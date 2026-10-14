#!/usr/bin/env python3
"""Profile source spans with bound questions, shared choices, grammar hints and media."""
import argparse
import json
import re
from itertools import combinations
from pathlib import Path
from grade_mode_evidence import BASE, REPO, evidence, load_ref
from audit_school_material_families import digest, remove_offsets
from audit_cloze_materials import normalized
from audit_baseline_bank_forms import compare
from audit_baseline_profiles import prior_materials, profile_views
from profile_task_load import count

MANIFEST = BASE / 'FirstRelease/Sampling/baseline-text-span-views-v0.1.json'


def span_views(manifest):
    sources = {r['id']: r for r in evidence()}
    acquisitions = {r['id']: r for r in json.loads((BASE / 'Registry/acquisitions.json').read_text())['acquisitions']}
    processing = {r['id']: r for r in json.loads((BASE / 'Registry/processing.json').read_text())['runs']}
    records, bodies, layouts = [], {}, {}
    for case in manifest['views']:
        row = sources[case['group_id']];family = row['shape']['family']
        if row['layer'] != 'baseline_selected117' or row['paper_id'] != case['source_parent_id'] or family != case['source_family']:
            raise ValueError('Source span layer/parent/family differs')
        parent = acquisitions[case['source_parent_id']]
        if case['parent_document'] != {'path': parent['path'], 'sha256': parent['sha256']}:
            raise ValueError('Original parent version differs')
        load_ref(case['parent_document'])
        obs = next(o for o in json.loads(load_ref(case['source_catalogue']).read_text())['groups'] if o['id'] == row['id'])
        if obs.get('acquisition_id', obs.get('source_paper_acquisition_id')) != row['paper_id'] or obs['grade'] != row['shape']['grade']:
            raise ValueError('Catalogue source identity differs')
        source_path = load_ref(case['text_source']);data = None
        if case['source_page_pointers']:
            a = acquisitions[case['text_source_acquisition_id']]
            if case['text_source'] != {'path': a['path'], 'sha256': a['sha256']}:
                raise ValueError('Native snapshot registration differs')
            origin = json.loads(load_ref(case['snapshot_origin_evidence']).read_text())
            if origin['path'] != parent['path'] or origin['sha256'] != parent['sha256'] or origin['native_text_path'] != case['text_source']['path']:
                raise ValueError('Native snapshot belongs to another original')
            data = json.loads(source_path.read_text());parts = []
            if [p['PDF_page'] for p in case['source_page_pointers']] != obs['material_and_question_PDF_pages']:
                raise ValueError('Declared native page scope differs')
            for page in case['source_page_pointers']:
                index = page['PDF_page'] - 1
                if page['pointer'] != [index, 'text'] or data[index]['PDF_page'] != page['PDF_page'] or digest(data[index]['text']) != page['sha256']:
                    raise ValueError('Native page/pointer/text differs')
                parts.append(data[index]['text'])
            text = '\n'.join(parts)
        else:
            run = processing[case['snapshot_processing_run_id']]
            if not any(r.get('source') == parent['path'] and r.get('output') == case['text_source']['path'] and r.get('sha256') == case['text_source']['sha256'] and r.get('exit_code') == 0 for r in run['page_records']):
                raise ValueError('HTML text processing belongs to another source')
            text = source_path.read_text()
        if digest(text) != case['joined_text_sha256']:
            raise ValueError('Joined source text differs')
        components = case['components'];by_id = {};counts = {};body = '';blanks = []
        for c in components:
            a, b = c['start'], c['end'];raw = text[a:b]
            if not 0 <= a < b <= len(text) or digest(raw) != c['sha256'] or c['id'] in by_id or c['role'] not in ['material', 'instruction', 'prompt', 'option', 'shared_option']:
                raise ValueError('Source component boundary/id/role differs')
            if any(t in raw for t in ['【答案】', '【解析】']):
                raise ValueError('Private references are not student input')
            clean = remove_offsets(raw, c['excluded_offsets'], ' ');by_id[c['id']] = c
            if c['role'] == 'material':
                if body:
                    raise ValueError('Unexpected second material')
                body = clean;blanks = [e for e in c['excluded_offsets'] if e['role'] == 'blank_label']
            role = counts.setdefault(c['role'], {'english_digit_tokens': 0, 'han_characters': 0, 'components': 0})
            for k, value in count(clean).items():
                role[k] += value
            role['components'] += 1
        shared_instruction = case.get('shared_instruction')
        if shared_instruction:
            p = shared_instruction;page = data[p['PDF_page'] - 1]
            if p['pointer'] != [p['PDF_page'] - 1, 'text'] or page['PDF_page'] != p['PDF_page'] or digest(page['text'][p['start']:p['end']]) != p['sha256']:
                raise ValueError('Shared section instruction differs')
            counts['instruction'] = dict(count(page['text'][p['start']:p['end']]), components=1)
        if 'instruction' not in counts:
            raise ValueError('Student section instruction omitted')
        media = case['required_media']
        for m in media:
            a = acquisitions[m['acquisition_id']]
            if m['asset'] != {'path': a['path'], 'sha256': a['sha256']} or not m['actually_visual_reviewed_this_batch'] or m['required_for_printed_number'] not in obs['question_numbers']:
                raise ValueError('Required media/source/response association differs')
            load_ref(m['asset'])
        if {m['acquisition_id'] for m in media} != set(obs.get('required_image_acquisition_ids', [])) and not (row['id'] == 'g12.national2025.readingA' and len(media) == 1 and media[0]['role'] == 'emissions_chart_and_two_fuel_panels'):
            raise ValueError('Necessary source image set differs')
        units = case['units'];numbers = obs['question_numbers']
        if [u['printed_number'] for u in units] != numbers or len(units) != row['shape']['responses']:
            raise ValueError('Whole response sequence differs')
        if family != 'reading_choice' and [b['blank_id'] for b in blanks] != numbers:
            raise ValueError('Material gap sequence differs')
        expected_shared = row['shape']['details'].get('shared_options', 0)
        if len(case['shared_options']) != expected_shared or [o['label'] for o in case['shared_options']] != list('ABCDEFG'[:expected_shared]):
            raise ValueError('Shared sentence candidate set differs')
        used = [];hint_count = 0;visual_choices = 0
        for u in units:
            if family != 'reading_choice' and u['blank'] != next(b for b in blanks if b['blank_id'] == u['printed_number']):
                raise ValueError('Response points to another material gap')
            options = u['option_components'];used += [o['component_id'] for o in options]
            if family in ['reading_choice', 'choice_cloze']:
                if u.get('image_choice_labels'):
                    if row['id'] != 'g7.2019.readingB' or u['printed_number'] != 51 or options or u['image_choice_labels'] != list('ABCD') or not media:
                        raise ValueError('Four visual options lack their source figure')
                    visual_choices += 4
                elif [o['label'] for o in options] != list('ABCD'):
                    raise ValueError('Per-response four-option set differs')
                if any(by_id[o['component_id']]['role'] != 'option' for o in options):
                    raise ValueError('Foreign/private response option')
                if family == 'reading_choice':
                    if by_id[u['prompt_component']]['role'] != 'prompt':
                        raise ValueError('Reading question omitted')
                    used.append(u['prompt_component'])
            elif options:
                raise ValueError('Free/shared gaps cannot become per-item choices')
            if family == 'passage_form':
                hint = u['given_hint'];hint_count += bool(hint)
                if u['word_limit'] != (None if hint else 1):
                    raise ValueError('Given/ungiven response policy differs')
                if hint:
                    material = components[0];raw = text[material['start']:material['end']];blank = u['blank']
                    if hint not in material['excluded_offsets'] or hint['blank_id'] != u['printed_number'] or raw[blank['end']:hint['start']].strip() or not re.fullmatch(r'\([^()]+\)', hint['literal']):
                        raise ValueError('Given hint moved to another gap')
        used += [o['component_id'] for o in case['shared_options']]
        if len(used) != len(set(used)) or set(used) != {c['id'] for c in components if c['role'] in ['prompt', 'option', 'shared_option']}:
            raise ValueError('Source prompt/options omitted/reused')
        norm = normalized(body);gid = row['id']
        if gid in bodies:
            raise ValueError('Repeated source group')
        bodies[gid] = norm
        records.append({'group_id': gid, 'paper_identity': row['paper_id'], 'grade': row['shape']['grade'], 'family': family,
                        'normalized_material_sha256': digest(norm), 'component_counts': counts, 'responses': len(units),
                        'text_option_positions': sum(len(u['option_components']) for u in units), 'visual_option_positions': visual_choices,
                        'shared_option_positions': len(case['shared_options']), 'given_hints': hint_count,
                        'required_media_assets': len(media), 'source_defects': case['source_defects'],
                        'current_text_and_media_author_reviewed': True, 'frozen_source_input_state': row['necessary_input_complete'],
                        'independent_gold': False, 'image_content_not_family_screened': True})
        layouts[gid] = {'source_shape': row['shape'], 'text_source': case['text_source'], 'joined_text_sha256': case['joined_text_sha256'],
                        'components': components, 'shared_instruction': shared_instruction, 'units': units, 'shared_options': case['shared_options'],
                        'required_media': media, 'frozen_source_input_state': row['necessary_input_complete'], 'source_scope_not_original_exam_number_mapping': True}
    return records, bodies, layouts


def ancestors(manifest):
    previous = json.loads(load_ref(manifest['prior_view_manifest']).read_text());old, records, _ = prior_materials(previous)
    new_records, new, _, _ = profile_views(previous)
    if set(old) & set(new):
        raise ValueError('Repeated prior source')
    old.update(new);records += new_records;prior = json.loads(load_ref(manifest['prior_material_audit']).read_text())
    if len(old) != prior['material_count_total'] or any(digest(old[r['group_id']]) != r['normalized_material_sha256'] for r in prior['records']):
        raise ValueError('Previous source normalization changed')
    return old, records, prior


def check(request, layouts):
    gid = request.get('evidence_group_id')
    if gid not in layouts or request.get('layout') != layouts[gid]:
        raise ValueError('Source material/instruction/response/choice/hint/media binding differs')
    if any(request.get(k) for k in ['use_as_verified_answer_gold', 'claim_original_exam_numbers', 'claim_production_supported', 'claim_image_family_screened']):
        raise ValueError('Source preparation is not gold, original numbering, production or visual deduplication')
    return {'source_span_layout_matches': True, 'evidence_group_id': gid, 'model_called': False, 'independent_gold': False, 'production_supported': False}


def audit():
    manifest = json.loads(MANIFEST.read_text());records, new, _ = span_views(manifest);old, old_records, prior = ancestors(manifest)
    if set(old) & set(new):
        raise ValueError('Source view already screened')
    comparisons = [{'left': left, 'right': right, **compare(a, b)} for left, a in new.items() for right, b in old.items()]
    comparisons += [{'left': left, 'right': right, **compare(new[left], new[right])} for left, right in combinations(new, 2)]
    total = len(old) + len(new);pairs = total * (total - 1) // 2
    if pairs != prior['pair_count_total'] + len(comparisons):
        raise ValueError('Text-view comparison coverage differs')
    return {'version': '0.1', 'prior_records_and_comparisons': manifest['prior_material_audit'], 'records': records,
            'material_count_total': total, 'parent_count_total': len({r['paper_identity'] for r in old_records + records}),
            'pair_count_total': pairs, 'prior_pairs_reused': prior['pair_count_total'], 'new_pair_count': len(comparisons), 'comparisons': comparisons,
            'exact_repeat_pairs': prior['exact_repeat_pairs'] + sum(c['exact_normalized_match'] for c in comparisons),
            'review_candidates': prior['review_candidates'] + sum(c['review_candidate'] for c in comparisons),
            'responses_this_batch': sum(r['responses'] for r in records), 'all_benchmark_deduplication_complete': False,
            'image_content_not_family_screened': True, 'zero_candidates_not_independent_families': True, 'model_called': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__);parser.add_argument('--output', type=Path);parser.add_argument('--request', type=Path);args = parser.parse_args()
    if args.request:
        _, _, layouts = span_views(json.loads(MANIFEST.read_text()));print(json.dumps(check(json.loads(args.request.read_text()), layouts)))
    elif args.output:
        if (REPO / 'build').resolve() not in args.output.resolve().parents:
            parser.error('Source-derived data must stay in ignored build/')
        result = audit();payload = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
        if args.output.exists() and args.output.read_text() != payload:
            raise ValueError('Refuse changed report overwrite')
        if not args.output.exists():
            args.output.write_text(payload)
        print(json.dumps({k: result[k] for k in ['material_count_total', 'parent_count_total', 'pair_count_total', 'new_pair_count', 'responses_this_batch', 'review_candidates']}))
    else:
        parser.error('Choose --request or --output')
