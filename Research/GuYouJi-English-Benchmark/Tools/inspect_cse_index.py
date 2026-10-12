#!/usr/bin/env python3
"""Count one pinned public CSE portal index without exporting descriptors.

Portal IDs are namespace-scoped; reverse-ordered option IDs are not levels.
No Chinese-grade, CEFR, IELTS or licensing equivalence is inferred.
"""
import argparse
import collections
import hashlib
import json
from pathlib import Path

EXPECTED_SHA = '290d507765a9ae2767eaf6a871f896139ededea56843fe622d293c0b17f1bc95'
RANKS = {f'{label}级': rank for rank, label in enumerate('一二三四五六七八九', 1)}


def inspect(path):
    payload = path.read_bytes()
    if hashlib.sha256(payload).hexdigest() != EXPECTED_SHA:
        raise ValueError('Unknown CSE index identity; review version/layout first')
    response = json.loads(payload)
    if response['code'] != 0:
        raise ValueError('Unsuccessful portal response')
    root = response['data']
    nodes = []

    def visit(node):
        nodes.append(node)
        for child in node.get('children', []):
            visit(child)
    visit(root)
    node_ids = [n['id'] for n in nodes]
    if len(node_ids) != len(set(node_ids)):
        raise ValueError('Duplicate node IDs')
    options = root['item']
    if {r['title'] for r in options} != set(RANKS) or len(options) != 9:
        raise ValueError('Nine distinct level labels not found')
    records = [r for node in nodes[1:] for r in node.get('item', [])]
    descriptor_ids = [r['id'] for r in records]
    if len(descriptor_ids) != len(set(descriptor_ids)):
        raise ValueError('Duplicate descriptor IDs; do not silently merge')
    if any(r['title'] not in RANKS or not r['content'].strip() for r in records):
        raise ValueError('Unknown label or blank descriptor')
    counts = collections.Counter(r['title'] for r in records)
    return {'input_sha256': EXPECTED_SHA, 'status': 'portal_metadata_only',
            'tree_nodes_including_option_root': len(nodes),
            'capability_parent_nodes': len(root['children']),
            'leaf_nodes': sum(not n.get('children') for n in nodes),
            'root_level_option_records': len(options),
            'descriptor_records_excluding_option_root': len(records),
            'distinct_descriptor_ids': len(set(descriptor_ids)),
            'records_by_label': {label: counts[label] for label in RANKS},
            'level_options': [{'raw_option_id': r['id'], 'label': r['title'],
                               'rank_from_label': RANKS[r['title']]} for r in options],
            'parents': [{'node_id': n['id'], 'title': n['title'],
                         'child_nodes': len(n['children'])} for n in root['children']],
            'limitations': ['Root contains search options and remarks, not interchangeable descriptor rows',
                'Portal node count is not independent full-book/table content review',
                'Node, option and descriptor IDs use different namespaces',
                'Numeric option1 means label9 in this payload; ID is not proficiency rank',
                'No school-semester/CEFR/exam-score mapping or commercial clearance established']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--index', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = inspect(args.index)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: result[k] for k in ('tree_nodes_including_option_root',
        'descriptor_records_excluding_option_root', 'distinct_descriptor_ids', 'records_by_label')}, ensure_ascii=False))


if __name__ == '__main__':
    main()
