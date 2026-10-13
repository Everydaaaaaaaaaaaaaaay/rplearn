#!/usr/bin/env python3
"""Validate metadata for the two currently authored Suzhou expansion modes.

Checks declarations and local source/version relations, not model or English quality.
"""
import argparse
import hashlib
import json
from pathlib import Path

BASE = Path(__file__).resolve().parents[1]
REPO = BASE.parents[1]
SOURCE_PATH = 'FirstRelease/Expansions/grade9-suzhou2024-official-written-groups-v0.1.json'
SPEC_PATH = 'FirstRelease/Specifications/grade9-v0.3.md'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'))


def file_ref(ref):
    path = Path(ref['path'])
    if path.is_absolute() or '..' in path.parts:
        raise ValueError('nonportable or escaping document reference')
    actual = BASE / path
    if BASE.resolve() not in actual.resolve().parents or not actual.is_file():
        raise ValueError('document reference outside benchmark or absent')
    if digest(actual) != ref['sha256']:
        raise ValueError('document version digest differs')
    return actual


def cached(record):
    path = Path(record['path'])
    if path.is_absolute() or '..' in path.parts or not path.parts or path.parts[0] != 'build':
        raise ValueError('nonportable cache reference')
    actual = REPO / path
    if (REPO / 'build').resolve() not in actual.resolve().parents:
        raise ValueError('cache reference escapes build')
    if actual.stat().st_size != record['bytes'] or digest(actual) != record['sha256']:
        raise ValueError('cached source version differs')
    return actual


def check(request):
    errors = []
    files_checked = []
    try:
        if request['source_extension_ref']['path'] != SOURCE_PATH:
            raise ValueError('unsupported source expansion catalog')
        source = json.loads(file_ref(request['source_extension_ref']).read_text())
        if request['specification']['path'] != SPEC_PATH:
            raise ValueError('wrong expansion specification')
        file_ref(request['specification'])
        group = next(g for g in source['groups'] if g['id'] == request['source_group_id'])
        if request['grade'] != group['grade'] or request['grade'] != source['reference_grade']:
            raise ValueError('wrong grade')
        if not group['complete_selected_group_visually_reviewed']:
            raise ValueError('complete source group not available')
        if request['source_paper_acquisition_id'] != group['source_paper_acquisition_id'] or request['source_reference_key_acquisition_id'] != group['source_reference_key_acquisition_id']:
            raise ValueError('source paper/key family differs')
        acquisitions = {a['id']: a for a in json.loads((BASE / 'Registry/acquisitions.json').read_text())['acquisitions']}
        for identity in [group['source_paper_acquisition_id'], group['source_reference_key_acquisition_id']]:
            record = acquisitions[identity]
            actual = cached(record)
            # Actual bytes are WebP even though the publisher's URL/header says PNG.
            prefix = actual.read_bytes()[:12]
            if record.get('actual_byte_format') != 'WEBP' or prefix[:4] != b'RIFF' or prefix[8:12] != b'WEBP':
                raise ValueError('actual source format identity differs')
            files_checked.append(identity)
        private_record = acquisitions[source['private_review_acquisition_id']]
        private_path = cached(private_record)
        if digest(private_path) != source['private_review_sha256']:
            raise ValueError('private author review version differs')
        detail = next(g for g in json.loads(private_path.read_text())['groups'] if g['group_id'] == group['id'])
        if [i['source_number'] for i in detail['items']] != group['question_numbers'] or any(not i['author_analysis'].strip() for i in detail['items']):
            raise ValueError('source item pairing/reasons incomplete')
        files_checked.append(source['private_review_acquisition_id'])
        expected = {'items': len(group['question_numbers']), 'features': group['features']}
        if canonical(request['source_format']) != canonical(expected):
            raise ValueError('source mode or response limits changed')
        target = request['target_format']
        if group['kind'] == 'readingA':
            if canonical(target) != canonical({'items': 3, 'options_each': 4, 'shared_materials': 1, 'table_rows': 6, 'table_columns': 3}):
                raise ValueError('wrong complete text/table reading target mode')
        elif group['kind'] == 'wordBank':
            if canonical(target) != canonical({'items': 5, 'bank_entries': 5, 'entry_once': True, 'complete_prose_and_schematic': True, 'all_responses_oneword': False, 'verbal_combinations_allowed_as_authored_rule': True}):
                raise ValueError('wrong five-entry word/phrase target mode')
        else:
            raise ValueError('other source modes not yet supported by this request control')
        positive = request['positive_source_reference_numbers']
        if not isinstance(positive, list) or len(set(positive)) != len(positive) or not set(positive).issubset(group['question_numbers']):
            raise ValueError('positive references do not belong to selected complete group')
        if request['source_reference_list_exhaustive'] is not False or request['all_shared_material_required'] is not True:
            raise ValueError('source exhaustiveness or incomplete material claim')
        changes = request['target_changes_and_justification']
        if not isinstance(request['new_scenario'], str) or not request['new_scenario'].strip() or not isinstance(changes, list) or not changes or any(not isinstance(x, str) or not x.strip() for x in changes):
            raise ValueError('new context and explained target changes required')
        required = {'complete_student_material', 'per_item_evidence_and_alternatives', 'whole_group_solve_or_refill', 'actual_revision_evidence_if_changed', 'independent_unknowns_separate'}
        output = request['author_output_required']
        if not isinstance(output, list) or not all(isinstance(x, str) for x in output) or not required.issubset(output):
            raise ValueError('author evidence output requirements missing')
        if any(k in request for k in ['source_full_text', 'source_text_payload']):
            raise ValueError('metadata request embeds source body')
        for field in ['original_source_republication_admitted', 'commercial_training_admitted', 'third_party_source_transmission_admitted', 'independent_review', 'student_calibration', 'production_admission', 'source_factual_gold']:
            if request.get(field) is not False:
                raise ValueError('unsupported admission: ' + field)
        if request['fact_strategy'] != 'fictional_context_and_numbers_not_source_claims_as_fact':
            raise ValueError('source factual claims silently certified')
        display = request['student_display']
        if display != {'avatar_next_to_instruction_only': True, 'independent_character_opening_story': False, 'correct_title_leaked': False}:
            raise ValueError('display conflicts with agreed task scope')
    except (KeyError, ValueError, OSError, TypeError, AttributeError, StopIteration) as exc:
        errors.append(str(exc) or type(exc).__name__)
    return {'metadata_and_source_bindings_valid': not errors, 'errors': errors,
            'actual_cached_source_files_checked': files_checked,
            'model_called': False, 'source_body_transmitted': False,
            'independent_English_or_student_validation': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--request', required=True)
    args = parser.parse_args()
    report = check(json.loads(Path(args.request).read_text()))
    print(json.dumps(report, ensure_ascii=False, indent=2))
    raise SystemExit(0 if report['metadata_and_source_bindings_valid'] else 1)
