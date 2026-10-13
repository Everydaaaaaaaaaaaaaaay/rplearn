#!/usr/bin/env python3
"""Inspect one frozen native lexical database; never infer CEFR/grade/sense choice.

Source WordNet 3.1 offsets are bytes in original data files, not Unicode spans.
Parse directly from tar, never execute or extract source paths. Retain the native
permission/copyright/disclaimer notice in every output containing source data.
"""
import argparse
import collections
import hashlib
import json
import re
import tarfile
from pathlib import Path

EXPECTED_SHA256 = '3f7d8be8ef6ecc7167d39b10d66954ec734280b5bdcd57f7d9eafe429d11c22a'
POS_FILES = {'n': 'noun', 'v': 'verb', 'a': 'adj', 'r': 'adv'}


def inspect(archive, queries):
    if hashlib.sha256(archive.read_bytes()).hexdigest() != EXPECTED_SHA256:
        raise ValueError('Unreviewed archive identity; review before changing version rules')
    with tarfile.open(archive) as source:
        names = [m.name for m in source.getmembers()]
        if len(names) != len(set(names)):
            raise ValueError('Duplicate archive member identity')
        data = {pos: source.extractfile('dict/data.' + name).read()
                for pos, name in POS_FILES.items()}
        indexes = {pos: source.extractfile('dict/index.' + name).read()
                   for pos, name in POS_FILES.items()}
        sense_raw = source.extractfile('dict/index.sense').read()
        exceptions = {pos: source.extractfile('dict/' + name + '.exc').read()
                      for pos, name in POS_FILES.items()}
    notice = '\n'.join(line.decode('ascii') for line in data['n'].splitlines()
                       if line.startswith(b'  ')) + '\n'
    if 'WordNet 3.1 Copyright 2011' not in notice or 'ALL copies' not in notice:
        raise ValueError('Versioned permission/copyright notice not established')
    synsets, lemma_index, counts = {}, {}, {}
    for pos, name in POS_FILES.items():
        position, synsets[pos], lemma_index[pos] = 0, {}, {}
        for line in data[pos].splitlines(keepends=True):
            if not line.startswith(b'  '):
                fields, gloss = line.decode('ascii').rstrip('\n').split(' | ', 1)
                fields = fields.split()
                offset, word_count = int(fields[0]), int(fields[3], 16)
                if offset != position or offset in synsets[pos]:
                    raise ValueError('Native synset byte offset mismatch/duplicate')
                words = [fields[4 + 2 * i] for i in range(word_count)]
                synsets[pos][offset] = dict(offset=offset, synset_type=fields[2],
                                            words=words, gloss=gloss)
            position += len(line)
        for line in indexes[pos].splitlines():
            if line.startswith(b'  '):
                continue
            f = line.decode('ascii').split()
            lemma, category, synset_count, pointers = f[0], f[1], int(f[2]), int(f[3])
            offsets = list(map(int, f[6 + pointers:]))
            if category != pos or len(offsets) != synset_count or lemma in lemma_index[pos]:
                raise ValueError('Native lemma index identity/count mismatch')
            for offset in offsets:
                synset = synsets[pos].get(offset)
                if synset is None or lemma not in {
                        re.sub(r'\((?:a|p|ip)\)$', '', word).lower() for word in synset['words']}:
                    raise ValueError('Lemma index does not point to a containing native synset')
            lemma_index[pos][lemma] = dict(offsets=offsets, tagged_senses=int(f[5 + pointers]))
        counts[pos] = dict(lemmas=len(lemma_index[pos]), synsets=len(synsets[pos]),
                           index_sense_references=sum(len(x['offsets']) for x in lemma_index[pos].values()))
    sense_counts, sense_ids = collections.Counter(), set()
    for line in sense_raw.splitlines():
        key, offset, ordinal, tags = line.decode('ascii').split()
        if key in sense_ids:
            raise ValueError('Duplicate native sense key')
        sense_ids.add(key)
        lemma, suffix = key.split('%', 1)
        pos = {'1': 'n', '2': 'v', '3': 'a', '4': 'r', '5': 'a'}[suffix[0]]
        offset, ordinal = int(offset), int(ordinal)
        row = lemma_index[pos].get(lemma)
        if row is None or ordinal < 1 or ordinal > len(row['offsets']) or row['offsets'][ordinal - 1] != offset:
            raise ValueError('Sense key/ordinal disagrees with native lemma index')
        sense_counts[pos] += 1
    candidates = []
    identities = set()
    for q in queries:
        if set(q) != {'id', 'lemma', 'pos', 'context_note'} or q['id'] in identities:
            raise ValueError('Supply unique explicit lemma/POS/context query identities')
        if not all(isinstance(v, str) and v for v in q.values()) or q['pos'] not in POS_FILES:
            raise ValueError('Invalid explicit query; no automatic case/POS/lemma mapping')
        identities.add(q['id'])
        row = lemma_index[q['pos']].get(q['lemma'])
        candidates.append({**q, 'candidate_senses': [] if row is None else [
            {'native_sense_ordinal': i, **synsets[q['pos']][offset]}
            for i, offset in enumerate(row['offsets'], 1)],
            'chosen_sense': None, 'CEFR': None, 'Chinese_grade': None,
            'context_disambiguation': 'not_established_by_native_lookup'})
    return dict(version='Princeton WordNet 3.1', archive_sha256=EXPECTED_SHA256,
                native_license_notice=notice, counts=counts,
                sense_keys_by_pos=dict(sense_counts), unique_sense_keys=len(sense_ids),
                native_byte_offsets_and_index_membership_checked=True,
                exceptions_note='Native lists may contain absent lemmas; no automatic lemmatization applied',
                exception_file_rows={pos: len(raw.splitlines()) for pos, raw in exceptions.items()},
                candidates=candidates, learner_level_or_sense_admission=False,
                limitation='Native referential consistency only, not semantic/curriculum/CEFR validation or complete rights adjudication')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--queries', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.resolve() in (args.archive.resolve(), args.queries.resolve()):
        raise ValueError('Output cannot overwrite source inputs')
    if args.output.exists() or args.output.is_symlink():
        raise FileExistsError('Use a fresh output path; never overwrite a frozen audit or source view')
    result = inspect(args.archive, json.loads(args.queries.read_text()))
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k not in ('native_license_notice', 'candidates')}, indent=2))


if __name__ == '__main__':
    main()
