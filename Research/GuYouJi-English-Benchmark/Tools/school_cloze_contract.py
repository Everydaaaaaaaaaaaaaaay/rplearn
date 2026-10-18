"""Bind a complete school cloze configuration; counts alone are not difficulty proof."""
import hashlib
import json
import re
from grade_mode_evidence import load_ref


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def validate(draft, binding, source):
    assert draft['grade'] == binding['level'] == source['level']
    assert draft['family'] == binding['family'] == source['kind'] == 'choice_cloze'
    assert draft['source_group_id'] == binding['source_group_id'] == source['id']
    assert binding['source_record_sha256'] == digest(json.dumps(source, sort_keys=True, ensure_ascii=False))
    assert source['source_full_inputs_verified'] and not source['source_key_is_gold']
    assert source['source_count_increment'] == 0 and binding['new_source_count'] == 0
    count = source['responses']; options = source['options_each']
    assert binding['responses'] == count and binding['options_each'] == options
    config = source['configuration']; sections = draft['sections']
    assert config['materials'] == len(sections) == len(config['subgroups'])
    assert sum(p['responses'] for p in config['subgroups']) == count
    assert config['each_gap_independent'] and not config['shared_bank']
    assert [len(re.findall(r'\((\d+)\) ____',s['passage'])) for s in sections] == [p['responses'] for p in config['subgroups']]
    assert [s['label'] for s in sections] == [p['label'] for p in config['subgroups']]
    for span in source['source_spans']:
        raw = load_ref(span['source']).read_text()
        selected = raw[span['start_offset']:span['end_offset']]
        assert digest(selected) == span['sha256']
        nums = re.findall(r'(?m)^(\d+)\.?\s+A\.',selected)
        assert list(map(int,nums)) == span['question_numbers']
        for line in re.findall(r'(?m)^\d+\.?\s+A\..*$',selected):
            assert re.findall(r'(?:^|\s)([A-D])\.',line) == list('ABCD'[:options])
        assert span['instruction'] in raw and span['instruction_sha256'] == digest(span['instruction'])
    passage = '\n\n'.join(s['passage'] for s in sections)
    assert re.findall(r'\((\d+)\) ____',passage) == list(map(str,range(1,count+1)))
    qs = draft['questions']; assert len(qs) == count
    assert [q['number'] for q in qs] == list(range(1,count+1))
    filled = passage
    for q in qs:
        labels = list('ABCD'[:options]); assert [p[0] for p in q['options']] == labels
        assert q['answer'] in labels and len({p[1].casefold().strip() for p in q['options']}) == options
        reasons = dict(part.split('：',1) for part in q['rationale'].split('；'))
        assert set(reasons) == set(labels) and all(reasons.values())
        assert all(v.strip() for _,v in q['options'])
        filled = filled.replace('('+str(q['number'])+') ____',dict(q['options'])[q['answer']])
    assert '____' not in filled
    return passage, filled


def check(group, audit, binding, source):
    draft = json.loads(load_ref(audit['manuscript']).read_text())
    passage, filled = validate(draft,binding,source)
    assert audit['school_complete_cloze'] and audit['student_passage'] == passage and audit['filled_passage'] == filled
    assert group['questions'] == draft['questions'] and group['grade'] == draft['grade']
    assert len(audit['choice_pair_audit']) == source['responses'] * source['options_each']
    pairs = {(p['number'],p['candidate']):p for p in audit['choice_pair_audit']}
    assert len(pairs) == len(audit['choice_pair_audit'])
    for q in draft['questions']:
        reasons = dict(part.split('：',1) for part in q['rationale'].split('；'))
        for label,value in q['options']:
            p = pairs[(q['number'],label)]; text = passage
            for other in draft['questions']:
                text = text.replace('('+str(other['number'])+') ____',value if other['number']==q['number'] else dict(other['options'])[other['answer']])
            assert p['text']==value and p['full_group_substitution']==text and p['reason']==reasons[label]
            assert p['is_best'] == (label==q['answer'])
    return True
