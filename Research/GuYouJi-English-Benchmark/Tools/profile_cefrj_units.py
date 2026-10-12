#!/usr/bin/env python3
"""Inspect supplied lexical units against attributed CEFR-J 1.6 POS entries.

Input is a JSON list of {id, surface, lemma?, pos?, analysis_note?}.
No automatic tagging, stemming, case folding, sense inference or text grading.
Requires openpyxl; does not edit or export the source workbook.
"""
import argparse
import collections
import hashlib
import json
from pathlib import Path

import openpyxl


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--wordlist', type=Path, required=True)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    workbook_bytes = args.wordlist.read_bytes()
    expected = 'e41033a12f92983012a0a6b201d4f1f860b7ba3de700c2c3b89660ea21a390e1'
    if hashlib.sha256(workbook_bytes).hexdigest() != expected:
        raise ValueError('Wordlist is not the reviewed upstream 1.6 workbook; review before using another version')
    workbook = openpyxl.load_workbook(args.wordlist, read_only=True, data_only=False)
    index = collections.defaultdict(list)
    positions = set()
    for row in workbook['ALL_sep'].iter_rows(min_row=2, values_only=True):
        headword, pos, level = row[:3]
        index[headword].append({'headword': headword, 'pos': pos, 'level': level})
        positions.add(pos)
    workbook.close()
    units = json.loads(args.input.read_text())
    if not isinstance(units, list):
        raise ValueError('Input must be a lexical-unit list')
    identities = set()
    results = []
    for unit in units:
        identity, surface = unit.get('id'), unit.get('surface')
        if (not isinstance(identity, str) or not identity or identity in identities or
                not isinstance(surface, str) or not surface):
            raise ValueError('Each unit needs a unique id and nonempty surface')
        identities.add(identity)
        lemma, pos = unit.get('lemma'), unit.get('pos')
        if lemma is not None and (not isinstance(lemma, str) or not lemma or not unit.get('analysis_note')):
            raise ValueError('A supplied lemma needs nonempty provenance/analysis_note')
        if pos is not None and pos not in positions:
            raise ValueError(f'Unsupported source POS {pos}; do not silently map tag systems')
        lookup = lemma if lemma is not None else surface
        candidates = index.get(lookup, [])
        matched = [r for r in candidates if pos is None or r['pos'] == pos]
        status = ('unlisted_form' if not candidates else 'pos_mismatch' if not matched
                  else 'pos_unspecified' if pos is None else 'exact_pos_reference')
        results.append({'id': identity, 'surface': surface, 'lookup_form': lookup,
                        'supplied_lemma': lemma, 'supplied_pos': pos,
                        'analysis_note': unit.get('analysis_note'),
                        'match_status': status, 'candidate_entries': matched,
                        'candidate_levels': sorted({r['level'] for r in matched}),
                        'sense_resolution': 'not_established',
                        'chinese_grade_alignment': 'not_established'})
    level_counts = collections.Counter()
    for row in results:
        if row['match_status'] == 'exact_pos_reference' and len(row['candidate_levels']) == 1:
            level_counts[row['candidate_levels'][0]] += 1
    report = {
        'method_version': 1, 'wordlist_version': '1.6', 'case_policy': 'exact',
        'source_sha256': expected,
        'attribution': 'The CEFR-J Wordlist Version 1.6. Compiled by Yukio Tono, Tokyo University of Foreign Studies. Retrieved from https://www.cefr-j.org/download.html on 12/10/2026.',
        'units': results, 'lexical_unit_count': len(results),
        'status_counts': dict(collections.Counter(r['match_status'] for r in results)),
        'exact_pos_reference_level_counts': dict(sorted(level_counts.items())),
        'limitations': ['POS/lemma analyses are caller supplied, not independently verified',
                        'No word-sense or phrase-meaning inference',
                        'Unlisted forms are unknown, not C1/C2 or out-of-curriculum',
                        'No text-level CEFR, Chinese grade, task difficulty or pass/fail conclusion',
                        'Lexical units can be multiword; this is not a running-word coverage percentage']}
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'units': len(results), 'status_counts': report['status_counts']}))


if __name__ == '__main__':
    main()
