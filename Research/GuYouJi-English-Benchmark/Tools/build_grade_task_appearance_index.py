#!/usr/bin/env python3
"""Index observed selected-source task families; missing cells remain unknown."""
import argparse
import hashlib
import json
from pathlib import Path
from grade_mode_evidence import BASE, CURRENT_BATCHES, evidence, load_ref

LEDGER = BASE / 'FirstRelease/Sampling/parent-paper-ledger-v0.4.json'


def build():
    rows = evidence();ledger = json.loads(LEDGER.read_text());load_ref(ledger['current_batches'])
    if ledger['current_batches']['path'] != str(CURRENT_BATCHES.relative_to(BASE)):
        raise ValueError('Appearance ledger and source batches differ')
    parents = {r['paper_identity']: r for r in ledger['parents']}
    if set(parents) != {r['paper_id'] for r in rows}:
        raise ValueError('Source parent ledger coverage differs')
    if any(sum(r['paper_id'] == identity for r in rows) != parent['structural_records'] for identity, parent in parents.items()):
        raise ValueError('Per-parent source count differs')
    families = sorted({r['shape']['family'] for r in rows});cells = []
    for family in families:
        for grade in range(7, 13):
            members = [r for r in rows if r['shape']['grade'] == grade and r['shape']['family'] == family]
            cells.append({'grade': grade, 'family': family, 'observation_state': 'observed' if members else 'unknown_no_selected_positive_evidence',
                          'source_group_ids': sorted(r['id'] for r in members), 'source_group_records': len(members),
                          'parent_paper_identities': sorted({r['paper_id'] for r in members}),
                          'source_layers': {layer: sum(r['layer'] == layer for r in members) for layer in ['baseline_selected117', 'new_structure_only']},
                          'input_states': {state: sum(r['necessary_input_complete'] is value for r in members) for state, value in [('confirmed', True), ('known_missing', False), ('unknown', None)]},
                          'whole_paper_absence_established': False, 'exclusive_grade_claim_established': False,
                          'same_family_not_same_complete_mode': True, 'source_input_or_answer_review_not_upgraded': True})
    if sum(c['source_group_records'] for c in cells) != len(rows):
        raise ValueError('Appearance cells omit or duplicate source groups')
    return {'version': '0.1', 'scope': 'grades7_to12_selected_written_source_structure_families_not_all_exams_or_model_capabilities',
            'family_classification_scope': 'top_level_source_task_group; embedded_operations_remain_in_parent_mixed_group',
            'current_batches': {'path': str(CURRENT_BATCHES.relative_to(BASE)), 'sha256': hashlib.sha256(CURRENT_BATCHES.read_bytes()).hexdigest()},
            'parent_ledger': {'path': str(LEDGER.relative_to(BASE)), 'sha256': hashlib.sha256(LEDGER.read_bytes()).hexdigest()},
            'source_record_count': len(rows), 'source_parent_count': len(parents), 'family_count': len(families),
            'observed_grade_family_cells': sum(c['observation_state'] == 'observed' for c in cells),
            'unknown_cells': sum(c['observation_state'] != 'observed' for c in cells), 'cells': cells,
            'no_selected_positive_evidence_is_not_whole_paper_absence': True, 'mode_replication_requires_complete_bound_parameters': True,
            'model_called': False, 'production_supported': False, 'population_grade_difficulty_validated': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__);parser.add_argument('--output', type=Path, required=True);args = parser.parse_args()
    result = build();payload = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if args.output.exists() and args.output.read_text() != payload:
        raise ValueError('Refuse changed frozen appearance index overwrite')
    if not args.output.exists():
        args.output.write_text(payload)
    print(json.dumps({k: result[k] for k in ['source_record_count', 'source_parent_count', 'family_count', 'observed_grade_family_cells', 'unknown_cells']}))
