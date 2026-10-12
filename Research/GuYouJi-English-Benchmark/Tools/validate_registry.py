#!/usr/bin/env python3
"""Validate research bookkeeping; never infer educational or legal validity."""
import argparse
import hashlib
import json
from pathlib import Path


BASE = Path(__file__).resolve().parents[1]
REPO = BASE.parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check-cache', action='store_true')
    parser.add_argument('--require-complete', action='store_true')
    args = parser.parse_args()
    errors = []
    documents = {}
    for path in sorted(BASE.rglob('*.json')):
        try:
            documents[str(path.relative_to(BASE))] = json.loads(path.read_text())
        except (ValueError, OSError) as exc:
            errors.append(f'{path}: {exc}')

    def rows(file, key):
        value = documents.get('Registry/' + file, {}).get(key)
        if not isinstance(value, list):
            errors.append(f'{file}: missing list {key}')
            return []
        return value

    def index(records, name):
        result = {}
        for row in records:
            identity = row.get('id')
            if not identity or identity in result:
                errors.append(f'{name}: missing/duplicate id {identity}')
            result[identity] = row
        return result

    acquisitions = index(rows('acquisitions.json', 'acquisitions'), 'acquisitions')
    sources = index(rows('sources.json', 'sources'), 'sources')
    gaps = index(rows('gaps.json', 'gaps'), 'gaps')
    milestones = index(rows('milestones.json', 'milestones'), 'milestones')
    rights_fields = {'commercial_publication', 'commercial_model_training',
                    'bulk_database_reuse', 'adaptation',
                    'third_party_model_transmission', 'redistribution'}
    for identity, source in sources.items():
        for aid in source.get('acquisition_ids', []):
            if aid not in acquisitions:
                errors.append(f'{identity}: unknown acquisition {aid}')
        if not rights_fields <= source.get('rights', {}).keys():
            errors.append(f'{identity}: missing usage rights fields')

    def check_references(value, location):
        if isinstance(value, dict):
            for key, target in value.items():
                if key == 'source_id' and target not in sources:
                    errors.append(f'{location}: unknown source {target}')
                if key == 'acquisition_id' and target not in acquisitions:
                    errors.append(f'{location}: unknown acquisition {target}')
                check_references(target, location + '/' + key)
        elif isinstance(value, list):
            for offset, child in enumerate(value):
                check_references(child, location + '/' + str(offset))

    for location, value in documents.items():
        check_references(value, location)

    cache_checked = 0
    for identity, row in acquisitions.items():
        if row.get('status') != 'fetched_unreviewed':
            continue
        if not all(key in row for key in ('path', 'bytes', 'sha256', 'review_scope', 'format_validation')):
            errors.append(f'{identity}: incomplete acquisition metadata')
            continue
        if args.check_cache:
            path = REPO / row['path']
            if not path.is_file():
                errors.append(f'{identity}: missing cache {path}')
                continue
            data = path.read_bytes()
            if len(data) != row['bytes'] or hashlib.sha256(data).hexdigest() != row['sha256']:
                errors.append(f'{identity}: cache size/digest mismatch')
            cache_checked += 1

    coverage = rows('coverage.json', 'coverage')
    identities = [row.get('level') or row.get('direction') for row in coverage]
    if len(identities) != 20 or len(set(identities)) != 20:
        errors.append('coverage: expected 20 distinct scope identities')
    if sum('level' in row for row in coverage) != 16 or sum('direction' in row for row in coverage) != 4:
        errors.append('coverage: expected 16 levels and 4 parallel directions')

    if set(milestones) != {f'M{i}' for i in range(1, 8)}:
        errors.append('milestones: expected M1 through M7')
    for identity, row in milestones.items():
        if row.get('status') not in {'pending', 'in_progress', 'passed', 'reopened'}:
            errors.append(f'{identity}: invalid status')
        for gid in row.get('gap_ids', []):
            if gid not in gaps:
                errors.append(f'{identity}: unknown gap {gid}')
        for ref in row.get('evidence_paths', []):
            if not (BASE / ref).is_file():
                errors.append(f'{identity}: missing evidence {ref}')
        if row.get('status') == 'passed':
            if not row.get('passed_on') or not row.get('evidence_paths') or not row.get('review_roles'):
                errors.append(f'{identity}: passed without date/evidence/review roles')
            if any(gaps.get(gid, {}).get('status') == 'open' for gid in row.get('gap_ids', [])):
                errors.append(f'{identity}: passed with an open required gap')
    incomplete = [identity for identity, row in milestones.items() if row.get('status') != 'passed']
    open_gaps = [identity for identity, row in gaps.items() if row.get('status') == 'open']
    if args.require_complete and (incomplete or open_gaps):
        errors.append(f'Not complete: milestones={incomplete}; open gaps={open_gaps}')
    report = dict(json_documents=len(documents), sources=len(sources),
                  acquisition_attempts=len(acquisitions), cache_files_checked=cache_checked,
                  scope_rows=len(coverage), incomplete_milestones=incomplete, open_gaps=open_gaps,
                  bookkeeping_valid=not errors, errors=errors,
                  limitation='Bookkeeping validation does not establish rights, content correctness or educational validity.')
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 1 if errors else 0


if __name__ == '__main__':
    raise SystemExit(main())
