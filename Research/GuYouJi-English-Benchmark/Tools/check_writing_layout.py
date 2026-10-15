#!/usr/bin/env python3
"""Bind one writing task, aggregate target, fixed text and required source inputs."""
import argparse
import json
import re
from pathlib import Path
from grade_mode_evidence import BASE, evidence, load_ref
from audit_school_material_families import digest, material_text, remove_offsets

MANIFEST = BASE / 'FirstRelease/Sampling/writing-material-views-v0.2.json'
VISUAL_SUPPLEMENTS = BASE / 'FirstRelease/Sampling/writing-visual-supplements-v0.1.json'


def layouts(manifest=MANIFEST):
    rows = {r['id']: r for r in evidence()}
    result = {}
    for case in json.loads(manifest.read_text())['views']:
        row = rows[case['group_id']]
        if row.get('source_text_ref') != case['source_text']:
            raise ValueError('Writing source differs from structural evidence')
        view = load_ref(case['source_text']).read_text()
        primary = material_text(case, view)
        remove_offsets(primary, case['excluded_offsets'], ' ')
        components = case['components']
        for c in components:
            text = view[c['start_offset']:c['end_offset']]
            if digest(text) != c['sha256'] or '【答案】' in text or '参考答案' in text:
                raise ValueError('Changed writing input or private model-answer boundary')
        contract = case['writing_contract']
        shape = row['shape']
        details, continuation = shape['details'], shape['family'] == 'read_then_continue'
        if shape['responses'] != 1 or contract['task_units'] != 1 or contract['target_scope'] != 'whole_task':
            raise ValueError('Writing paragraph fields are not separate tasks or targets')
        if contract['output_fields'] != (2 if continuation else 1) or contract['output_paragraphs'] != (2 if continuation else None):
            raise ValueError('Output field/paragraph structure differs')
        if contract['word_target'] != details['word_target'] or contract['target_relation'] != details['target_relation'] or contract['about_tolerance_established']:
            raise ValueError('Target number/relation or unsupported tolerance differs')
        instructions = [components[i] for i in contract['instruction_components']]
        if not instructions or any(c['role'] != 'student_instruction' for c in instructions):
            raise ValueError('Writing instruction missing')
        instruction_text = ' '.join(view[c['start_offset']:c['end_offset']] for c in instructions)
        target = str(contract['word_target'])
        if contract['target_relation'] == 'at_least':
            if not re.search(r'不少于\s*' + target, instruction_text):
                raise ValueError('Printed lower bound absent')
        elif contract['target_relation'] == 'about':
            if not re.search(target + r'[^\n]{0,6}左右', instruction_text):
                raise ValueError('Printed approximate target absent')
        else:
            raise ValueError('Unknown writing target relation')
        fixed = [components[i] for i in contract['fixed_student_components']]
        openings = [components[i] for i in contract['given_paragraph_openings']]
        if continuation and (len(openings) != 2 or any(c['role'] != 'given_paragraph_opening' for c in openings) or openings != sorted(openings, key=lambda c: c['start_offset'])):
            raise ValueError('Two source paragraph openings missing/reordered')
        if not continuation and openings:
            raise ValueError('Application/picture task cannot inherit two continuation openings')
        if any(c['start_offset'] < max(i['end_offset'] for i in instructions) for c in fixed):
            raise ValueError('Scenario quotation mistaken for supplied student text')
        if any(c['excluded_from_student_word_target'] not in [True, None] for c in fixed):
            raise ValueError('Unstated fixed-text inclusion cannot become a scoring rule')
        if any(c['excluded_from_student_word_target'] is True for c in fixed) and not ('不计入' in instruction_text):
            raise ValueError('Word-target exclusion lacks printed evidence')
        vocabulary = [components[i] for i in contract.get('supplied_vocabulary_components', [])]
        if any(c['role'] != 'supplied_vocabulary' for c in vocabulary) or set(contract.get('supplied_vocabulary_components', [])) & set(contract['instruction_components'] + contract['fixed_student_components']):
            raise ValueError('Supplied vocabulary cannot be counted again as fixed output or instruction')
        if contract['missing_required_inputs'] and row['necessary_input_complete'] is True:
            raise ValueError('Missing figure/chart is not complete student input')
        if contract['independent_rubric_complete'] or contract['grade_derived_from_survey_subject']:
            raise ValueError('Task topic/source model answer cannot validate grade or rubric')
        result[row['id']] = {'source_shape': shape, 'source_text': case['source_text'],
                             'primary_input_role': case['primary_input_role'], 'primary_input_sha256': digest(primary),
                             'contract': contract, 'fixed_student_text': fixed, 'instructions': instructions,
                             **({'supplied_vocabulary': vocabulary} if vocabulary else {}),
                             'necessary_input_complete': row['necessary_input_complete'],
                             'source_risks': case['source_defects']}
    return result


def check_visual_supplement(request, gid, layout):
    """Validate a reviewed linked chart while retaining the frozen missing state."""
    definition = {'path': str(VISUAL_SUPPLEMENTS.relative_to(BASE)),
                  'sha256': digest(VISUAL_SUPPLEMENTS.read_text())}
    if request.get('definition') != definition:
        raise ValueError('Writing visual supplement definition differs')
    bundles = json.loads(load_ref(definition).read_text())['bundles']
    matches = [b for b in bundles if b['id'] == request.get('bundle_id') and b['evidence_group_id'] == gid]
    if len(matches) != 1:
        raise ValueError('Writing visual supplement belongs to another task')
    bundle = matches[0]
    manifest_ref = {'path': str(MANIFEST.relative_to(BASE)), 'sha256': digest(MANIFEST.read_text())}
    if (bundle['source_text'] != layout['source_text'] or bundle['writing_view_manifest'] != manifest_ref or
            bundle['resolved_required_inputs'] != layout['contract']['missing_required_inputs'] or
            bundle['frozen_source_input_complete_preserved'] is not layout['necessary_input_complete'] or
            not bundle['author_prepared_student_bundle_complete'] or bundle['source_key_gold'] or
            bundle['independent_rubric_complete'] or bundle['commercial_admission'] or bundle['original_edition_authenticated']):
        raise ValueError('Writing chart source, dependency or review status differs')
    assets = bundle['required_student_assets']
    if request.get('included_student_assets') != assets or len(assets) != 1:
        raise ValueError('Necessary writing chart must accompany frozen text')
    review = json.loads(load_ref(bundle['visual_review']).read_text())
    if (review['evidence_group_id'] != gid or review['frozen_source_text'] != layout['source_text'] or
            review['mirror_html'] != bundle['mirror_html'] or review['image'] != assets[0] or
            review['graph'] != bundle['graph'] or not review['pixels_actually_visually_read']):
        raise ValueError('Chart review belongs to another writing input')
    mirror = load_ref(bundle['mirror_html']).read_text()
    span = review['mirror_prompt_span'];block = mirror[span['start_offset']:span['end_offset']]
    if digest(block) != span['sha256'] or ('src=' + review['image_link_in_prompt_block']) not in block:
        raise ValueError('Mirror chart is not linked from the selected writing prompt')
    import html
    text = html.unescape(re.sub('<[^>]+>', ' ', block))
    source_raw = load_ref(layout['source_text']).read_text()
    case = next(v for v in json.loads(load_ref(manifest_ref).read_text())['views'] if v['group_id'] == gid)
    source = source_raw[min(c['start_offset'] for c in case['components']):max(c['end_offset'] for c in case['components'])]
    if any(marker not in text or marker not in source for marker in review['prompt_identity_markers']):
        raise ValueError('Selected writing prompt identity differs')
    from PIL import Image
    with Image.open(load_ref(assets[0])) as image:
        if list(image.size) != review['image_dimensions'] or image.format != review['image_format']:
            raise ValueError('Writing chart pixels/dimensions differ')
        image.verify()
    if any(request.get(k) for k in ['claim_original_edition_authenticated', 'claim_rubric_complete', 'claim_student_calibrated', 'claim_commercial_admission']):
        raise ValueError('Linked mirror input is not original authentication or independent validation')
    return {'bundle_id': bundle['id'], 'prepared_student_bundle_complete': True,
            'original_edition_authenticated': False, 'independent_rubric_complete': False}


def check(request, available):
    gid = request.get('evidence_group_id')
    if gid not in available or request.get('layout') != available[gid]:
        raise ValueError('Writing source/task/paragraph/target/exclusion/required-input layout differs')
    state = available[gid]['necessary_input_complete']
    supplement = check_visual_supplement(request['visual_supplement'], gid, available[gid]) if 'visual_supplement' in request else None
    if request.get('requires_complete_student_input', True) and state is not True and supplement is None:
        raise ValueError('Required source writing input missing or unconfirmed')
    if request.get('use_as_verified_answer_gold') or request.get('claim_production_supported'):
        raise ValueError('Writing layout is not an independent rubric or production support')
    return {'source_writing_layout_matches': True, 'evidence_group_id': gid,
            'task_units': 1, 'output_fields': available[gid]['contract']['output_fields'],
            'necessary_input_complete': state, 'independent_rubric_complete': False,
            'prepared_student_bundle_complete': state is True or supplement is not None,
            **({'visual_supplement': supplement} if supplement is not None else {}),
            'model_called': False, 'production_supported': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--request', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(check(json.loads(args.request.read_text()), layouts()), ensure_ascii=False))
