#!/usr/bin/env python3
"""Check reviewed source anchors and failure behavior of Oxford inspection."""
import argparse
import copy
import json
import tempfile
from pathlib import Path

from inspect_oxford_pdfs import ENTRY, inspect, repair_page


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-dir', type=Path, required=True)
    parser.add_argument('--repairs', type=Path, required=True)
    args = parser.parse_args()
    fixes = json.loads(args.repairs.read_text())
    results = {label: inspect(args.source_dir / filename, label, fixes[label])
               for label, filename in [('3000', 'oxford3000-pdf.pdf'),
                                       ('5000_additional', 'oxford5000-pdf.pdf')]}
    assert not any(r['unresolved'] for r in results.values())
    # Selected source-image anchors, not every entry and not educational gold.
    anchors = [('3000', 'bank (money)', 'n.', 'A1', 1),
               ('3000', 'bank (river)', 'n.', 'B1', 7),
               ('3000', 'account', 'n.', 'B1', 7),
               ('3000', 'account', 'v.', 'B2', 10),
               ('3000', 'adult', 'n.', 'A1', 1),
               ('3000', 'adult', 'adj.', 'A2', 4),
               ('3000', 'can1', 'modal v.', 'A1', 1),
               ('3000', 'can2', 'n.', 'A2', 4),
               ('3000', 'wind1', 'n.', 'A2', 7),
               ('3000', 'wind2', 'v.', 'B2', 12),
               ('3000', 'per cent', 'noun.', 'A2', 6),
               ('3000', 'audio', 'adj.', 'A2', 4),
               ('5000_additional', 'audio', 'adj.', 'B2', 1),
               ('3000', 'well-being', 'n.', 'B2', 12),
               ('5000_additional', 'well-being', 'n.', 'C1', 8),
               ('5000_additional', 'diplomatic', 'n.', 'C1', 5)]
    for label, head, pos, level, page in anchors:
        found = [r for r in results[label]['entries'] if r['display_headword'] == head
                 and pos in r['pos_tags'] and r['level'] == level and r['pdf_page'] == page]
        assert len(found) == 1, (label, head, pos, level, page)
    assert all(r['summary']['all_entries_visually_verified'] is False for r in results.values())
    assert all(r['summary']['commercial_use_cleared'] is False for r in results.values())
    unrepaired = inspect(args.source_dir / 'oxford3000-pdf.pdf', '3000', [])
    assert unrepaired['summary']['candidate_index_status'] == 'blocked_unresolved_lines'
    assert ENTRY.fullmatch('per cent noun., adj./adv.').group(1) == 'per cent'
    rejected = 0
    def reject(fn):
        nonlocal rejected
        try:
            fn()
        except ValueError:
            rejected += 1
        else:
            raise AssertionError('Invalid case accepted')
    lines = [{'normalised': s, 'raw_lines': [s], 'native_line_numbers': [i + 1]}
             for i, s in enumerate(fixes['3000'][0]['source_lines'])]
    no_evidence = copy.deepcopy(fixes['3000'][0]);no_evidence['visual_evidence'] = ''
    reject(lambda: repair_page(lines, [no_evidence], 2))
    missing_file = copy.deepcopy(fixes['3000'][0]);missing_file['visual_evidence'] += '.missing'
    reject(lambda: repair_page(lines, [missing_file], 2))
    reject(lambda: repair_page(lines * 2, [fixes['3000'][0]], 2))
    absent = copy.deepcopy(fixes['3000'][0]);absent['source_lines'][0] += ' corrupt'
    reject(lambda: repair_page(lines, [absent], 2))
    with tempfile.TemporaryDirectory() as temp:
        path = Path(temp) / 'foreign.pdf';path.write_bytes(b'%PDF-unreviewed')
        reject(lambda: inspect(path, '3000', []))
    print(json.dumps({'selected_source_anchors': len(anchors), 'negative_cases_rejected': rejected,
                      'missing_repairs_block_index': True, 'no_gold_or_permission_inferred': True}))


if __name__ == '__main__':
    main()
