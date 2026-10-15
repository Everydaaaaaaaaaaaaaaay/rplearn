#!/usr/bin/env python3
"""Reconcile one related exam repost without merging provenance, inputs or keys."""
import argparse
import hashlib
import html
import json
import re
from pathlib import Path
from grade_mode_evidence import load_ref


def sha(value):
    return hashlib.sha256(value.encode()).hexdigest()


def extract_html_text(raw):
    if raw.count('<p class="assets-intro">') != 1:
        raise ValueError('One public resource block required')
    block = raw.split('<p class="assets-intro">', 1)[1].split('</p>', 1)[0]
    return html.unescape(re.sub('<[^>]+>', '\n', block))


def material(text, rule):
    start = text.find(rule['start'])
    if start < 0:
        raise ValueError('Missing selected material start')
    end = re.search(rule['end_regex'], text[start:])
    if not end:
        raise ValueError('Missing selected material end')
    return text[start:start + end.start()]


def tokens(value, gap_map):
    # Only explicitly mapped gap numbers change. Years, ages and other numbers stay.
    value = re.sub(r'[0-9]+', lambda m: ' SLOT' + gap_map[m[0]] + ' ' if m[0] in gap_map else m[0], value)
    return re.findall(r"[a-z]+(?:'[a-z]+)*|[0-9]+|[\u4e00-\u9fff]", value.lower().replace('’', "'"))


def audit(manifest):
    old = load_ref(manifest['existing_source_text']).read_text()
    old_html = load_ref(manifest['existing_html']).read_text()
    raw = load_ref(manifest['related_html']).read_text()
    new = load_ref(manifest['related_text']).read_text()
    old_title = html.unescape(re.search(r'<title>(.*?)</title>', old_html, re.S)[1])
    related_title = html.unescape(re.search(r'<title>(.*?)</title>', raw, re.S)[1])
    if '萧山区' not in old_title or '淳安县' not in related_title:
        raise ValueError('Observed repost region labels differ from the registered relation')
    if extract_html_text(raw) != new:
        raise ValueError('Related text differs from the saved public HTML')
    image = load_ref(manifest['related_preview'])
    if not image.read_bytes().startswith(b'\x89PNG\r\n\x1a\n'):
        raise ValueError('Expected public PNG preview')
    rows = []
    for row in manifest['material_relations']:
        a, b = material(old, row['existing_span']), material(new, row['related_span'])
        gap_map = row.get('old_gap_map', {})
        ta, tb = tokens(a, gap_map), tokens(b, {v: v for v in gap_map.values()})
        ga = {tuple(ta[i:i + 5]) for i in range(len(ta) - 4)}
        gb = {tuple(tb[i:i + 5]) for i in range(len(tb) - 4)}
        if not ga or not gb:
            raise ValueError('Insufficient selected material to compare')
        rows.append({'existing_group_id': row['existing_group_id'],
                     'related_numbering': row['related_numbering'],
                     'old_span_sha256': sha(a), 'related_span_sha256': sha(b),
                     'old_tokens': len(ta), 'related_tokens': len(tb),
                     'normalized_tokens_equal': ta == tb,
                     'fivegram_containment_smaller': len(ga & gb) / min(len(ga), len(gb)),
                     'fivegram_Jaccard': len(ga & gb) / len(ga | gb),
                     'author_review': row['author_review'],
                     'full_material_equivalence_or_independent_origin_proven': False})
    # These are separate observations in two versions, never an overwrite instruction.
    if not re.search(r'31\. B\s+32\. C\s+33\. F\s+34\. A', old):
        raise ValueError('Frozen source key conflict missing')
    if '31.【答案】【小题1】\nB\n【小题2】\nC\n【小题3】\nE\n【小题4】\nA' not in new:
        raise ValueError('Related mixed-task answer vector differs')
    bank = 'millions of match good together play'
    if bank not in re.sub(r'\s+', ' ', new) or bank in re.sub(r'\s+', ' ', old):
        raise ValueError('Variant bank presence/old missing distinction differs')
    if '第四部分 书面表达 (共1小题，满分20分)' not in old or '六、书面表达：本大题共1小题，共15分。' not in new:
        raise ValueError('Versioned writing score difference missing')
    if '满分15分' not in old[old.index('第一节 完形填空'):old.index('第一节 完形填空') + 80] or '共22.5分' not in new[:200]:
        raise ValueError('Cloze point change missing')
    bank_section = new[new.index('四、选词填空'):new.index('五、阅读填空')]
    if '共10分' not in bank_section:
        raise ValueError('Related bank section score missing')
    return {'relation_id': manifest['id'], 'materials': rows,
            'related_shared_bank_entries': ['millions of', 'match', 'good', 'together', 'play'],
            'bank_phrase_entry_not_two_entries': True,
            'key_vectors': {'existing_mixed31to34': ['B', 'C', 'F', 'A'], 'related31sub1to4': ['B', 'C', 'E', 'A']},
            'writing_points': {'existing': 20, 'related': 15},
            'cloze_points': {'existing': 15, 'related': 22.5},
            'wordbank_points': {'existing': 5, 'related': 10},
            'existing_positions_in_ten_related_groups': 61,
            'related_top_level_numbers': 35,
            'top_level_numbers_not_response_count': True,
            'related_public_text_once_rule_observed': '每词' in bank_section,
            'related_original_wordbank_once_rule': None,
            'related_variant_bank_input_complete_at_public_text_scope': True,
            'new_independent_parent_or_group_count': 0,
            'old_missing_inputs_key_and_score_preserved': True,
            'original_institution_authentication_or_gold': False}


def check_request(request, manifest):
    audit(manifest)
    if request.get('relation_id') != manifest['id'] or request.get('purpose') not in ['compare_related_version', 'review_variant_bank']:
        raise ValueError('Unknown relation or comparison purpose')
    if any(request.get(k) for k in ['count_as_independent_parent', 'count_as_new_source_groups',
            'authenticate_school_from_title', 'overwrite_original_key', 'mark_original_bank_complete',
            'inherit_variant_score', 'inherit_once_rule', 'claim_whole_paper_equal',
            'claim_independent_gold', 'claim_commercial_admission', 'claim_production_supported']):
        raise ValueError('Related material cannot transfer provenance, inputs, rules, keys or validation')
    return {'comparison_permitted': True, 'original_mutated': False, 'new_count': 0}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    result = audit(manifest)
    args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'materials'}, ensure_ascii=False))
