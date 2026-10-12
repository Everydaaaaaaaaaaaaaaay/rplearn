#!/usr/bin/env python3
"""Inspect exact NGSL-family files locally; never infer senses or CEFR/grade bands.

Outputs retain publisher rows in a private file. Summary counts describe source
units, not a learner's vocabulary or coverage on an unobserved corpus.
"""
import argparse
import collections
import csv
import hashlib
import json
from decimal import Decimal, InvalidOperation
from pathlib import Path


def parse_rows(path):
    raw = Path(path).read_bytes()
    text = raw.decode('utf-8-sig')
    comments, entries = [], []
    for number, row in enumerate(csv.reader(text.splitlines()), 1):
        if not row:
            continue
        if row[0].startswith('##'):
            comments.append({'csv_record_number': number, 'source_fields': row})
        else:
            entries.append({'csv_record_number': number, 'source_fields': row})
    return raw, comments, entries


def integer_rank(value):
    # The NDL file uses decimal-looking ranks such as '4.'. No row-position fallback.
    try:
        number = Decimal(value)
        if number.is_finite() and number > 0 and number == number.to_integral_value():
            return int(number)
    except InvalidOperation:
        pass
    return None


def inspect(spec, root):
    path = root / spec['file']
    raw, comments, rows = parse_rows(path)
    digest = hashlib.sha256(raw).hexdigest()
    if digest != spec['sha256']:
        raise ValueError(f"{spec['id']}: source digest differs; register a new version")
    header = None
    if 'header' in spec:
        if not rows or rows[0]['source_fields'] != spec['header']:
            raise ValueError(f"{spec['id']}: unexpected source header")
        header = rows.pop(0)
    if len(rows) != spec['expected_rows']:
        raise ValueError(f"{spec['id']}: source row count differs")
    head_column = spec.get('head_column', 0)
    heads, forms, rank_values, missing_ranks = [], collections.defaultdict(list), [], []
    blank_form_fields = 0
    for row in rows:
        fields = row['source_fields']
        if spec.get('width') and len(fields) != spec['width']:
            raise ValueError(f"{spec['id']}: unexpected width at {row['csv_record_number']}")
        if not fields[head_column]:
            raise ValueError(f"{spec['id']}: empty source headword")
        head = fields[head_column]
        heads.append(head)
        row['source_headword'] = head
        if spec.get('kind') == 'forms':
            for form in fields:
                if not form:
                    if not spec.get('allow_padded_forms', False):
                        raise ValueError(f"{spec['id']}: empty source form")
                    blank_form_fields += 1
                    continue  # Preserve source_fields; count permitted source padding.
                forms[form.casefold()].append(head)
        if 'rank_column' in spec:
            value = fields[spec['rank_column']]
            rank = integer_rank(value)
            row['parsed_rank'] = rank
            if rank is None:
                missing_ranks.append({'csv_record_number': row['csv_record_number'],
                                      'source_headword': head, 'source_rank': value})
            else:
                rank_values.append(rank)
    ambiguous = {form: list(dict.fromkeys(values)) for form, values in forms.items()
                 if len(set(values)) > 1}
    ranks = dict(numeric_rank_rows=len(rank_values), unknown_rank_rows=missing_ranks)
    if rank_values:
        ranks.update(min_rank=min(rank_values), max_rank=max(rank_values),
                     distinct_ranks=len(set(rank_values)),
                     duplicate_rank_values=[k for k, n in collections.Counter(rank_values).items() if n > 1],
                     missing_in_1_to_max=sorted(set(range(1, max(rank_values) + 1)) - set(rank_values)),
                     strictly_ascending_in_source_order=all(a < b for a, b in zip(rank_values, rank_values[1:])))
    summary = dict(id=spec['id'], file=spec['file'], bytes=len(raw), sha256=digest,
                   source_header=header, comment_records=len(comments), headword_rows=len(rows),
                   distinct_display_headwords=len(set(heads)),
                   distinct_casefold_headwords=len(set(h.casefold() for h in heads)),
                   source_fields_widths=dict(collections.Counter(len(r['source_fields']) for r in rows)),
                   form_strings=len(forms), ambiguous_form_strings=len(ambiguous),
                   blank_form_fields=blank_form_fields, ranks=ranks)
    return dict(summary=summary, source_comments=comments, source_rows=rows,
                ambiguous_casefold_forms=ambiguous)


def analyse(manifest, root):
    results = [inspect(spec, root) for spec in manifest['files']]
    indexed = {value['summary']['id']: value for value in results}
    if len(indexed) != len(results):
        raise ValueError('Duplicate inspection identity')
    summary = dict(method='native_csv_exact_digest_no_rank_or_sense_inference',
                   observed_on=manifest['observed_on'], production_admission=False,
                   files=[value['summary'] for value in results], comparisons=[])
    for pair in manifest.get('comparisons', []):
        left, right = indexed[pair['left']], indexed[pair['right']]
        get_heads = lambda v: {r['source_headword'].casefold() for r in v['source_rows']}
        a, b = get_heads(left), get_heads(right)
        summary['comparisons'].append(dict(left=pair['left'], right=pair['right'],
                                            casefold_intersection=len(a & b),
                                            left_only=sorted(a - b), right_only_count=len(b - a),
                                            reason='Headword membership only; not meaning equivalence'))
    return dict(summary=summary, files=results)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', required=True, type=Path)
    parser.add_argument('--source-root', required=True, type=Path)
    parser.add_argument('--private-output', required=True, type=Path)
    parser.add_argument('--summary-output', required=True, type=Path)
    args = parser.parse_args()
    result = analyse(json.loads(args.manifest.read_text()), args.source_root)
    for path, value in [(args.private_output, result), (args.summary_output, result['summary'])]:
        path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(dict(files=len(result['files']),
                          total_source_rows=sum(v['summary']['headword_rows'] for v in result['files']),
                          production_admission=False)))


if __name__ == '__main__':
    main()
