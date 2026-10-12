#!/usr/bin/env python3
"""Extract review candidates from one hash-pinned secondary PDF, not gold words.

Requires pdfplumber. Full entries remain in an ignored local output directory.
No alias expansion, POS/sense assignment, count repair or grade mapping occurs.
"""
import argparse
import collections
import hashlib
import json
import re
from pathlib import Path

import pdfplumber


EXPECTED_SHA256 = '4d2d0f33e511dc0d239d2cdc53fe16f38a107afde9bd1ae557cec9ce7bb1bba0'
REGULAR_FONT = 'EMLJOL+TimesNewRomanPSMT'
REPO = Path(__file__).resolve().parents[3]


def extract(path):
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest != EXPECTED_SHA256:
        raise ValueError('Unreviewed PDF identity: refuse to reuse page/font/column rules')
    entries, pages = [], []
    with pdfplumber.open(path) as document:
        if len(document.pages) != 178:
            raise ValueError('Unexpected PDF page count')
        for number in range(76, 133):
            words = [w for w in document.pages[number - 1].extract_words(
                extra_attrs=['fontname']) if w['fontname'] == REGULAR_FONT
                and (number != 76 or w['top'] >= 450)]
            starts = collections.Counter(round(w['x0'], 1) for w in words
                                         if re.search('[A-Za-z]', w['text']))
            columns = sorted(x for x, _ in starts.most_common(2))
            if len(columns) != 2 or columns[1] - columns[0] < 180:
                raise ValueError(f'Page {number}: ambiguous two-column starts')
            groups = collections.defaultdict(list)
            for word in words:
                column = 2 if word['x0'] >= columns[1] - 1 else 1
                groups[column, round(word['top'], 1)].append(word)
            count = 0
            for (column, top), blocks in sorted(groups.items()):
                blocks.sort(key=lambda w: w['x0'])
                text = ' '.join(w['text'] for w in blocks)
                if not re.search('[A-Za-z]', text):
                    continue
                suffix = re.search(r'(\*+)$', text)
                stars = len(suffix[0]) if suffix else 0
                if stars > 2 or '*' in text[:-stars or None]:
                    raise ValueError(f'Page {number}: ambiguous star placement')
                entries.append({'pdf_page': number, 'column': column,
                                'top': top, 'raw_entry': text, 'star_count': stars,
                                'bbox': [min(w['x0'] for w in blocks),
                                         min(w['top'] for w in blocks),
                                         max(w['x1'] for w in blocks),
                                         max(w['bottom'] for w in blocks)]})
                count += 1
            pages.append({'pdf_page': number, 'column_starts': columns,
                          'candidate_rows': count})
    counts = collections.Counter(row['star_count'] for row in entries)
    duplicate_rows = [word for word, count in collections.Counter(
        row['raw_entry'] for row in entries).items() if count > 1]
    return {'method': 'font_and_geometry_rows_no_OCR_no_alias_expansion',
            'pdfplumber_version': pdfplumber.__version__, 'input_sha256': digest,
            'status': 'secondary_candidate_requires_source_concordance_and_full_review',
            'canonical_admission': False, 'declared_totals': {'all': 3100,
                'no_star': 1600, 'one_star': 500, 'two_stars': 1000},
            'observed_row_total': len(entries),
            'observed_rows_by_star_count': dict(sorted(counts.items())),
            'duplicate_raw_rows': duplicate_rows, 'pages': pages, 'entries': entries,
            'limitations': ['Rows are not token, variant, lemma or sense counts',
                'Observed total and marker subcounts differ from publisher declaration',
                'No invented missing entry or reassignment to reconcile totals',
                'Exact PDF identity does not establish publisher origin or rights',
                'Only separately registered original-image pages were visually compared']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pdf', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    destination = args.output.resolve()
    cache_root = (REPO / 'build').resolve()
    if cache_root not in destination.parents:
        parser.error('Full candidate entries must be saved under ignored repository build/')
    result = extract(args.pdf)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: result[k] for k in ('observed_row_total',
        'observed_rows_by_star_count', 'duplicate_raw_rows', 'canonical_admission')}))


if __name__ == '__main__':
    main()
