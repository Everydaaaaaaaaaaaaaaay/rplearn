"""Unhinted whole-passage atomic edits, not ten known-location fill slots."""
import re
from itertools import product

WORD = re.compile(r"[A-Za-z]+(?:['’-][A-Za-z]+)*")


def tokens(sentence):
    return list(WORD.finditer(sentence))


def edit_key(edit):
    return (edit['sentence'], edit['position'], edit['operation'], edit['text'].replace('’', "'").casefold())


def apply_edits(sentences, edits):
    result = []
    for n, sentence in enumerate(sentences, 1):
        spans = tokens(sentence); operations = []
        for edit in edits:
            if edit['sentence'] != n:
                continue
            index = edit['position'] - 1
            if edit['operation'] == 'insert':
                start = spans[index].start() if index < len(spans) else len(sentence.rstrip('.!?'))
                operations.append((start, start, edit['text'] + ' ' if index < len(spans) else ' ' + edit['text']))
            else:
                span = spans[index]
                operations.append((span.start(), span.end(), edit['text']))
        for start, end, text in sorted(operations, reverse=True):
            sentence = sentence[:start] + text + sentence[end:]
        result.append(re.sub(r'\s+([,.!?;:])', r'\1', re.sub(r' +', ' ', sentence)).strip())
    return result


def validate(group, audit=None):
    c = group['wordEditing']; qs = group['questions']
    assert group['kind'] == 'passage_word_editing'
    assert c['version'] == 1 and c['errors'] == c['firstScoredEdits'] == len(qs) == 10
    assert c['wordsPerEdit'] == 1 and c['maxEditsPerSentence'] == 2
    assert c['order'] == 'any' and c['unlisted'] == 'review'
    assert c['normalization'] == 'non_case_target_word_v1' and c['caseOnlyTargets'] is False
    sentences = c['sentences']; assert len(sentences) >= 5
    assert all(isinstance(s, str) and tokens(s) and re.search(r'[.!?]$', s) for s in sentences)
    seen = set()
    for n, q in enumerate(qs, 1):
        assert q['number'] == n and q['stem'] == f'修改记录{n}（任选错误，顺序不限）'
        assert not q['options'] and q['rationale'] and q['editAlternatives']
        assert not any(q.get(k) for k in ['acceptedAnswers', 'fillMarking', 'parts', 'knownForms'])
        for edit in q['editAlternatives']:
            assert set(edit) == {'sentence', 'position', 'operation', 'text'}
            assert type(edit['sentence']) is int and 1 <= edit['sentence'] <= len(sentences)
            length = len(tokens(sentences[edit['sentence'] - 1]))
            assert type(edit['position']) is int and 1 <= edit['position'] <= length + (edit['operation'] == 'insert')
            assert edit['operation'] in {'insert', 'delete', 'replace'}
            assert (edit['text'] == '') if edit['operation'] == 'delete' else bool(WORD.fullmatch(edit['text']))
            key = edit_key(edit); assert key not in seen; seen.add(key)
            if edit['operation'] == 'replace':
                old = tokens(sentences[edit['sentence'] - 1])[edit['position'] - 1].group()
                assert old.casefold() != edit['text'].casefold()
    variants = list(product(*(q['editAlternatives'] for q in qs)))
    for variant in variants:
        touched = set(); counts = {}
        for edit in variant:
            point = (edit['sentence'], edit['position'], edit['operation'] == 'insert')
            assert point not in touched; touched.add(point)
            counts[edit['sentence']] = counts.get(edit['sentence'], 0) + 1
        assert max(counts.values()) <= 2
    if audit is not None:
        assert audit['word_editing'] == c
        assert audit['student_passage'] == '\n\n'.join(sentences)
        assert audit['corrected_passage_variants'] == [' '.join(apply_edits(sentences, v)) for v in variants]
        assert audit['full_edit_variant_combinations'] == len(variants)
    return True


def check(group, audit, binding, source):
    assert binding['task_mode'] == 'unhinted_word_editing'
    assert source['responses'] == binding['responses'] == audit['questions'] == 10
    assert source['grade'] == binding['level'] == group['grade']
    config = source['configuration']
    assert config['edit_operations'] == ['insert', 'delete', 'replace']
    assert config['error_locations_given'] is False
    assert config['words_per_edit'] == config['points_each'] == 1
    assert config['max_edits_per_sentence'] == 2 and config['only_first_n_edits_scored'] == 10
    assert not group.get('requiredPassageImages') and not group.get('requiredAudioAssets')
    assert audit['source_key_not_copied'] and audit['author_grammar_and_corrected_variant_review']
    return validate(group, audit)
