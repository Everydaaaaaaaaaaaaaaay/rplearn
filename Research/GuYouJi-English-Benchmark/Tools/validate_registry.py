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
    parser.add_argument('--check-processing', action='store_true')
    parser.add_argument('--check-storage', action='store_true')
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
                if key == 'source_id' and (not isinstance(target, str) or target not in sources):
                    errors.append(f'{location}: unknown source {target}')
                if key == 'acquisition_id' and (not isinstance(target, str) or target not in acquisitions):
                    errors.append(f'{location}: unknown acquisition {target}')
                check_references(target, location + '/' + key)
        elif isinstance(value, list):
            for offset, child in enumerate(value):
                check_references(child, location + '/' + str(offset))

    for location, value in documents.items():
        if location.endswith('.schema.json') and isinstance(value, dict) and '$schema' in value:
            continue  # Field definitions are not source/acquisition references.
        check_references(value, location)

    cache_checked = 0
    for identity, row in acquisitions.items():
        if row.get('status') != 'fetched_unreviewed' and not row.get('path'):
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

    processing_checked = 0
    if args.check_processing:
        processing = documents.get('Registry/processing.json', {})
        for run in processing.get('runs', []):
            pages = run.get('page_records', [])
            if len(pages) != run.get('pages'):
                errors.append(f"{run.get('id')}: processing page count mismatch")
            for page in pages:
                if page.get('exit_code') != 0:
                    continue
                output = page.get('output') or page.get('output_prefix', '') + '.txt'
                pairs = [(output, page.get('sha256'))]
                if page.get('tsv_output'):
                    pairs.append((page['tsv_output'], page.get('tsv_sha256')))
                for filename, digest in pairs:
                    path = REPO / filename
                    if not path.is_file() or not digest:
                        errors.append(f"{run.get('id')}: missing processing output/digest {filename}")
                    elif hashlib.sha256(path.read_bytes()).hexdigest() != digest:
                        errors.append(f"{run.get('id')}: processing digest mismatch {filename}")
                    processing_checked += 1

    storage_checked = 0
    if args.check_storage:
        snapshots = documents.get('Storage/local-snapshots.json', {}).get('snapshots', [])
        if not snapshots:
            errors.append('storage: no registered local snapshot')
        for snapshot in snapshots:
            root = Path(snapshot['snapshot_path']).resolve()
            manifest_path = Path(snapshot['manifest_path']).resolve()
            if root not in manifest_path.parents or not manifest_path.is_file():
                errors.append('storage: missing or out-of-root manifest')
                continue
            data = manifest_path.read_bytes()
            if hashlib.sha256(data).hexdigest() != snapshot['manifest_sha256']:
                errors.append('storage: manifest digest mismatch')
                continue
            manifest = json.loads(data)
            files = manifest['files']
            if (len(files) != snapshot['files_verified'] or
                    sum(row['bytes'] for row in files) != snapshot['bytes_verified']):
                errors.append('storage: manifest count/size mismatch')
            for row in files:
                path = (root / row['path']).resolve()
                if root not in path.parents or not path.is_file():
                    errors.append(f"storage: missing/out-of-root asset {row['path']}")
                    continue
                payload = path.read_bytes()
                if (len(payload) != row['bytes'] or
                        hashlib.sha256(payload).hexdigest() != row['sha256']):
                    errors.append(f"storage: asset digest/size mismatch {row['path']}")
                storage_checked += 1

    coverage = rows('coverage.json', 'coverage')
    identities = [row.get('level') or row.get('direction') for row in coverage]
    if len(identities) != 20 or len(set(identities)) != 20:
        errors.append('coverage: expected 20 distinct scope identities')
    if sum('level' in row for row in coverage) != 16 or sum('direction' in row for row in coverage) != 4:
        errors.append('coverage: expected 16 levels and 4 parallel directions')

    detailed = documents.get('Registry/coverage-cells.json', {})
    cells = detailed.get('cells', [])
    if detailed:
        cell_index = index(cells, 'priority coverage cells')
        expected_cells = {(grade, term, publisher) for grade in range(7, 13)
                          for term in ('upper', 'lower')
                          for publisher in ('PEP', 'FLTRP', 'Yilin')}
        actual_cells = {(row.get('grade'), row.get('semester'), row.get('publisher'))
                        for row in cells}
        if len(cell_index) != 36 or actual_cells != expected_cells:
            errors.append('priority coverage: expected 36 distinct grade/term/series plan cells')
        unit_index = index(documents.get('Curriculum/pep-junior-unit-index.json', {}).get('units', []),
                           'PEP unit index')
        for row in cells:
            for uid in row.get('known_unit_index_ids', []):
                unit = unit_index.get(uid)
                if (not unit or row['publisher'] != 'PEP' or
                        (row['grade'], row['semester']) != (unit['grade'], unit['semester'])):
                    errors.append(f"priority coverage: incorrect unit reference {row['id']}/{uid}")
        remaining = detailed.get('remaining_full_scope_records', [])
        expected_remaining = set(identities) - {'junior1', 'junior2', 'junior3',
                                                'senior1', 'senior2', 'senior3'}
        if (len(remaining) != 14 or
                {row.get('scope_id') for row in remaining} != expected_remaining):
            errors.append('priority coverage: remaining 14 required scopes missing/duplicated')

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
                  processing_outputs_checked=processing_checked,
                  storage_files_checked=storage_checked,
                  scope_rows=len(coverage), incomplete_milestones=incomplete, open_gaps=open_gaps,
                  priority_coverage_cells=len(cells),
                  bookkeeping_valid=not errors, errors=errors,
                  limitation='Bookkeeping validation does not establish rights, content correctness or educational validity.')
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 1 if errors else 0


if __name__ == '__main__':
    raise SystemExit(main())
