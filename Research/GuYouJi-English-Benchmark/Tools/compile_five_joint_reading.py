"""Five four-choice reading responses; item four joins two printed slots.

The damaged exam export supplies the observed task shape. A separately named
reader witness supplies an intact version of the story family, without replacing
the export or authenticating its administration/key. Originals use new stories.
"""
import hashlib
import json
from grade_mode_evidence import load_ref
from compile_primary6_written_groups import ref, words
from quality_review_contract import response_markdown


def validate(d,b,s):
    assert d['grade']==b['level']==s['level']=='primary6'
    assert d['family']==b['family']==s['kind']=='reading_choice'
    assert d['source_group_id']==b['source_group_id']==s['id']
    assert s['source_full_input_verified'] is False and s['source_key_acquired'] is False
    assert s['school_exam_authentication'] is False and b['raw_exam_not_repaired'] is True
    assert s['features']==b['source_features']==dict(passages=1,responses=5,options_each=4,
        visible_blank_slots_each=[1,0,1,2,0],joint_choice_positions=[4],necessary_media=False)
    witness=json.loads(load_ref(b['source_companion']).read_text())
    assert witness['access_mode']=='public_web_reader_cached_representation'
    assert witness['native_original_downloaded'] is False and witness['source_exam_not_repaired'] is True
    assert witness['China_primary2_mapping'] is False and witness['ordinary_paper_increment']==0
    assert len(witness['paragraphs'])==4 and all(witness['paragraphs'])
    assert 'play by candlelight next week' in witness['paragraphs'][3]
    assert len(d['paragraphs'])==4 and all(d['paragraphs']) and len(d['items'])==5
    for n,row in enumerate(d['items']):
        assert row['stem'].count('____')==[1,0,1,2,0][n]
        assert len(row['options'])==len(set(v.casefold() for v in row['options']))==4
        assert len(row['grounds'])==4 and all(row['grounds']) and row['key'] in 'ABCD'
        if n==3:assert all(len(v.split(' / '))==2 for v in row['options'])
    return True


def compile_author(manuscript,version='0.1'):
    d=json.loads(manuscript.read_text());bp=load_ref(d['source_bindings'])
    b=next(v for v in json.loads(bp.read_text())['bindings']if v['id']==d['source_binding'])
    s=next(v for v in json.loads(load_ref(b['source_index']).read_text())['groups']if v['id']==b['source_group_id'])
    validate(d,b,s)
    tasks=[dict(number=n,stem=r['stem'],options=[list(p)for p in zip('ABCD',r['options'])],answer=r['key'],
        rationale='；'.join(k+'：'+v for k,v in zip('ABCD',r['grounds'])))for n,r in enumerate(d['items'],1)]
    passage='\n\n'.join(d['paragraphs']);block=response_markdown(tasks)
    p=manuscript.parent/(d['id']+'-v'+version+'.md');ap=manuscript.parent/(d['id']+'-author-check-v'+version+'.json')
    teacher='\n\n'.join('### '+str(q['number'])+'：'+q['answer']+'\n\n'+q['rationale']for q in tasks)
    text='# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n'+passage+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+teacher+'\n\n'+d['source_notice']+'\n'
    if p.exists():assert p.read_text()==text
    else:p.write_text(text)
    a=dict(version=version,id=d['id'],grade=d['grade'],questions=5,source_binding=b['id'],source_bindings=ref(bp),
        source_group_id=s['id'],source_companion=b['source_companion'],manuscript=ref(manuscript),candidate_sha256=ref(p)['sha256'],
        five_joint_reading=True,raw_exam_not_repaired=True,reader_witness_not_school_administration=True,
        canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),review_response_tasks=tasks,
        student_passage=passage,student_paragraphs=d['paragraphs'],joint_decision_positions=[4],visible_blank_slots_each=[1,0,1,2,0],
        candidate_reason_rows=[dict(number=n,key=r['key'],grounds=dict(zip('ABCD',r['grounds'])))for n,r in enumerate(d['items'],1)],
        source_count_increment=0,authored_student_inputs_complete=True,independent_teacher_student_commercial_production_validated=False,
        load_measure=dict(body_English_words=words(passage),stem_English_words=sum(words(q['stem'])for q in tasks),
            options_English_words_with_repeated_bank=sum(words(v)for q in tasks for _,v in q['options']),output_response_positions=5,
            visible_blank_slots=4,joint_choice_response_positions=1))
    text=json.dumps(a,ensure_ascii=False,indent=2)+'\n'
    if ap.exists():assert ap.read_text()==text
    else:ap.write_text(text)
    return dict(id=d['id'],grade='primary6',family='reading_choice',family_label='阅读单选',title=d['title'],questions=5,
        candidate=ref(p),author_check=ref(ap),source_group_ids=[s['id']],instruction=d['instruction'],source_form_notice=d['source_notice'],
        format_summary='1完整新故事 / 5题各4选 / 第4题两空联选一个组合 / 共5回应 / 原卷缺文与同文读者版本分列')


def check(g,a,b,s):
    d=json.loads(load_ref(a['manuscript']).read_text());validate(d,b,s)
    selected=json.loads(load_ref(s['selected_native']).read_text());native=json.loads(load_ref(selected['native_text']).read_text())
    assert selected['configuration']==s['features'] and selected['source_full_inputs_verified'] is False
    assert selected['source']==s['source']
    for span in selected['spans']:
        block=native['pages'][span['physical_page']-1]['text'][span['start']:span['end']]
        assert block==span['text'] and hashlib.sha256(block.encode()).hexdigest()==span['sha256']
    assert a['five_joint_reading'] and a['raw_exam_not_repaired'] and a['source_companion']==b['source_companion']
    assert b['options_each']==4 and b['responses']==len(g['questions'])==5
    assert a['student_passage']=='\n\n'.join(d['paragraphs']) and a['student_paragraphs']==d['paragraphs']
    assert a['joint_decision_positions']==[4] and a['visible_blank_slots_each']==[1,0,1,2,0]
    for q,r,reason in zip(g['questions'],d['items'],a['candidate_reason_rows']):
        assert q['stem']==r['stem'] and q['answer']==r['key'] and q['options']==[list(p)for p in zip('ABCD',r['options'])]
        assert q['rationale']=='；'.join(k+'：'+v for k,v in zip('ABCD',r['grounds']))
        assert reason==dict(number=q['number'],key=r['key'],grounds=dict(zip('ABCD',r['grounds'])))
    return True
