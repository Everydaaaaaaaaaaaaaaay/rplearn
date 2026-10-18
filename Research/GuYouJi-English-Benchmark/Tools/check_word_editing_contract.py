#!/usr/bin/env python3
"""Verify all current atomic-edit manuscripts and reject malformed contracts."""
import argparse
import copy
import json
from pathlib import Path
from check_all_levels_review import extract
from grade_mode_evidence import load_ref
from word_editing_contract import validate


def check(page):
    rows = []
    for group in extract(page)['groups'].values():
        if not group.get('wordEditing'):
            continue
        audit = json.loads(load_ref(group['author_check']).read_text())
        validate(group, audit)
        mutations = []
        m = copy.deepcopy(group); m['questions'].pop(); mutations.append(m)
        m = copy.deepcopy(group); m['questions'][0]['editAlternatives'][0]['position'] = 0; mutations.append(m)
        m = copy.deepcopy(group); m['questions'][0]['editAlternatives'][0]['text'] = 'two words'; mutations.append(m)
        m = copy.deepcopy(group); m['questions'][0]['acceptedAnswers'] = ['fake']; mutations.append(m)
        m = copy.deepcopy(group); m['wordEditing']['maxEditsPerSentence'] = 3; mutations.append(m)
        m = copy.deepcopy(group); m['questions'][1]['editAlternatives'].append(copy.deepcopy(m['questions'][0]['editAlternatives'][0])); mutations.append(m)
        for mutation in mutations:
            try:
                validate(mutation)
            except AssertionError:
                pass
            else:
                raise AssertionError('Malformed contract admitted: ' + group['id'])
        rows.append(dict(id=group['id'],candidate=group['candidate'],negative_contracts=len(mutations),
                         full_variants=audit['full_edit_variant_combinations'],
                         corrected_passage_variants=audit['corrected_passage_variants']))
    assert rows, 'No word-editing groups exercised'
    return dict(rows=rows, source_and_author_validation_separate=True, independent_validation=False)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--page', type=Path, default=Path('build/english-benchmark-quality-review/index.html'))
    p.add_argument('--report', type=Path)
    args = p.parse_args(); result = check(args.page)
    if args.report:
        output = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
        if args.report.exists():
            assert args.report.read_text() == output, 'Frozen report differs'
        else:
            args.report.write_text(output)
    print(json.dumps(dict(groups=len(result['rows']),negative_contracts=sum(r['negative_contracts'] for r in result['rows']))))
