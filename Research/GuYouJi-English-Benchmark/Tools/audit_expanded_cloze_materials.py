#!/usr/bin/env python3
"""Recheck nineteen selected clozes, component load and local text duplication.

No answer adjudication, population grade ranges, rights or whole-library claim.
Old thirteen-material report stays frozen; source numbers are excluded explicitly.
"""
import hashlib
import json
import re
from grade_mode_evidence import REPO, CURRENT_BATCHES, load_ref
from profile_cloze_reference_batch import CASES
from audit_cloze_materials import EXTRA, normalized, shingles
from profile_task_load import count

NEW = [
    (9, 'grade9-boxing2025-21cnjy24857076', 'cloze', 'Wang Xiaoying, 28,', '\n11. A. programs', list(range(11, 21)), 'underscored'),
    (9, 'grade9-zhongshan2025-21cnjy22278047', 'cloze', 'Last month, Emily,', '\n11. A. tallest', list(range(11, 26)), 'bare_numbers'),
    (10, 'grade10-jinhua2025-21cnjy22399612', 'cloze', 'With annoying delays', '\n41. A. died down', list(range(41, 56)), 'underscored'),
    (10, 'grade10-weishi2026-21cnjy25962499', 'cloze', 'I grew up in France', '\n21. A．spots', list(range(21, 36)), 'underscored'),
    (11, 'grade11-heze2026-21cnjy24886046', 'cloze', '"When I first started', '\n41. A. majoring', list(range(41, 56)), 'number_suffix'),
    (12, 'grade12-linyi2025-21cnjy24838709', 'cloze', 'The walk I’d plotted', '\n21. A. aching', list(range(21, 36)), 'underscored'),
]


def digest(text):
    return hashlib.sha256(text.encode()).hexdigest()


def audit():
    manifest = json.loads(CURRENT_BATCHES.read_text())
    papers = {p['id']: p for ref in manifest['batches'] for p in json.loads(load_ref(ref).read_text())['papers']}
    records, bodies = [], {}
    for grade, pid, local, start, end, ids, style in list(CASES) + EXTRA + NEW:
        paper = papers[pid]
        view = load_ref(paper['resource_text']).read_text()
        first = view.index(start)
        last = view.index(end, first)
        material = view[first:last].strip()
        row = next(r for r in paper['rows'] if r['id'] == pid + '.' + local)
        offsets = []
        for number in ids:
            pattern = {'underscored': r'_+' + str(number) + r'_+',
                       'bare_numbers': r'\b' + str(number) + r'\b',
                       'number_suffix': r'\b' + str(number) + r'\s*[.．]\s*_+'}[style]
            found = list(re.finditer(pattern, material))
            if len(found) != 1:
                raise ValueError('Missing or repeated blank: ' + pid + '/' + str(number))
            offsets.append((found[0].start(), found[0].end(), number))
        if [n for _, _, n in sorted(offsets)] != ids or len(ids) != row['shape']['responses']:
            raise ValueError('Blank sequence or count differs')
        unfilled = material
        for begin, finish, _ in sorted(offsets, reverse=True):
            unfilled = unfilled[:begin] + unfilled[finish:]
        options = []
        wanted = list('ABCD')[:row['shape']['options_each']]
        for number in ids:
            match = re.search(r'^' + str(number) + r'\s*(?:[.．]\s*|\s+)(.*)$', view[last:], re.M)
            if not match:
                raise ValueError('Missing option row')
            labels = re.findall(r'(?:^|\s)([A-D])[.．]\s*', match[1])
            if labels != wanted:
                raise ValueError('Incomplete or differently ordered options: ' + pid)
            # Count content only; source number and four letter labels excluded.
            options.append(re.sub(r'(?:^|\s)[A-D][.．]\s*', ' ', match[1]))
        body = normalized(unfilled)
        bodies[row['id']] = body
        records.append({'group_id': row['id'], 'grade': grade, 'paper_identity': pid,
                        'source_acquisition_id': paper['acquisition_id'], 'source_text': paper['resource_text'],
                        'material_line_span_1based': [view[:first].count('\n') + 1, view[:last].count('\n') + 1],
                        'material_sha256': digest(material), 'normalized_material_sha256': digest(body),
                        'blank_offsets_in_material': sorted(offsets), 'responses': len(ids),
                        'options_each': len(wanted), 'material_counts': count(unfilled),
                        'option_content_counts': count('\n'.join(options)),
                        'instruction_counts_included': False, 'student_minutes': None,
                        'independent_answer_gold': False})
    comparisons = []
    for i, left in enumerate(bodies):
        for right in list(bodies)[i + 1:]:
            a, b = shingles(bodies[left]), shingles(bodies[right])
            overlap = len(a & b) / len(a | b) if a | b else 0
            comparisons.append({'left': left, 'right': right,
                                'exact_normalized_match': bodies[left] == bodies[right],
                                'fivegram_jaccard': overlap, 'review_candidate': overlap >= 0.5})
    old = json.loads((REPO / 'build/english-benchmark-research-20261012/cloze-material-audit20261015-v0.1.json').read_text())
    current = {r['group_id']: r for r in records}
    for previous in old['records']:
        now = current[previous['group_id']]
        if previous['unfilled_material_counts'] != now['material_counts'] or previous['material_sha256'] != now['material_sha256']:
            raise ValueError('Frozen thirteen-material measurement no longer reproduces')
    return {'version': '0.1', 'scope': 'nineteen_selected_new_text_clozes_only',
            'records': records, 'comparisons': comparisons, 'old13_reproduced': True,
            'exact_repeated_pairs': sum(x['exact_normalized_match'] for x in comparisons),
            'review_candidates': sum(x['review_candidate'] for x in comparisons),
            'candidate_threshold_is_engineering_screen': True,
            'all_benchmark_deduplication_complete': False, 'model_called': False}


if __name__ == '__main__':
    result = audit()
    output = REPO / 'build/english-benchmark-research-20261012/cloze-material-audit20261015c-v0.1.json'
    payload = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if output.exists() and output.read_text() != payload:
        raise ValueError('Refuse to overwrite a different audit')
    if not output.exists():
        output.write_text(payload)
    print(json.dumps({'materials': len(result['records']), 'parents': len({r['paper_identity'] for r in result['records']}),
                      'pairs': len(result['comparisons']), 'exact_repeat_pairs': result['exact_repeated_pairs'],
                      'near_candidates': result['review_candidates'], 'old13_reproduced': result['old13_reproduced'],
                      'new6': [{'grade': r['grade'], 'responses': r['responses'],
                                'material_tokens': r['material_counts']['english_digit_tokens'],
                                'option_tokens': r['option_content_counts']['english_digit_tokens']} for r in result['records'][-6:]]}))
