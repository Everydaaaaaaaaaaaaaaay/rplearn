#!/usr/bin/env python3
"""Archive and restore-check only the new media named by one expansion batch."""
import argparse
import hashlib
import json
import shutil
import tarfile
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('batch')
    parser.add_argument('--run', choices=['2026-10-24', '2026-10-28'], default='2026-10-24')
    args = parser.parse_args()
    if len(args.batch) != 4 or args.batch[0] != 'b' or not args.batch[1:].isdigit():
        raise ValueError('Expected b000-style batch')
    directory = ROOT / 'Backend/config/learning/expansions' / args.run
    manifest = json.loads((directory / (args.batch + '.json')).read_text())
    if manifest['run'] != args.run or manifest['batch'] != args.batch:
        raise ValueError('Selected media batch identity mismatch')
    assets = [(asset, '.png') for asset in manifest.get('imageAssets', [])]
    new_audio = manifest.get('newAudioAssetIds', [])
    selected_audio = [asset for asset in manifest.get('audioAssets', []) if asset['id'] in new_audio]
    if len(new_audio) != len(set(new_audio)) or len(selected_audio) != len(new_audio):
        raise ValueError('Selected new audio identities do not match declared metadata')
    assets += [(asset, '.wav') for asset in selected_audio]
    registry = json.loads((ROOT / 'Research/GuYouJi-English-Benchmark/Storage/local-snapshots.json').read_text())
    objects = Path(registry['content_archives'][-1]['archive_path']) / 'objects'
    work = ROOT / 'build/learning-expansion-assets'
    if args.run != '2026-10-24':
        work = work / args.run
    work.mkdir(exist_ok=True, parents=True)
    rows = []
    added = 0
    for asset, extension in assets:
        source = ROOT / 'Backend/config/learning/originals/media' / (asset['id'] + extension)
        if source.is_symlink() or sha(source) != asset['sha256'] or source.stat().st_size != asset['byteSize']:
            raise ValueError('Changed new asset')
        target = objects / asset['sha256']
        if target.is_symlink():
            raise ValueError('Archive symlink is not permitted')
        if not target.exists():
            shutil.copyfile(source, target)
            added += 1
        if target.is_symlink() or sha(target) != asset['sha256']:
            raise ValueError('Archive differs')
        target.chmod(0o400)
        rows.append(dict(id=asset['id'], sha256=asset['sha256'], bytes=asset['byteSize'], archiveObject=str(target), source=str(source)))
    with tempfile.TemporaryDirectory(prefix='restore-', dir=work) as temp:
        for i, row in enumerate(rows):
            target = Path(temp) / str(i)
            shutil.copyfile(row['archiveObject'], target)
            if sha(target) != row['sha256'] or target.stat().st_ino == Path(row['archiveObject']).stat().st_ino:
                raise ValueError('Independent restore failed')
    pack = work / (args.batch + '.tar.gz')
    with tarfile.open(pack, 'w:gz', compresslevel=1) as archive:
        for row in rows:
            archive.add(row['source'], arcname=Path(row['source']).name, recursive=False)
    record = dict(run=args.run, batch=args.batch, assets=len(rows), newlyArchived=added, restoreChecked=bool(rows), independentlyRestored=len(rows), newFullSnapshots=0, archiveSHA256=sha(pack), transport=str(pack.relative_to(ROOT)), objects=rows)
    (directory / (args.batch + '.assets.json')).write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: v for k, v in record.items() if k != 'objects'}))


if __name__ == '__main__':
    main()
