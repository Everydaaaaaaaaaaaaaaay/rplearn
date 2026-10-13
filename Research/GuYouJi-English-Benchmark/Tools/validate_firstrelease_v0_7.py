#!/usr/bin/env python3
"""Image-bound core checks plus real three-passage blank allocation; default0.7."""
import json
import re
import validate_firstrelease_v0_6 as images

core = images.core


def author_evidence_count(text):
    headings = list(re.finditer(r'^## .*?(?:作者|答案).*$', text, re.M))
    if not headings:
        return 0
    # Student choice tables can also have a header 空; exclude the student region.
    author = text[headings[0].end():]
    active = False
    total = 0
    for line in author.splitlines():
        if not line.startswith('|'):
            active = False
            continue
        first = line.strip().strip('|').split('|')[0].strip()
        if first in {'题', '空', 'Item', 'Blank'}:
            active = True
        elif active and re.fullmatch(r'\d+(?:\s+[A-D])?', first):
            total += 1
    return total


def grouped_blanks(authored, text, expected):
    blocks = re.findall(r'<!-- passage:([A-Z]):start -->\n(.*?)\n<!-- passage:\1:end -->', text, re.S)
    if [name for name, _ in blocks] != ['A', 'B', 'C'] or authored.get('subgroup_counts') != expected:
        raise ValueError('three material labels or declared allocation differ')
    nums = [[int(n) for n in re.findall(r'\((\d+)\) _+', body)] for _, body in blocks]
    if [len(n) for n in nums] != expected:
        raise ValueError('actual blank allocation differs from complete source mode')
    if [n for part in nums for n in part] != list(range(1, authored['questions'] + 1)):
        raise ValueError('missing/repeated/out-of-order material blanks')
    return nums


def check(data, check_cache=False):
    result = images.check(data, check_cache)
    groups = {r['id']: r for r in json.loads((core.BASE / 'FirstRelease/source-group-observations.json').read_text())['groups']}
    checked = 0
    for row in data.get('candidates', []):
        sources = [groups.get(g, {}) for g in row.get('anchor_group_ids', [])]
        matches = [g for g in sources if g.get('features', {}).get('materials') == 3]
        if not matches:
            continue
        try:
            authored = json.loads(core.file_ref(row['author_check']).read_text())
            text = core.file_ref(row['candidate']).read_text()
            grouped_blanks(authored, text, matches[0]['features']['subgroup_slots'])
            checked += 1
        except (KeyError, ValueError, OSError) as exc:
            result['errors'].append(row.get('id', '?') + ': grouped blanks: ' + str(exc))
    result['three_material_allocations_checked'] = checked
    result['bindings_and_structure_valid'] = not result['errors']
    return result


if __name__ == '__main__':
    core.author_evidence_count = author_evidence_count
    core.DEFAULT = core.BASE / 'FirstRelease/review-index-v0.7.json'
    core.check = check
    raise SystemExit(core.main())
