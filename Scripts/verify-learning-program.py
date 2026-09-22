#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Check the learning-program ledger; never execute commands from recorded evidence."""
import argparse
import json
import re
from pathlib import Path


def check(state, root, current_version):
    errors = []
    tasks = state.get('tasks', [])
    if state.get('workflow_version') != current_version:
        errors.append('Ledger does not adopt the published workflow version')
    ids = [t.get('id') for t in tasks]
    if not tasks or any(not isinstance(i, str) or not i for i in ids) or len(set(ids)) != len(ids):
        return errors + ['Tasks must have unique non-empty IDs'], []
    by_id = {t['id']: t for t in tasks}
    for task in tasks:
        name = task['id']
        if task.get('status') not in ('ready', 'in_progress', 'blocked', 'deferred', 'complete'):
            errors.append(name + ': invalid status')
        if task.get('status') == 'blocked' and not task.get('blocker'):
            errors.append(name + ': missing concrete blocker')
        if task.get('status') == 'deferred' and not task.get('deferral_reason'):
            errors.append(name + ': missing deferral reason')
        for dep in task.get('depends_on', []):
            if dep not in by_id:
                errors.append(name + ': unknown dependency ' + dep)
            elif task.get('status') == 'complete' and by_id[dep].get('status') != 'complete':
                errors.append(name + ': incomplete dependency ' + dep)
        checks = task.get('checks', [])
        if not checks:
            errors.append(name + ': acceptance checks missing')
        for item in checks:
            if item.get('status') not in ('pending', 'passed', 'failed', 'blocked'):
                errors.append(name + ': invalid check status')
            if task.get('status') == 'complete' and item.get('status') != 'passed':
                errors.append(name + ': cannot complete with unresolved check ' + item.get('name', ''))
            if item.get('status') == 'passed':
                references = item.get('evidence', [])
                if not references:
                    errors.append(name + ': passed check lacks evidence')
                for ref in references:
                    path = (root / ref.split('#')[0]).resolve()
                    if not path.is_relative_to(root.resolve()) or not path.is_file():
                        errors.append(name + ': missing or out-of-repository evidence ' + ref)
    visiting, visited = set(), set()
    def visit(name):
        if name in visiting:
            errors.append('Dependency cycle at ' + name)
            return
        if name in visited or name not in by_id:
            return
        visiting.add(name)
        for dep in by_id[name].get('depends_on', []):
            visit(dep)
        visiting.remove(name)
        visited.add(name)
    for name in ids:
        visit(name)
    ready = [t['id'] for t in tasks if t.get('status') in ('ready', 'in_progress')
             and all(by_id.get(d, {}).get('status') == 'complete' for d in t.get('depends_on', []))]
    return errors, ready


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--state', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    ledger = root / 'docs/learning-program'
    state = json.loads((args.state or ledger / 'execution-state.json').read_text())
    versions = (ledger / 'workflow-versions.md').read_text()
    version = re.search(r'唯一生效版本：\*\*(WF-[\d.]+)\*\*', versions)
    if not version:
        raise SystemExit('Missing unique published workflow version')
    errors, ready = check(state, root, version.group(1))
    workflow = (ledger / 'workflow.md').read_text()
    if '`' + version.group(1) + '`' not in workflow:
        errors.append('Workflow document and version ledger disagree')
    for error in errors:
        print('ERROR:', error)
    if errors:
        raise SystemExit(1)
    print('Ledger checks passed. Evidence content still requires human/agent review.')
    print('Next actionable tasks:', ', '.join(ready) or 'none; inspect blockers')


if __name__ == '__main__':
    main()
