#!/usr/bin/env python3
"""Screen actual isolated prompts including Chinese; group bundles are not passages."""
import argparse
import json
import re
from itertools import combinations
from pathlib import Path
from check_sentence_layout import MANIFEST, layouts
from grade_mode_evidence import load_ref
from audit_school_material_families import digest, remove_offsets
from profile_task_load import count


def audit():
    checked = layouts()
    manifest = json.loads(MANIFEST.read_text())
    records, normalized = [], {}
    for case in manifest['views']:
        view = load_ref(case['source_text']).read_text()
        for item in case['items']:
            segment = case['material_segments'][item['prompt_segment']]
            prompt_component = next(c for c in case['components'] if c['role'] == 'prompt_with_hints' and c['item_id'] == item['ordinal'])
            raw = view[segment['start_offset']:segment['end_offset']]
            text = remove_offsets(raw, prompt_component['excluded_offsets'], ' ')
            tokens = re.findall(r"[A-Za-z]+(?:['’][A-Za-z]+)*|\d+(?:\.\d+)?|[\u4e00-\u9fff]", text.casefold())
            identity = case['group_id'] + '.item' + str(item['ordinal'])
            normalized[identity] = tokens
            options = [case['components'][i] for i in item['option_components']]
            option_counts = {'english_digit_tokens': 0, 'han_characters': 0}
            for c in options:
                content = remove_offsets(view[c['start_offset']:c['end_offset']], c['excluded_offsets'])
                for k, v in count(content).items():
                    option_counts[k] += v
            records.append({'id': identity, 'group_id': case['group_id'],
                            'ordinal': item['ordinal'], 'source_text': case['source_text'],
                            'prompt_sha256': digest(raw), 'bilingual_normalized_prompt_sha256': digest(' '.join(tokens)),
                            'prompt_with_hints_counts': count(text), 'option_counts': option_counts,
                            'response_units': 1, 'visible_blank_count': len(item['visible_blanks']),
                            'necessary_input_complete': checked[case['group_id']]['necessary_input_complete']})
    candidates, comparisons, short_pairs = [], 0, 0
    for left, right in combinations(normalized, 2):
        a, b = normalized[left], normalized[right]
        sa = {tuple(a[i:i + 5]) for i in range(len(a) - 4)}
        sb = {tuple(b[i:i + 5]) for i in range(len(b) - 4)}
        comparisons += 1
        if not sa or not sb:
            short_pairs += 1
        exact = bool(a) and a == b
        jaccard = len(sa & sb) / len(sa | sb) if sa | sb else 0
        containment = len(sa & sb) / min(len(sa), len(sb)) if sa and sb else 0
        if exact or jaccard >= .5 or containment >= .8:
            candidates.append({'left': left, 'right': right, 'exact_bilingual_prompt': exact,
                               'fivegram_jaccard': jaccard, 'fivegram_containment': containment})
    return {'version': '0.1', 'scope': '15 isolated sentence sets/163 response units; prompts with hints compared across and within sets',
            'records': records, 'pairs_checked': comparisons, 'pairs_with_under5token_prompt': short_pairs,
            'candidates': candidates, 'normalization_preserves_Chinese': True,
            'private_keys_or_repost_explanations_in_student_profile': False,
            'prompt_counts_include_hints_not_separate_additive_load': True,
            'all_benchmark_deduplication_complete': False,
            'screen_threshold_not_validated_family_classifier': True,
            'zero_candidates_not_independent_families_or_generation_capacity': True,
            'independent_gold': False, 'model_called': False, 'student_minutes': None}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = audit()
    from grade_mode_evidence import REPO
    if (REPO / 'build').resolve() not in args.output.resolve().parents:
        parser.error('Source-derived profiles must stay in ignored build/')
    payload = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if args.output.exists() and args.output.read_text() != payload:
        raise ValueError('Refuse to overwrite a different sentence audit')
    if not args.output.exists():
        args.output.write_text(payload)
    print(json.dumps({'items': len(result['records']), 'pairs': result['pairs_checked'],
                      'candidates': len(result['candidates']), 'short_pairs': result['pairs_with_under5token_prompt']}))
