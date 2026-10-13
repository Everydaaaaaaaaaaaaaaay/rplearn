#!/usr/bin/env python3
"""Frozen v0.3 checks plus complete local SVG option bindings, default index0.6.

Format/digest and option completeness only, not image understanding or difficulty.
"""
import json
import xml.etree.ElementTree as ET
import validate_firstrelease_v0_3 as core

ORIGINAL_CHECK = core.check


def image_bindings(row, authored, text):
    assets = authored.get('required_image_assets', [])
    required = authored.get('image_option_question_numbers', [])
    if not required or not assets:
        raise ValueError('image-option task requires explicit question numbers and all assets')
    if any(type(q) is not int or not 1 <= q <= authored['questions'] for q in required):
        raise ValueError('image question outside actual item range')
    if len(set(required)) != len(required):
        raise ValueError('duplicate image question')
    seen = set()
    for asset in assets:
        key = (asset['question_number'], asset['option_label'])
        if key in seen or key[0] not in required:
            raise ValueError('duplicate/wrong question image option')
        seen.add(key)
        target = core.file_ref(asset)
        if target.suffix != '.svg':
            raise ValueError('this version checks local SVG only; other media needs its own review')
        root = ET.fromstring(target.read_text())
        if root.tag != '{http://www.w3.org/2000/svg}svg':
            raise ValueError('asset is not SVG')
        if any(e.tag.rsplit('}', 1)[-1] in {'script', 'foreignObject', 'image'}
               or any(k.rsplit('}', 1)[-1] in {'href', 'src'} or k.lower().startswith('on')
                      for k in e.attrib) for e in root.iter()):
            raise ValueError('external/executable SVG content is outside this local diagram contract')
        embed = asset['markdown_embed_path']
        if '](' + embed + ')' not in text:
            raise ValueError('required image not embedded in candidate')
        if (core.BASE / row['candidate']['path']).parent.joinpath(embed).resolve() != target.resolve():
            raise ValueError('embed points to different asset')
    for q in required:
        if len({a['path'] for a in assets if a['question_number'] == q}) != authored['options_each']:
            raise ValueError('same image asset reused as distinct options')
    labels = set('ABCD'[:authored['options_each']])
    for q in required:
        if {label for n, label in seen if n == q} != labels:
            raise ValueError('image question lacks complete distinct option labels')
    return len(assets)


def check(data, check_cache=False):
    result = ORIGINAL_CHECK(data, check_cache)
    checked = 0
    observations = {g['id']: g for g in json.loads((core.BASE / 'FirstRelease/source-group-observations.json').read_text())['groups']}
    for row in data.get('candidates', []):
        must_have = any(observations.get(i, {}).get('features', {}).get('all4_image_options_required')
                        for i in row.get('anchor_group_ids', []))
        if not must_have:
            continue
        try:
            authored = json.loads(core.file_ref(row['author_check']).read_text())
            text = core.file_ref(row['candidate']).read_text()
            checked += image_bindings(row, authored, text)
        except (KeyError, ValueError, OSError, ET.ParseError) as exc:
            result['errors'].append(row.get('id', '?') + ': image bindings: ' + str(exc))
    result['local_image_option_assets_checked'] = checked
    result['bindings_and_structure_valid'] = not result['errors']
    return result


if __name__ == '__main__':
    core.DEFAULT = core.BASE / 'FirstRelease/review-index-v0.6.json'
    core.check = check
    raise SystemExit(core.main())
