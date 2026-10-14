#!/usr/bin/env python3
"""Read frozen native-page pointers, never infer empty text means a missing paper."""
import argparse
import json
import re
from itertools import combinations
from pathlib import Path
from grade_mode_evidence import BASE, evidence, load_ref
from audit_school_material_families import digest, remove_offsets
from audit_baseline_prepared_materials import prepared_views, prior_bodies
from audit_cloze_materials import normalized, shingles
from profile_task_load import count

MANIFEST = BASE / 'FirstRelease/Sampling/baseline-native-material-views-v0.1.json'
DECORATION = re.compile(r'(?m)^\s*第\d+页/共\d+页\s*$|(?m:^学科 网（北 京）股 份有限 公司\s*$)|(?m:^进入北京高考在线网站：[^\n]+$)')


def native_views(manifest):
    acquisitions = {r['id']: r for r in json.loads((BASE / 'Registry/acquisitions.json').read_text())['acquisitions']}
    rows = {r['id']: r for r in evidence()}
    cached = {}
    def document(ref):
        key = (ref['path'], ref['sha256'])
        if key not in cached:
            cached[key] = load_ref(ref)
        return cached[key]
    def page_text(case):
        parent = acquisitions[case['source_parent_id']]
        snapshot = acquisitions[case['snapshot_acquisition_id']]
        for expected, actual in [(case['parent_document'], parent), (case['snapshot'], snapshot)]:
            if expected != {'path': actual['path'], 'sha256': actual['sha256']}:
                raise ValueError('Native snapshot/parent differs from registered version')
            document(expected)
        data = json.loads(document(case['snapshot']).read_text())
        values = []
        for page in case['pages']:
            value = data
            for key in page['pointer']:
                value = value[key]
            if not isinstance(value, str) or digest(value) != page['sha256']:
                raise ValueError('Frozen page pointer/text changed')
            # Each pointer must address the source's declared page, not arbitrary audit text.
            p = page['pointer']
            if p[-1] != str(page['PDF_page']) or p[0] not in ['native_source_pages_private', 'native_pages_private', 'grade12_native_pages_private']:
                raise ValueError('Native pointer is not a declared original page')
            if p[0] == 'native_source_pages_private' and p[1] != case['source_parent_id']:
                raise ValueError('Native page belongs to another source')
            if p[0] == 'native_pages_private' and data.get('parent_acquisition_id') != case['source_parent_id']:
                raise ValueError('Curated native pages belong to another source')
            if p[0] == 'grade12_native_pages_private' and case['source_parent_id'] != 'grade12-jianghuai2024-firstjoint-20261013':
                raise ValueError('Single grade12 snapshot belongs to another parent')
            values.append(value)
        joined = '\n'.join(values)
        if digest(joined) != case['joined_text_sha256']:
            raise ValueError('Joined native page view changed')
        return joined
    records, bodies = [], {}
    for case in manifest['views']:
        row = rows[case['group_id']]
        if row['layer'] != 'baseline_selected117' or row['paper_id'] != case['source_parent_id']:
            raise ValueError('Native view belongs to another source layer/parent')
        catalogue = json.loads(document(case['source_catalogue']).read_text())
        obs = next(o for o in catalogue['groups'] if o['id'] == row['id'])
        if obs['acquisition_id'] != case['source_parent_id'] or obs['grade'] != row['shape']['grade']:
            raise ValueError('Native source catalogue/grade/parent differs')
        if [p['PDF_page'] for p in case['pages']] != obs['material_and_question_PDF_pages']:
            raise ValueError('Native pages differ from observed group scope')
        text = page_text(case)
        a, b = case['material_start_offset'], case['material_end_offset']
        raw = text[a:b]
        if not 0 <= a < b <= len(text) or digest(raw) != case['material_sha256']:
            raise ValueError('Native material boundary changed')
        measured = remove_offsets(raw, case['excluded_offsets'], ' ')
        blanks = sorted([r for r in case['excluded_offsets'] if r['role'] == 'blank_label'], key=lambda r: r['start'])
        if [r['blank_id'] for r in blanks] != case['expected_blank_ids']:
            raise ValueError('Native blank order differs')
        if row['shape']['family'] == 'choice_cloze' and case['expected_blank_ids'] != obs['question_numbers']:
            raise ValueError('Complete cloze slots differ from source')
        q = case['question_region'];region = text[q['start_offset']:q['end_offset']]
        if digest(region) != q['sha256'] or q['printed_source_question_numbers'] != obs['question_numbers']:
            raise ValueError('Question region/version differs')
        clean = DECORATION.sub(' ', region)
        matches = list(re.finditer(r'(?m)^\s*(?:\(\s*\)\s*)?(\d+)[.．]\s+', clean))
        if [int(m[1]) for m in matches] != obs['question_numbers'] or len(matches) != row['shape']['responses']:
            raise ValueError('Native question sequence/response count incomplete')
        option_count = 0
        for i, match in enumerate(matches):
            unit = clean[match.end():matches[i + 1].start() if i + 1 < len(matches) else len(clean)]
            options = re.findall(r'(?<!\S)([A-D])[.．]', unit)
            if options != list('ABCD'[:row['shape']['options_each']]):
                raise ValueError('Native per-response option set missing or duplicated')
            option_count += len(options)
        gid = row['id']
        if gid in bodies:
            raise ValueError('Duplicate native version is not a new instance')
        norm = normalized(measured);bodies[gid] = norm
        records.append({'group_id': gid, 'grade': row['shape']['grade'], 'paper_identity': row['paper_id'],
                        'snapshot': case['snapshot'], 'material_sha256': digest(raw),
                        'normalized_material_sha256': digest(norm), 'material_counts': count(measured),
                        'responses': len(matches), 'option_positions_verified': option_count,
                        'question_region_counts_with_labels': count(clean),
                        'native_spacing_not_repaired': True, 'source_defects': case['source_defects'],
                        'necessary_student_input_complete': row['necessary_input_complete'],
                        'independent_answer_gold': False, 'source_media_not_profiled': True})
    empty = []
    for case in manifest['native_empty_instances']:
        if page_text(case).strip():
            raise ValueError('Native-empty state differs from frozen page strings')
        empty.append({'group_id': case['group_id'], 'native_text_empty': True,
                      'original_paper_missing': False, 'student_input_completeness_inferred': False})
    return records, bodies, empty


def audit():
    manifest = json.loads(MANIFEST.read_text())
    records, new, empty = native_views(manifest)
    prepared_manifest = json.loads(load_ref(manifest['prior_view_manifest']).read_text())
    old, older = prior_bodies(prepared_manifest)
    prepared, prepared_bodies = prepared_views(prepared_manifest)
    if set(old).intersection(prepared_bodies):
        raise ValueError('Repeated old/prepared source identity')
    old.update(prepared_bodies)
    prior = json.loads(load_ref(manifest['prior_material_audit']).read_text())
    if len(old) != prior['material_count_total'] or any(digest(old[r['group_id']]) != r['normalized_material_sha256'] for r in prior['records']):
        raise ValueError('Previous prepared source normalization differs')
    if set(old).intersection(new):
        raise ValueError('Native view already screened')
    bodies = dict(old, **new);comparisons = []
    for left, right in combinations(bodies, 2):
        if left in old and right in old:
            continue
        a, b = shingles(bodies[left]), shingles(bodies[right]);exact = bodies[left] == bodies[right]
        jac = len(a & b) / len(a | b) if a | b else 0
        con = len(a & b) / min(len(a), len(b)) if a and b else 0
        comparisons.append({'left': left, 'right': right, 'exact_normalized_match': exact,
                            'fivegram_jaccard': jac, 'fivegram_containment': con,
                            'review_candidate': exact or jac >= .5 or con >= .8})
    total = len(bodies) * (len(bodies) - 1) // 2
    if total != prior['pair_count_total'] + len(comparisons):
        raise ValueError('Cross-layer comparison coverage differs')
    return {'version': '0.1', 'records_scope': 'nine new native profiles; earlier201 via frozen references',
            'prior_records_and_comparisons': manifest['prior_material_audit'], 'records': records,
            'native_empty_instances': empty, 'material_count_total': len(bodies),
            'parent_count_total': len({r['paper_identity'] for r in older['records'] + prepared + records}),
            'pair_count_total': total, 'prior_pairs_reused': prior['pair_count_total'], 'new_pair_count': len(comparisons),
            'comparisons': comparisons, 'exact_repeat_pairs': prior['exact_repeat_pairs'] + sum(c['exact_normalized_match'] for c in comparisons),
            'review_candidates': prior['review_candidates'] + sum(c['review_candidate'] for c in comparisons),
            'all_benchmark_deduplication_complete': False, 'zero_candidates_not_independent_families': True,
            'source_media_shared_options_semantic_paraphrases_not_screened': True, 'model_called': False}


def question_components():
    manifest = json.loads(MANIFEST.read_text())
    verified, _, _ = native_views(manifest)
    source_by = {r['group_id']: r for r in verified}
    records = []
    for case in manifest['views']:
        data = json.loads(load_ref(case['snapshot']).read_text());pages = []
        for page in case['pages']:
            value = data
            for key in page['pointer']:
                value = value[key]
            pages.append(value)
        text = '\n'.join(pages);q = case['question_region']
        clean = DECORATION.sub(' ', text[q['start_offset']:q['end_offset']])
        matches = list(re.finditer(r'(?m)^\s*(?:\(\s*\)\s*)?(\d+)[.．]\s+', clean))
        units = [];totals = {role: {'english_digit_tokens': 0, 'han_characters': 0} for role in ['prompt', 'option']}
        for i, match in enumerate(matches):
            unit = clean[match.end():matches[i + 1].start() if i + 1 < len(matches) else len(clean)]
            labels = list(re.finditer(r'(?<!\S)([A-D])[.．]', unit))
            prompt = unit[:labels[0].start()].strip()
            options = [unit[label.end():labels[j + 1].start() if j + 1 < len(labels) else len(unit)].strip() for j, label in enumerate(labels)]
            pc = count(prompt);oc = {k: sum(count(option)[k] for option in options) for k in pc}
            for key in pc:
                totals['prompt'][key] += pc[key];totals['option'][key] += oc[key]
            units.append({'printed_question_number': int(match[1]), 'prompt_counts': pc, 'option_counts': oc,
                          'option_positions': len(options), 'prompt_sha256': digest(prompt),
                          'option_sha256s': [digest(t) for t in options]})
        if len(units) != source_by[case['group_id']]['responses']:
            raise ValueError('Sparse component profile loses native responses')
        records.append({'group_id': case['group_id'], 'frozen_question_region': q, 'by_role': totals, 'units': units,
                        'cloze_has_zero_isolated_stems_not_missing_passage': all(not any(u['prompt_counts'].values()) for u in units),
                        'labels_and_page_decorations_not_in_prompt_or_options': True, 'native_spacing_not_repaired': True})
    return {'version': '0.1', 'scope': 'nine frozen native question regions; sparse companion profile referencing prior material audit',
            'records': records, 'model_called': False, 'source_gold': False, 'source_counts_not_grade_thresholds': True}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--components-only', action='store_true')
    args = parser.parse_args()
    from grade_mode_evidence import REPO
    if (REPO / 'build').resolve() not in args.output.resolve().parents:
        parser.error('Source-derived report must stay in ignored build/')
    result = question_components() if args.components_only else audit()
    payload = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if args.output.exists() and args.output.read_text() != payload:
        raise ValueError('Do not overwrite a different native audit')
    if not args.output.exists():
        args.output.write_text(payload)
    if args.components_only:
        print(json.dumps({'groups': len(result['records']), 'responses': sum(len(r['units']) for r in result['records'])}))
    else:
        print(json.dumps({k: result[k] for k in ['material_count_total', 'parent_count_total', 'pair_count_total', 'new_pair_count', 'exact_repeat_pairs', 'review_candidates']}))
