#!/usr/bin/env python3
"""Report observed grade/shape evidence and check one preparation request.

An observed shape is not exclusive to a grade, a nationally typical range,
independent answer gold, commercial permission, or production model support.
Exact reference binding avoids creating unseen combinations from marginal ranges.
"""
import argparse
import hashlib
import json
import re
from collections import defaultdict
from pathlib import Path

BASE = Path(__file__).resolve().parents[1]
REPO = BASE.parents[1]
BATCH = BASE / 'FirstRelease/Sampling/grade-mode-batch20261015-v0.1.json'


def load_ref(ref):
    relative = Path(ref['path'])
    if relative.is_absolute() or '..' in relative.parts:
        raise ValueError('Nonportable reference')
    path = REPO / relative if relative.parts[0] == 'build' else BASE / relative
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != ref['sha256']:
        raise ValueError('Missing or changed reference: ' + str(relative))
    return path


def evidence():
    batch = json.loads(BATCH.read_text())
    overview = json.loads(load_ref(batch['baseline_source_overview']).read_text())
    inventory = json.loads(load_ref(batch['baseline_mode_inventory']).read_text())
    parents = {x['id']: x['parent_paper_id'] for x in overview['groups']}
    rows = []
    for mode in inventory['shapes']:
        for gid in mode['source_group_ids']:
            rows.append({'id': gid, 'paper_id': parents[gid], 'shape': mode['shape'],
                         'layer': 'baseline_selected117', 'necessary_input_complete': None,
                         'positive_answer_anchor_admitted': False, 'production_supported': False})
    new_positions = 0
    for paper in batch['papers']:
        load_ref(paper['raw'])
        text = load_ref(paper['resource_text']).read_text()
        for observation in paper['rows']:
            marker = re.search(r'\s+'.join(re.escape(x) for x in observation['locator'].split()), text)
            if not marker or text[:marker.start()].count('\n') + 1 != observation['locator_line_1based']:
                raise ValueError('Section locator changed: ' + observation['id'])
            shape = observation['shape']
            if shape['grade'] != paper['grade'] or type(shape['responses']) is not int or shape['responses'] < 1:
                raise ValueError('Invalid grade/response count')
            if observation['positive_answer_anchor_admitted'] or observation['production_supported']:
                raise ValueError('New structure observations cannot self-admit answers or production')
            if 'components' in shape['details']:
                if sum(x['responses'] for x in shape['details']['components']) != shape['responses']:
                    raise ValueError('Mixed response count mismatch')
            rows.append({'id': observation['id'], 'paper_id': paper['id'], 'shape': shape,
                         'layer': 'new_structure_only',
                         'necessary_input_complete': shape['details'].get('necessary_input_complete', True),
                         'positive_answer_anchor_admitted': False, 'production_supported': False})
            new_positions += shape['responses']
    if len({x['id'] for x in rows}) != len(rows):
        raise ValueError('Repeated group identity; do not double-count')
    if len(batch['papers']) != batch['paper_count'] or new_positions != batch['observed_written_response_positions']:
        raise ValueError('Batch count mismatch')
    if len(rows) - len(overview['groups']) != batch['structural_record_count']:
        raise ValueError('Structure record mismatch')
    return rows


def report(rows):
    grouped = defaultdict(list)
    for row in rows:
        s = row['shape']
        grouped[(s['grade'], s['family'])].append(row)
    result = []
    for (grade, family), members in sorted(grouped.items()):
        signatures = {json.dumps(x['shape'], ensure_ascii=False, sort_keys=True) for x in members}
        result.append({'grade': grade, 'family': family,
                       'observed_response_counts': sorted({x['shape']['responses'] for x in members}),
                       'observed_options_each': sorted({x['shape']['options_each'] for x in members if x['shape']['options_each'] is not None}),
                       'group_records': len(members), 'parent_paper_identities': len({x['paper_id'] for x in members}),
                       'exact_shapes': [json.loads(s) for s in sorted(signatures)],
                       'supporting_group_ids': [x['id'] for x in members],
                       'typical_population_range': None, 'exclusive_to_these_grades': False})
    return {'scope': 'grades7_to12', 'record_count': len(rows),
            'parent_paper_identities': len({x['paper_id'] for x in rows}),
            'layers_have_different_review_status': True, 'families': result,
            'marginal_counts_not_cartesian_generation_choices': True,
            'paper_counts_not_independent_passage_families': True, 'model_called': False,
            'production_supported': False}


def check_request(request, rows):
    matches = [x for x in rows if x['id'] == request.get('evidence_group_id')]
    if len(matches) != 1:
        raise ValueError('Unknown evidence group; no unobserved default')
    row = matches[0]
    if request.get('grade') != row['shape']['grade']:
        raise ValueError('Reference belongs to a different grade')
    if request.get('shape') != row['shape']:
        raise ValueError('Shape differs from actual evidence, including response/option/material/rule details')
    if request.get('requires_complete_student_input', True) and row['necessary_input_complete'] is False:
        raise ValueError('Necessary student input missing in this evidence')
    if request.get('use_as_verified_answer_gold', False):
        raise ValueError('Independent answer admission is not established by this structural inventory')
    if request.get('claim_production_supported', False):
        raise ValueError('Preparation guard is not wired production or model verification')
    return {'preparation_shape_matches_evidence': True, 'grade': request['grade'],
            'evidence_group_id': row['id'], 'content_correctness_checked': False,
            'independent_answer_gold': False, 'model_called': False, 'production_supported': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', type=Path)
    parser.add_argument('--request', type=Path)
    args = parser.parse_args()
    rows = evidence()
    if args.report:
        args.report.write_text(json.dumps(report(rows), ensure_ascii=False, indent=2) + '\n')
    if args.request:
        print(json.dumps(check_request(json.loads(args.request.read_text()), rows), ensure_ascii=False))
    else:
        print(json.dumps({'records': len(rows), 'parent_paper_identities': len({x['paper_id'] for x in rows}),
                          'baseline_records': sum(x['layer'] == 'baseline_selected117' for x in rows),
                          'new_structure_records': sum(x['layer'] == 'new_structure_only' for x in rows),
                          'grade_family_cells': len(report(rows)['families']), 'model_called': False}))
