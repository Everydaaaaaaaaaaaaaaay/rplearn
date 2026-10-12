#!/usr/bin/env python3
"""Inspect two reviewed Oxford PDFs into a private candidate index.

Requires pypdf. Preserves grouped display headwords, qualifiers and POS levels.
Only explicit, uniquely located, evidence-backed repairs are applied. No word
sense inference, automatic aliases, grade assignment or rights determination.
Keep source text/index output in ignored research storage.
"""
import argparse
import collections
import hashlib
import json
import re
from pathlib import Path

from pypdf import PdfReader, __version__ as PYPDF_VERSION

SOURCES = {
    '3000': {'sha256': '441aa79b39a720afbe78bf944f8df49bce9f61977c8ac2be9fbcbc81cd94046f',
             'pages': 12, 'levels': ['A1', 'A2', 'B1', 'B2'],
             'intro': {'The Oxford 3000™ by CEFR level',
                       'The Oxford 3000 is the list of the 3000 most important words to learn in English, from A1 to B2 level.'}},
    '5000_additional': {'sha256': '6577e6eb8745226ab7ab80912e83d285cf421ec70e61c92d74d5fef5f2c99570',
                        'pages': 8, 'levels': ['B2', 'C1'],
                        'intro': {'The Oxford 5000 ™ by CEFR level',
                                  'The Oxford 5000 is an expanded core word list for advanced learners of English. As well as the Oxford',
                                  '3000, it includes an additional 2000 words for learners at B2-C1 level, which are listed here.'}}
}
POS = ('indefinite article', 'definite article', 'infinitive marker',
       'auxiliary v.', 'modal v.', 'number', 'exclam.', 'prep.', 'pron.',
       'conj.', 'det.', 'adj.', 'adv.', 'noun.', 'n.', 'v.')
TOKEN = '(?:' + '|'.join(re.escape(x) for x in POS) + ')'
ENTRY = re.compile(r'^(.+?)\s+(' + TOKEN + r'(?:\s*[,/]\s*' + TOKEN + r')*)$')
FOOTER = re.compile(r'^© Oxford University Press (\d+) / (\d+)(?:The Oxford (?:3000|5000)™ by CEFR level)?$')


def normalise(value):
    return ' '.join(value.split())


def repair_page(lines, repairs, page):
    result = list(lines)
    applications = []
    for repair in repairs:
        if repair['pdf_page'] != page:
            continue
        wanted = [normalise(x) for x in repair['source_lines']]
        if (len(wanted) < 2 or not repair.get('visual_evidence') or
                not repair.get('reason') or repair.get('join_with') not in ('', ' ')):
            raise ValueError('Repair needs multiple lines, visual evidence, reason and explicit join')
        evidence = Path(repair['visual_evidence'])
        if not evidence.is_file() or evidence.stat().st_size == 0:
            raise ValueError('Repair visual evidence file missing or empty')
        found = [i for i in range(len(result) - len(wanted) + 1)
                 if [x['normalised'] for x in result[i:i + len(wanted)]] == wanted]
        if len(found) != 1:
            raise ValueError(f'Page {page}: repair sequence missing or ambiguous')
        offset = found[0]
        fragments = result[offset:offset + len(wanted)]
        combined = normalise(repair['join_with'].join(wanted))
        merged = {'normalised': combined, 'raw_lines': [x for f in fragments for x in f['raw_lines']],
                  'native_line_numbers': [x for f in fragments for x in f['native_line_numbers']],
                  'explicit_repair': repair}
        result[offset:offset + len(wanted)] = [merged]
        applications.append({'pdf_page': page, 'native_line_numbers': merged['native_line_numbers'],
                             'result': combined, 'reason': repair['reason'],
                             'visual_evidence': repair['visual_evidence'],
                             'visual_evidence_sha256': hashlib.sha256(evidence.read_bytes()).hexdigest()})
    return result, applications


def inspect(path, label, repairs):
    spec = SOURCES[label]
    blob = path.read_bytes()
    digest = hashlib.sha256(blob).hexdigest()
    if digest != spec['sha256']:
        raise ValueError(f'{label}: unreviewed PDF digest')
    reader = PdfReader(path)
    if len(reader.pages) != spec['pages']:
        raise ValueError('PDF page count changed')
    entries, unresolved, applications, headings, native = [], [], [], [], []
    level = None
    for number, page in enumerate(reader.pages, 1):
        text = page.extract_text()
        native.append({'pdf_page': number, 'text': text,
                       'sha256': hashlib.sha256(text.encode()).hexdigest()})
        lines = [{'normalised': normalise(raw), 'raw_lines': [raw], 'native_line_numbers': [i]}
                 for i, raw in enumerate(text.splitlines(), 1) if normalise(raw)]
        lines, applied = repair_page(lines, repairs, number)
        applications.extend(applied)
        footers = 0
        for row in lines:
            line = row['normalised']
            footer = FOOTER.fullmatch(line)
            if footer:
                if tuple(map(int, footer.groups())) != (number, spec['pages']):
                    raise ValueError('Footer page identity mismatch')
                footers += 1
                continue
            if number == 1 and line in spec['intro']:
                continue
            if line in spec['levels']:
                headings.append(line)
                level = line
                continue
            match = ENTRY.fullmatch(line)
            if not match or level is None:
                unresolved.append({'pdf_page': number, **row, 'reason': 'Unrecognised entry or missing level'})
                continue
            headword, pos_text = match.groups()
            if re.search(r'(?:\b(?:noun|adj|adv|prep|pron|det|conj)\.|[,;]$)', headword):
                unresolved.append({'pdf_page': number, **row,
                                   'reason': 'Suspicious POS or punctuation in display headword'})
                continue
            tags = re.findall(TOKEN, pos_text)
            entries.append({'source_list': label, 'pdf_page': number, **row,
                            'display_headword': headword, 'pos_expression': pos_text,
                            'pos_tags': tags, 'level': level,
                            'sense_resolution': 'not_established', 'aliases_expanded': False})
        if footers != 1:
            raise ValueError(f'Page {number}: expected one known footer, got {footers}')
    if headings != spec['levels']:
        raise ValueError(f'Unexpected level section sequence: {headings}')
    if len(applications) != len(repairs):
        raise ValueError('Repair page outside PDF')
    atomic = [(r['display_headword'], p, r['level']) for r in entries for p in r['pos_tags']]
    levels = collections.defaultdict(set)
    for head, pos, lev in atomic:
        levels[head].add(lev)
    summary = {'source_list': label, 'pdf_sha256': digest, 'pdf_bytes': len(blob), 'pages': len(reader.pages),
               'grouped_entry_rows': len(entries), 'pos_level_rows': len(atomic),
               'distinct_display_headwords': len(levels),
               'casefolded_display_headwords': len({h.casefold() for h in levels}),
               'grouped_rows_by_level': dict(collections.Counter(r['level'] for r in entries)),
               'pos_rows_by_level': dict(collections.Counter(x[2] for x in atomic)),
               'headwords_with_multiple_levels': sum(len(v) > 1 for v in levels.values()),
               'duplicate_display_pos_level_rows': len(atomic) - len(set(atomic)),
               'unresolved_native_lines': len(unresolved), 'explicit_repairs': applications,
               'candidate_index_status': 'native_parse_candidate' if not unresolved else 'blocked_unresolved_lines',
               'all_entries_visually_verified': False, 'commercial_use_cleared': False,
               'full_sense_inventory': False, 'Chinese_grade_alignment': 'not_established'}
    return {'summary': summary, 'entries': entries, 'unresolved': unresolved, 'native_pages': native}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--oxford3000', type=Path, required=True)
    parser.add_argument('--oxford5000-additional', type=Path, required=True)
    parser.add_argument('--repairs', type=Path, required=True)
    parser.add_argument('--private-output', type=Path, required=True)
    parser.add_argument('--summary-output', type=Path, required=True)
    args = parser.parse_args()
    repair_spec = json.loads(args.repairs.read_text())
    if set(repair_spec) != set(SOURCES):
        raise ValueError('Repair file needs both exact source lists')
    results = [inspect(args.oxford3000, '3000', repair_spec['3000']),
               inspect(args.oxford5000_additional, '5000_additional', repair_spec['5000_additional'])]
    output = {'method': 'pypdf_native_exact_version_explicit_repairs', 'pypdf_version': PYPDF_VERSION,
              'sources': results, 'production_admission': False}
    args.private_output.write_text(json.dumps(output, ensure_ascii=False, indent=2) + '\n')
    report = {k: output[k] for k in ('method', 'pypdf_version', 'production_admission')}
    report['sources'] = [r['summary'] for r in results]
    args.summary_output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps([{'list': r['summary']['source_list'], 'rows': r['summary']['grouped_entry_rows'],
                       'unresolved': len(r['unresolved'])} for r in results]))
    if any(r['unresolved'] for r in results):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
