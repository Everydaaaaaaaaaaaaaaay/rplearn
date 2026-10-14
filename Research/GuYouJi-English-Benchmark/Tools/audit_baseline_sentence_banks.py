#!/usr/bin/env python3
"""Bind independent sentence prompts/cues, per-item choices and letter-response banks."""
import argparse
import hashlib
import json
import re
from itertools import combinations
from pathlib import Path
from grade_mode_evidence import BASE, REPO, evidence, load_ref
from audit_school_material_families import digest, normalize_view
from audit_cloze_materials import normalized
from audit_baseline_bank_forms import compare
from audit_baseline_open_forms import open_form_views, prior_views
from profile_task_load import count

MANIFEST = BASE / 'FirstRelease/Sampling/baseline-sentence-bank-views-v0.1.json'


def sentence_views(manifest):
    sources = {r['id']: r for r in evidence()}
    acquisitions = {r['id']: r for r in json.loads((BASE / 'Registry/acquisitions.json').read_text())['acquisitions']}
    grammar_cases = [v for v in manifest['views'] if sources[v['group_id']]['shape']['family'] == 'passage_form']
    records, bodies, layouts = open_form_views({'views': grammar_cases})
    atoms = {}
    for case in manifest['views']:
        row = sources[case['group_id']];family = row['shape']['family']
        if family == 'passage_form':
            continue
        a = acquisitions[case['source_parent_id']]
        if row['layer'] != 'baseline_selected117' or row['paper_id'] != case['source_parent_id'] or case['parent_document'] != {'path': a['path'], 'sha256': a['sha256']}:
            raise ValueError('Sentence/bank source layer/parent/version differs')
        load_ref(case['parent_document'])
        obs = next(r for r in json.loads(load_ref(case['source_catalogue']).read_text())['groups'] if r['id'] == row['id'])
        catalogue_parent = obs.get('source_paper_acquisition_id', obs.get('acquisition_id'))
        if catalogue_parent != row['paper_id'] or obs['grade'] != row['shape']['grade'] or obs['material_and_question_PDF_pages'] != case['PDF_pages']:
            raise ValueError('Sentence/bank source catalogue/page scope differs')
        record = json.loads(load_ref(case['transcription']).read_text())['records'][case['record_index']]
        if record['id'] != row['id'] or record['family'] != family or record['grade'] != row['shape']['grade'] or record['printed_numbers'] != obs['question_numbers'] or len(record['printed_numbers']) != row['shape']['responses']:
            raise ValueError('Source sentence mode/response allocation differs')
        if record['source_images'] != case['source_images'] or record['PDF_pages'] != case['PDF_pages'] or len(case['source_images']) != len(case['PDF_pages']):
            raise ValueError('Required original page omitted/reordered')
        for image in case['source_images']:
            if sum(r.get('path') == image['path'] and r.get('sha256') == image['sha256'] for r in acquisitions.values()) != 1:
                raise ValueError('Required original image not registered')
            load_ref(image)
        cs = record['components'];by_id = {c['id']: c for c in cs};counts = {};parts = []
        if len(by_id) != len(cs) or {c['id']: digest(c['text']) for c in cs} != case['component_hashes']:
            raise ValueError('Source prompt/cue/choice changed or omitted')
        for c in cs:
            if c['role'] not in ['instruction', 'scoring_declaration', 'prompt', 'option', 'phonetic_hint', 'English_hint', 'passage', 'shared_option'] or any(x in c['text'] for x in ['【答案】', '【解析】']):
                raise ValueError('Private key/rationale is not source student input')
            text = c['text']
            if c['role'] in ['prompt', 'passage']:
                parts.append(text)
                if c['role'] == 'prompt':
                    atoms[row['id'] + '.' + c['id']] = normalize_view(text, 'bilingual_token_view')
                text = re.sub(r'_+\d+_+', ' ', text)
            role = counts.setdefault(c['role'], {'english_digit_tokens': 0, 'han_characters': 0, 'components': 0})
            for k, v in count(text).items():
                role[k] += v
            role['components'] += 1
        if counts.get('instruction', {}).get('components') != 1 or counts.get('scoring_declaration', {}).get('components') != 1:
            raise ValueError('Source instruction/score omitted')
        if family == 'shared_bank':
            bank = [c for c in cs if c['role'] == 'shared_option'];body = by_id['body']['text']
            if len(bank) != row['shape']['details']['entries'] or [c['label'] for c in bank] != list('ABCD') or [c['text'] for c in bank] != ['eggs', 'come', 'big', 'sit']:
                raise ValueError('Shared bank candidates differ')
            if [int(n) for n in re.findall(r'_+(\d+)_+', body)] != record['printed_numbers']:
                raise ValueError('Shared bank gaps missing/reordered')
            if (record['response_policy'] != 'letter_from_shared_bank' or record['reuse_rule_explicit'] is not None or record['form_change_explicit'] or record['strict_no_form_change_quote_established'] or
                    '所对应的A、B、C、D' not in by_id['instruction']['text'] or record['this_subgroup_responses'] != 4 or record['parent_cloze_responses'] != 10):
                raise ValueError('Source bank letter/part/reuse/form policy differs')
            body = re.sub(r'_+\d+_+', ' ', body)
            extra = {'response_policy': 'letter_from_shared_bank', 'reuse_rule_explicit': None, 'form_change_explicit': False,
                     'strict_no_form_change_quote_established': False, 'shared_options': bank,
                     'parent_cloze_responses': 10, 'this_subgroup_responses': 4}
        else:
            units = record['units'];used = []
            if [u['printed_number'] for u in units] != record['printed_numbers'] or any(u['response_fields'] != 1 for u in units):
                raise ValueError('Independent response units differ')
            for u in units:
                c = by_id[u['prompt_component']];used.append(c['id'])
                if c['role'] != 'prompt' or c['item_id'] != u['printed_number']:
                    raise ValueError('Prompt assigned to another response')
                if family == 'sentence_choice':
                    if [o['label'] for o in u['options']] != list('ABCD'[:row['shape']['options_each']]):
                        raise ValueError('Per-response three/four choices differ')
                    for option in u['options']:
                        o = by_id[option['component_id']];used.append(o['id'])
                        if o['role'] != 'option' or o['item_id'] != u['printed_number'] or o['label'] != option['label']:
                            raise ValueError('Choice belongs to another question')
                else:
                    cue = by_id[u['hint_component']];used.append(cue['id'])
                    expected = 'phonetic_hint' if family == 'phonetic_word_completion' else 'English_hint'
                    if cue['role'] != expected or cue['item_id'] != u['printed_number'] or u['word_limit_explicit'] is not None or u['whole_sentence_output'] != (family == 'sentence_translation'):
                        raise ValueError('Phonetic/translation cue and output policy differ')
                    if family == 'sentence_translation' and not re.search(r'[\u4e00-\u9fff]', c['text']):
                        raise ValueError('Chinese whole-sentence input missing')
            if set(used) != {c['id'] for c in cs if c['role'] in ['prompt', 'option', 'phonetic_hint', 'English_hint']} or len(used) != len(set(used)):
                raise ValueError('Student response components omitted/reused')
            if family == 'phonetic_word_completion' and [by_id[u['hint_component']]['text'] for u in units] != ['[rest]', '[dɪʃ]', '[fi:d]', '[smel]']:
                raise ValueError('Original phonetic glyphs replaced without separate normalization')
            body = '\n'.join(parts)
            extra = {'units': units, 'independent_contexts_not_connected_passage': family == 'sentence_choice',
                     'variant_scoring_or_analytic_rubric_not_established': True}
        policy = 'bilingual_token_view' if family == 'sentence_translation' else None
        norm = normalize_view(body, policy);gid = row['id']
        if not norm:
            raise ValueError('Source prompts cannot collapse to an empty comparison view')
        if gid in bodies:
            raise ValueError('Repeated source sentence group')
        bodies[gid] = norm
        records.append({'group_id': gid, 'paper_identity': row['paper_id'], 'grade': row['shape']['grade'], 'family': family,
                        'normalized_material_sha256': digest(norm), 'component_counts': counts, 'responses': len(record['printed_numbers']),
                        'options_each': row['shape']['options_each'], 'source_point_each': record['source_point_each'],
                        'normalization_policy': policy,
                        'source_cue_bytes_preserved': True, 'frozen_source_input_state': row['necessary_input_complete'],
                        'transcription_independent': False, 'source_key_not_independent_gold': True})
        layouts[gid] = {'source_shape': row['shape'], 'parent_document': case['parent_document'], 'transcription': case['transcription'],
                        'required_source_images': case['source_images'], 'component_hashes': case['component_hashes'],
                        'printed_numbers': record['printed_numbers'], 'source_point_each': record['source_point_each'], **extra,
                        'frozen_source_input_state': row['necessary_input_complete']}
    return records, bodies, atoms, layouts


def old_views(manifest):
    previous = json.loads(load_ref(manifest['prior_view_manifest']).read_text());old, records, _ = prior_views(previous)
    new_records, new, _ = open_form_views(previous)
    if set(old) & set(new):
        raise ValueError('Repeated prior open/form source')
    old.update(new);records += new_records;prior = json.loads(load_ref(manifest['prior_material_audit']).read_text())
    if len(old) != prior['material_count_total'] or any(digest(old[r['group_id']]) != r['normalized_material_sha256'] for r in prior['records']):
        raise ValueError('Previous source views changed')
    return old, records, prior


def check(request, layouts):
    gid = request.get('evidence_group_id')
    if gid not in layouts or request.get('layout') != layouts[gid]:
        raise ValueError('Sentence/choice/translation/cue/bank/optional source binding differs')
    if any(request.get(k) for k in ['claim_semantic_or_rubric_gold', 'claim_production_supported', 'claim_factual_review_complete', 'claim_all_sentence_semantics_deduplicated']):
        raise ValueError('Source layout is not semantic/rubric gold, production, facts or full deduplication')
    return {'source_sentence_bank_layout_matches': True, 'evidence_group_id': gid, 'frozen_source_input_state': layouts[gid]['frozen_source_input_state'],
            'model_called': False, 'independent_gold': False, 'production_supported': False}


def audit():
    manifest = json.loads(MANIFEST.read_text());records, new, atoms, _ = sentence_views(manifest);old, old_records, prior = old_views(manifest)
    if set(old) & set(new):
        raise ValueError('Source group already screened')
    comparisons = [{'left': left, 'right': right, **compare(a, b)} for left, a in new.items() for right, b in old.items()]
    comparisons += [{'left': left, 'right': right, **compare(new[left], new[right])} for left, right in combinations(new, 2)]
    total = len(old) + len(new);pairs = total * (total - 1) // 2
    if pairs != prior['pair_count_total'] + len(comparisons):
        raise ValueError('Source group comparison coverage differs')
    atomic_candidates = [];atomic_pairs = 0
    for left, a in atoms.items():
        for right, b in old.items():
            result = compare(a, b);atomic_pairs += 1
            if result['review_candidate']:
                atomic_candidates.append({'left': left, 'right': right, **result})
    for left, right in combinations(atoms, 2):
        result = compare(atoms[left], atoms[right]);atomic_pairs += 1
        if result['review_candidate']:
            atomic_candidates.append({'left': left, 'right': right, **result})
    failed = REPO / 'build/english-benchmark-research-20261012/baseline-sentence-bank-audit20261015t-v0.1.json'
    return {'version': '0.2', 'records_scope': 'nine new baseline views; previous238 via frozen references',
            'failed_first_pass': {'path': str(failed.relative_to(REPO)), 'sha256': hashlib.sha256(failed.read_bytes()).hexdigest()},
            'failed_empty_Han_prompt_candidates_not_valid_repeats': True,
            'individual_prompt_normalization': 'bilingual_token_view',
            'prior_records_and_comparisons': manifest['prior_material_audit'], 'records': records, 'comparisons': comparisons,
            'material_count_total': total, 'parent_count_total': len({r['paper_identity'] for r in old_records + records}),
            'pair_count_total': pairs, 'prior_pairs_reused': prior['pair_count_total'], 'new_pair_count': len(comparisons),
            'exact_repeat_pairs': prior['exact_repeat_pairs'] + sum(c['exact_normalized_match'] for c in comparisons),
            'review_candidates': prior['review_candidates'] + sum(c['review_candidate'] for c in comparisons),
            'individual_sentence_prompts': len(atoms), 'atomic_pairs_checked_separate_not_added_to_group_pairs': atomic_pairs, 'atomic_candidates': atomic_candidates,
            'response_positions_this_batch': 63, 'all_benchmark_deduplication_complete': False,
            'sentence_prompt_fragments_not_full_cue_or_semantic_family_screen': True, 'model_called': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__);parser.add_argument('--output', type=Path);parser.add_argument('--request', type=Path);args = parser.parse_args()
    if args.request:
        _, _, _, layouts = sentence_views(json.loads(MANIFEST.read_text()));print(json.dumps(check(json.loads(args.request.read_text()), layouts)))
    elif args.output:
        if (REPO / 'build').resolve() not in args.output.resolve().parents:
            parser.error('Source-derived data must stay in ignored build/')
        result = audit();payload = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
        if args.output.exists() and args.output.read_text() != payload:
            raise ValueError('Refuse changed report overwrite')
        if not args.output.exists():
            args.output.write_text(payload)
        print(json.dumps({k: result[k] for k in ['material_count_total', 'parent_count_total', 'pair_count_total', 'new_pair_count', 'review_candidates', 'individual_sentence_prompts', 'atomic_pairs_checked_separate_not_added_to_group_pairs']}))
    else:
        parser.error('Choose --request or --output')
