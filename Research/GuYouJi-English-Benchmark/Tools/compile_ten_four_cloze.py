"""Complete P6 ten-gap four-option cloze, with source defects retained separately."""
import hashlib
import json
import re
from grade_mode_evidence import load_ref
from compile_primary6_written_groups import ref, words
from quality_review_contract import response_markdown


def validate(d,b,s):
    assert d['grade']==b['level']==s['level']=='primary6'
    assert d['family']==b['family']==s['kind']=='choice_cloze'
    assert d['source_group_id']==b['source_group_id']==s['id']
    assert s['source_full_input_verified'] is False and s['source_key_acquired'] is False
    assert s['school_exam_authentication'] is False and b['raw_exam_not_repaired'] is True
    assert s['features']==b['source_features']==dict(passages=1,responses=10,options_each=4,numbered_gaps=list(range(1,11)),shared_bank=False)
    w=json.loads(load_ref(b['source_companion']).read_text())
    assert w['source_class']=='public_tutoring_practice_not_authenticated_ordinary_exam'
    assert w['configuration']==dict(passages=1,responses=10,options_each=4,shared_bank=False)
    assert not w['native_original_downloaded'] and not w['original_school_authenticated'] and not w['raw_exam_repaired']
    assert w['key_not_gold'] and w['numbered_source_positions']==list(range(49,59))
    assert len(w['options'])==len(w['published_keys'])==10 and all(len(o)==4 for o in w['options'])
    assert re.findall(r'\((\d+)\) ____',d['passage'])==list(map(str,range(1,11)))
    assert len(d['questions'])==10 and len(d['passage'].split('\n\n'))>=3
    filled=d['passage']
    for n,q in enumerate(d['questions'],1):
        assert q['number']==n and q['stem']=='第'+str(n)+'空'
        assert [k for k,_ in q['options']]==list('ABCD') and q['answer'] in 'ABCD'
        assert len({v.casefold() for _,v in q['options']})==4
        reasons=dict(p.split('：',1)for p in re.split(r'；(?=[ABCD]：)',q['rationale']))
        assert set(reasons)==set('ABCD') and all(reasons.values())
        filled=filled.replace('('+str(n)+') ____',dict(q['options'])[q['answer']])
    assert '____'not in filled
    return filled


def compile_author(mp,version='0.2'):
    d=json.loads(mp.read_text());bp=load_ref(d['source_bindings']);b=next(v for v in json.loads(bp.read_text())['bindings']if v['id']==d['source_binding']);s=next(v for v in json.loads(load_ref(b['source_index']).read_text())['groups']if v['id']==b['source_group_id']);filled=validate(d,b,s);tasks=d['questions'];block=response_markdown(tasks)
    p=mp.parent/(d['id']+'-v'+version+'.md');ap=mp.parent/(d['id']+'-author-check-v'+version+'.json')
    text='# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n'+d['passage']+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n### 全组回填\n\n'+filled+'\n\n'+d['source_notice']+'\n'
    pairs=[]
    for q in tasks:
        reasons=dict(v.split('：',1)for v in re.split(r'；(?=[ABCD]：)',q['rationale']))
        for k,v in q['options']:
            t=d['passage']
            for other in tasks:t=t.replace('('+str(other['number'])+') ____',v if other['number']==q['number']else dict(other['options'])[other['answer']])
            pairs.append(dict(number=q['number'],candidate=k,text=v,is_best=k==q['answer'],reason=reasons[k],full_group_substitution=t))
    a=dict(version=version,id=d['id'],grade=d['grade'],questions=10,source_binding=b['id'],source_bindings=ref(bp),source_group_id=s['id'],source_companion=b['source_companion'],manuscript=ref(mp),candidate_sha256=hashlib.sha256(text.encode()).hexdigest(),canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),review_response_tasks=tasks,student_passage=d['passage'],filled_passage=filled,source_count_increment=0,ten_four_cloze=True,raw_exam_not_repaired=True,choice_pair_audit=pairs,load_measure=dict(body_English_words=words(d['passage']),stem_English_words=0,options_English_words_with_repeated_bank=sum(words(v)for q in tasks for _,v in q['options']),output_response_positions=10),authored_student_inputs_complete=True,independent_teacher_student_commercial_production_validated=False)
    for path,t in [(p,text),(ap,json.dumps(a,ensure_ascii=False,indent=2)+'\n')]:
        if path.exists():assert path.read_text()==t
        else:path.write_text(t)
    return dict(id=d['id'],grade=d['grade'],family=d['family'],family_label='单选完形',title=d['title'],questions=10,candidate=ref(p),author_check=ref(ap),source_group_ids=[s['id']],instruction=d['instruction'],source_form_notice=d['source_notice'],format_summary='1完整新故事 / 10空各4独立候选 / 共10回应 / 原卷缺文和练习结构旁证分列')


def check(g,a,b,s):
    d=json.loads(load_ref(a['manuscript']).read_text());filled=validate(d,b,s)
    selected=json.loads(load_ref(s['selected_native']).read_text());native=json.loads(load_ref(selected['native_text']).read_text())
    assert selected['configuration']==s['features'] and selected['source_full_inputs_verified'] is False and selected['source']==s['source']
    for span in selected['spans']:
        t=native['pages'][span['physical_page']-1]['text'][span['start']:span['end']];assert t==span['text']and hashlib.sha256(t.encode()).hexdigest()==span['sha256']
    assert a['ten_four_cloze']and a['raw_exam_not_repaired']and a['source_companion']==b['source_companion']
    assert a['filled_passage']==filled and a['student_passage']==d['passage']and g['questions']==d['questions']
    assert a['canonical_response_block_sha256']==hashlib.sha256(response_markdown(d['questions']).encode()).hexdigest()
    expected=[]
    for q in d['questions']:
        reasons=dict(p.split('：',1)for p in re.split(r'；(?=[ABCD]：)',q['rationale']))
        for k,v in q['options']:
            t=d['passage']
            for other in d['questions']:t=t.replace('('+str(other['number'])+') ____',v if other['number']==q['number']else dict(other['options'])[other['answer']])
            expected.append(dict(number=q['number'],candidate=k,text=v,is_best=k==q['answer'],reason=reasons[k],full_group_substitution=t))
    assert a['choice_pair_audit']==expected and len(expected)==40
    return True
