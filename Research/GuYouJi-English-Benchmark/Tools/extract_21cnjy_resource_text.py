#!/usr/bin/env python3
"""Extract the public resource-description block, preserving BR boundaries.

This is a view of the saved HTML, not reconstruction of omitted images/PDF pages.
No inferred text, answer repair, or full-paper authenticity claim.
"""
import argparse
import hashlib
import html
import json
import re
from pathlib import Path


def extract(path):
    raw = path.read_bytes()
    text = raw.decode('utf-8')
    blocks = re.findall(r'<p[^>]*class="assets-intro"[^>]*>(.*?)</p>', text, re.S)
    if len(blocks) != 1:
        raise ValueError('Expected one public resource block: ' + str(path))
    body = blocks[0]
    view = html.unescape(re.sub(r'<[^>]+>', '', re.sub(r'<br\s*/?>', '\n', body)))
    if len(view.strip()) < 300:
        raise ValueError('Resource block is empty/truncated')
    output = path.parent.parent / (path.stem + '-resource-v0.2.txt')
    if output.exists():
        if output.read_bytes() != view.encode('utf-8'):
            raise ValueError('Refuse to overwrite a different saved extraction: ' + str(output))
    else:
        output.write_text(view, encoding='utf-8')
    return {'input': str(path), 'input_sha256': hashlib.sha256(raw).hexdigest(),
            'output': str(output), 'bytes': output.stat().st_size,
            'sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
            'lines': len(view.splitlines()), 'omitted_image_payloads_reconstructed': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('inputs', type=Path, nargs='+')
    parser.add_argument('--manifest', type=Path, required=True)
    args = parser.parse_args()
    records = [extract(path) for path in args.inputs]
    args.manifest.write_text(json.dumps({'version': '0.2', 'records': records}, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps([{'output': r['output'], 'lines': r['lines'], 'bytes': r['bytes']} for r in records]))
