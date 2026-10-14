#!/usr/bin/env python3
"""Save current registered assets by content identity, never a new full tree.

Tracked metadata stays in Git. Original/processed versions are immutable objects;
an atomic current path/hash index is updated. Repeated runs add no equal objects.
"""
import argparse
import json
import os
import tempfile
from pathlib import Path
from snapshot_research_assets import BASE, REPO, copy_asset, digest
from compact_research_snapshots import atomic_json


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    registry_path = BASE / 'Storage/local-snapshots.json'
    registry = json.loads(registry_path.read_text())
    if not registry.get('content_archives'):
        raise ValueError('Verified historical content archive required first')
    archive = registry['content_archives'][-1]
    root = Path(archive['archive_path']).resolve()
    store = root / 'objects'
    index_path = root / 'current-asset-index.json'
    previous_record = registry.get('current_asset_preservation', {})
    previous = {}
    if index_path.exists() and previous_record.get('index_path') == str(index_path):
        if digest(index_path) != previous_record['index_sha256']:
            raise ValueError('Current preservation index changed outside registration')
        previous = {r['path']: r for r in json.loads(index_path.read_text())['records']}
    registered = {}
    source_hashes = 0

    def fingerprint(path):
        stat = path.stat()
        return [stat.st_dev, stat.st_ino, stat.st_size, stat.st_mtime_ns, stat.st_ctime_ns]

    def register(filename, expected=None, expected_bytes=None):
        nonlocal source_hashes
        relative = Path(filename)
        if relative.is_absolute() or '..' in relative.parts or relative.parts[0] != 'build':
            raise ValueError('Only registered relative research-cache paths are eligible')
        path = REPO / relative
        if not path.is_file() or path.is_symlink():
            raise ValueError('Missing/linked registered asset: ' + filename)
        prior = previous.get(filename, {})
        current_fingerprint = fingerprint(path)
        if prior.get('source_fingerprint') == current_fingerprint and (expected is None or expected == prior.get('sha256')):
            actual = prior['sha256']
        else:
            actual = digest(path)
            source_hashes += 1
        size = path.stat().st_size
        if (expected and actual != expected) or (expected_bytes is not None and size != expected_bytes):
            raise ValueError('Registered asset digest/size differs: ' + filename)
        if filename in registered and registered[filename]['sha256'] != actual:
            raise ValueError('Conflicting current versions')
        registered[filename] = {'path': filename, 'sha256': actual, 'bytes': size, 'source_fingerprint': current_fingerprint}

    acquisitions = json.loads((BASE / 'Registry/acquisitions.json').read_text())
    for row in acquisitions['acquisitions']:
        filename = row.get('path') or row.get('cache_path')
        if filename:
            register(filename, row.get('sha256'), row.get('bytes'))
        if row.get('manifest'):
            register(row['manifest'])
    processing = json.loads((BASE / 'Registry/processing.json').read_text())
    for model in processing.get('ocr_models', []):
        register(model['path'], model.get('sha256'))
    for run in processing['runs']:
        if run.get('manifest'):
            register(run['manifest'])
        for page in run.get('page_records', []):
            if page.get('exit_code') != 0:
                continue
            for key in ('source', 'source_crop'):
                if page.get(key):
                    register(page[key], page.get(key + '_sha256'))
            register(page.get('output') or page['output_prefix'] + '.txt', page['sha256'])
            if page.get('tsv_output'):
                register(page['tsv_output'], page['tsv_sha256'])
    unique = {r['sha256']: r for r in registered.values()}
    new_count = new_bytes = 0
    archive_hashes = 0
    object_fingerprints = {}
    for h, row in unique.items():
        target = store / h
        if not target.exists():
            copy_asset(REPO / row['path'], target)
            new_count += 1
            new_bytes += row['bytes']
        if target.is_symlink() or target.stat().st_size != row['bytes']:
            raise ValueError('Preserved object differs')
        prior = previous.get(row['path'], {})
        if prior.get('sha256') != h or prior.get('object_fingerprint') != fingerprint(target):
            if digest(target) != h:
                raise ValueError('Preserved object hash differs')
            archive_hashes += 1
        if target.stat().st_mode & 0o222:
            os.chmod(target, 0o400)
        object_fingerprints[h] = fingerprint(target)
    for row in registered.values():
        row['object_fingerprint'] = object_fingerprints[row['sha256']]
    index = {'version': '0.1', 'archive_id': archive['archive_id'], 'records': sorted(registered.values(), key=lambda r: r['path']),
             'current_cache_mutations': 0, 'new_full_snapshots': 0, 'metadata_preserved_in_Git': True}
    if not index_path.exists() or json.loads(index_path.read_text()) != index:
        atomic_json(index_path, index)
    restore = next(iter(unique.values()))
    with tempfile.TemporaryDirectory(prefix='incremental-restore-', dir=root) as scratch:
        target = Path(scratch) / 'restored-asset'
        copy_asset(store / restore['sha256'], target)
        if digest(target) != restore['sha256'] or target.stat().st_ino == (store / restore['sha256']).stat().st_ino:
            raise ValueError('Incremental restore differs')
    record = {'archive_id': archive['archive_id'], 'index_path': str(index_path), 'index_sha256': digest(index_path),
              'current_registered_paths': len(registered), 'current_unique_contents': len(unique),
              'current_unique_bytes': sum(r['bytes'] for r in unique.values()), 'same_host_only': True}
    registry['current_asset_preservation'] = record
    atomic_json(registry_path, registry)
    report = {'current_preservation': record, 'new_objects_created': new_count, 'new_bytes_created': new_bytes,
              'source_hashes_checked': source_hashes, 'archive_hashes_checked': archive_hashes,
              'unchanged_verified_fingerprints_reused': True,
              'new_full_snapshots': 0, 'restore_verified': True, 'current_cache_mutations': 0}
    if args.report.exists() and json.loads(args.report.read_text()) != report:
        raise ValueError('Do not overwrite a different run report')
    if not args.report.exists():
        atomic_json(args.report, report)
    print(json.dumps(report))


if __name__ == '__main__':
    main()
