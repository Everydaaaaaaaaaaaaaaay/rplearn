#!/usr/bin/env python3
"""Compare frozen prepared source passages with current spans without copying corpora."""
import argparse
import json
from itertools import combinations
from pathlib import Path
from grade_mode_evidence import BASE, evidence, load_ref
from audit_school_material_families import digest, material_text, remove_offsets, normalize_view
from audit_cloze_materials import normalized, shingles
from profile_task_load import count

MANIFEST = BASE / 'FirstRelease/Sampling/baseline-prepared-material-views-v0.1.json'
ALIASES = {'grade8-changjun2024-readingC-explanation-actual-text': 'g8.changjun2024.readingC',
           'g8.fengtai2026.readingD.author_transcription': 'g8.fengtai2026.readingD'}


def prepared_views(manifest):
    overview = json.loads(load_ref(manifest['baseline_source_overview']).read_text())
    parents = {r['id']: r['parent_paper_id'] for r in overview['groups']}
    structures = {r['id']: r for r in evidence()}
    acquisitions = {r['id']: r for r in json.loads((BASE / 'Registry/acquisitions.json').read_text())['acquisitions']}
    rows, bodies, loaded = [], {}, {}
    def read(ref):
        identity = (ref['path'], ref['sha256'])
        if identity not in loaded:
            loaded[identity] = load_ref(ref)
        return loaded[identity]
    for case in manifest['views']:
        gid = case['group_id']
        row = structures[gid]
        if row['layer'] != 'baseline_selected117' or parents[gid] != case['source_parent_id']:
            raise ValueError('Prepared text belongs to another source layer/parent')
        for identity, ref in [(case['source_parent_id'], case['parent_document']),
                              (case['prepared_acquisition_id'], case['prepared_file'])]:
            registered = acquisitions[identity]
            if ref != {'path': registered['path'], 'sha256': registered['sha256']}:
                raise ValueError('Document differs from registered parent/prepared source')
        read(case['parent_document'])
        catalogue = json.loads(read(case['source_catalogue']).read_text())
        matches = [r for r in catalogue['groups'] if r['id'] == gid]
        if len(matches) != 1 or matches[0]['question_numbers'] != case['printed_source_question_numbers']:
            raise ValueError('Source question sequence differs from catalogue')
        obs = matches[0]
        if obs.get('acquisition_id', obs.get('source_paper_acquisition_id')) != case['source_parent_id'] or obs['grade'] != row['shape']['grade']:
            raise ValueError('Catalogue source/grade differs')
        prepared = json.loads(read(case['prepared_file']).read_text())
        index = case['prepared_record_index']
        record = prepared['records'][index] if index is not None else prepared
        rid = record.get('id', record.get('group_id'))
        if rid != case['prepared_record_id'] or ALIASES.get(rid, rid) != gid:
            raise ValueError('Prepared record/explicit alias differs')
        if index is not None:
            if 'source' not in record['origin'] or record['grade'] != row['shape']['grade'] or record['options_each'] != row['shape']['options_each']:
                raise ValueError('Author sample/grade/options cannot become source material')
            if record['item_ids'] != case['prepared_item_ids']:
                raise ValueError('Prepared response order differs')
            expected_pointers = [['records', index, 'components', i, 'text'] for i in range(len(record['components']))]
            if [c['pointer'] for c in case['components']] != expected_pointers:
                raise ValueError('Selected components omit/reorder source or point into an author record')
            if any(c['role'] != original['role'] or c['id'] != original['id'] or c['item_id'] != original.get('item_id') for c, original in zip(case['components'], record['components'])):
                raise ValueError('Source component role/response binding differs')
            ev = record.get('evidence')
            if isinstance(ev, dict):
                parent = ev.get('acquisition_id', ev.get('paper_acquisition_id', ev.get('source_paper_acquisition_id')))
                if parent is not None and parent != case['source_parent_id']:
                    raise ValueError('Prepared evidence cites another parent')
                if ev.get('sha256') and ev['sha256'] != case['parent_document']['sha256']:
                    raise ValueError('Prepared evidence cites another parent version')
        elif record['paper_acquisition_id'] != case['source_parent_id']:
            raise ValueError('Open-source transcript belongs to another paper')
        else:
            expected_pointers = ([['author_transcribed_paragraphs', i] for i in range(len(record['author_transcribed_paragraphs']))] +
                                 [['prompts', i] for i in range(len(record['prompts']))])
            if [c['pointer'] for c in case['components']] != expected_pointers:
                raise ValueError('Open-source paragraph/prompt allocation differs')
        parts, roles = [], {}
        for component in case['components']:
            value = prepared
            for key in component['pointer']:
                value = value[key]
            if not isinstance(value, str) or digest(value) != component['sha256'] or component['role'] not in ['passage', 'material_label', 'instruction', 'prompt', 'option']:
                raise ValueError('Changed/non-student source component')
            if component['role'] == 'passage':
                parts.append(value)
            totals = roles.setdefault(component['role'], {'english_digit_tokens': 0, 'han_characters': 0, 'components': 0})
            for k, v in count(value).items():
                totals[k] += v
            totals['components'] += 1
        if not parts or roles.get('prompt', {}).get('components') != row['shape']['responses'] or len(case['prepared_item_ids']) != row['shape']['responses']:
            raise ValueError('Passage/prompt/response allocation incomplete')
        options = [c for c in case['components'] if c['role'] == 'option']
        if any(sum(c['item_id'] == i for c in options) != (row['shape']['options_each'] or 0) for i in case['prepared_item_ids']):
            raise ValueError('Per-response source options incomplete')
        body = '\n'.join(parts)
        norm = normalized(body)
        if gid in bodies:
            raise ValueError('Duplicate prepared version cannot add an instance')
        bodies[gid] = norm
        rows.append({'group_id': gid, 'grade': row['shape']['grade'], 'paper_identity': parents[gid],
                     'prepared_source': case['prepared_file'], 'material_sha256': digest(body),
                     'normalized_material_sha256': digest(norm), 'material_counts': count(body),
                     'component_counts': roles, 'responses': row['shape']['responses'],
                     'options_each': row['shape']['options_each'], 'necessary_student_input_complete': row['necessary_input_complete'],
                     'comparison_scope': case['scope'], 'independent_transcription': False,
                     'independent_answer_gold': False, 'commercial_admission': False})
    return rows, bodies


def prior_bodies(manifest):
    layer = json.loads(load_ref(manifest['prior_view_manifest']).read_text())
    layers = [layer]
    while layers[-1].get('prior_view_manifest'):
        layers.append(json.loads(load_ref(layers[-1]['prior_view_manifest']).read_text()))
    frozen = json.loads(load_ref(layers[-1]['frozen_nineteen_audit']).read_text())
    bodies = {}
    for r in frozen['records']:
        text = load_ref(r['source_text']).read_text();a, b = r['material_line_span_1based']
        material = '\n'.join(text.splitlines()[a - 1:b]).strip()
        offsets = [{'start': x, 'end': y, 'literal': material[x:y]} for x, y, _ in r['blank_offsets_in_material']]
        bodies[r['group_id']] = normalized(remove_offsets(material, offsets))
    for layer in reversed(layers):
        for case in layer['views']:
            text = load_ref(case['source_text']).read_text()
            material = remove_offsets(material_text(case, text), case['excluded_offsets'], ' ' if case.get('replace_exclusions_with_space') else '')
            if case['group_id'] in bodies:
                raise ValueError('Repeated prior material')
            bodies[case['group_id']] = normalize_view(material, case.get('normalization'))
    prior = json.loads(load_ref(manifest['prior_material_audit']).read_text())
    for row in prior['records']:
        if digest(bodies[row['group_id']]) != row['normalized_material_sha256']:
            raise ValueError('Prior normalization changed; cannot reuse prior pair coverage')
    if len(bodies) != len(prior['records']):
        raise ValueError('Prior material inventory differs')
    return bodies, prior


def audit():
    manifest = json.loads(MANIFEST.read_text())
    records, new = prepared_views(manifest)
    old, prior = prior_bodies(manifest)
    if set(old).intersection(new):
        raise ValueError('Prepared source already included')
    bodies = dict(old, **new);comparisons = []
    for left, right in combinations(bodies, 2):
        if left in old and right in old:
            continue
        a, b = shingles(bodies[left]), shingles(bodies[right])
        jaccard = len(a & b) / len(a | b) if a | b else 0
        containment = len(a & b) / min(len(a), len(b)) if a and b else 0
        exact = bodies[left] == bodies[right]
        comparisons.append({'left': left, 'right': right, 'exact_normalized_match': exact,
                            'fivegram_jaccard': jaccard, 'fivegram_containment': containment,
                            'review_candidate': exact or jaccard >= .5 or containment >= .8})
    prior_pairs = prior['pair_count_total'];total = len(bodies) * (len(bodies) - 1) // 2
    if total != prior_pairs + len(comparisons):
        raise ValueError('Cross-layer pair coverage differs')
    return {'version': '0.1', 'prior_records_and_comparisons': manifest['prior_material_audit'],
            'records': records, 'material_count_total': len(bodies),
            'parent_count_total': len({r['paper_identity'] for r in prior['records'] + records}),
            'prior_pairs_reused': prior_pairs, 'new_pair_count': len(comparisons), 'pair_count_total': total,
            'comparisons': comparisons, 'exact_repeat_pairs': prior['exact_repeat_pairs'] + sum(c['exact_normalized_match'] for c in comparisons),
            'review_candidates': prior['review_candidates'] + sum(c['review_candidate'] for c in comparisons),
            'all_benchmark_deduplication_complete': False, 'prepared_source_versions_not_new_paper_or_group_instances': True,
            'material_labels_not_folded_into_passage_counts': True, 'source_media_and_semantic_paraphrases_not_screened': True,
            'zero_candidates_not_independent_families_or_validated_capacity': True, 'model_called': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    from grade_mode_evidence import REPO
    if (REPO / 'build').resolve() not in args.output.resolve().parents:
        parser.error('Derived source profiles must stay in ignored build/')
    result = audit();payload = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if args.output.exists() and args.output.read_text() != payload:
        raise ValueError('Refuse to overwrite a different prepared-source audit')
    if not args.output.exists():
        args.output.write_text(payload)
    print(json.dumps({k: result[k] for k in ['material_count_total', 'parent_count_total', 'new_pair_count', 'prior_pairs_reused', 'pair_count_total', 'exact_repeat_pairs', 'review_candidates']}))
