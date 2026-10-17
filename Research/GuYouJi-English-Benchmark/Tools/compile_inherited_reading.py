"""Keep CET complete single-passage and two-passage section contracts separate."""
import hashlib,json,re
from grade_mode_evidence import load_ref
from compile_short_dialogue_listening import ref
from compile_inherited_cloze import words
from quality_review_contract import response_markdown


def validate(d,b,s):
    assert d['grade']==b['level']==s['level'] and d['grade']in ['undergraduate','postgraduate']
    assert d['family']==b['family']=='reading_choice' and d['source_group_id']==b['source_group_id']==s['id']
    assert hashlib.sha256(json.dumps(s,sort_keys=True,ensure_ascii=False).encode()).hexdigest()==b['source_record_sha256']
    load_ref(b['source_document']);load_ref(b['authoring_specification'])
    n=b['materials'];assert n in [1,2] and len(d['passages'])==n and b['responses']==5*n and b['options_each']==4
    if n==1:
        root=json.loads(load_ref(b['source_index']).read_text());assert root['source_sha256']==b['source_document']['sha256']
        assert s['response_count']==5 and s['kind']=='single_reading_five_four_options' and s['necessary_source_pages_visually_reviewed']
    else:
        assert s['material']['passages']==2 and s['material']['questions_per_passage']==[5,5] and s['responses']==10
        assert s['source']==b['source_document'] and s['full_student_input'] and not s['is_independent_gold']
    limits=[300,350]if d['grade']=='undergraduate'else[400,450]
    for i,p in enumerate(d['passages']):
        assert limits[0]<=words(p['text'])<=limits[1],(d['id'],i,words(p['text']))
        assert len(p['questions'])==5 and [q['number']for q in p['questions']]==list(range(5*i+1,5*i+6))
        for q in p['questions']:
            assert [k for k,v in q['options']]==list('ABCD') and q['answer'] in list('ABCD')
            assert len(set(v for k,v in q['options']))==4
            assert set(q['candidate_reasons'])==set('ABCD') and all(q['candidate_reasons'].values())
            assert q['evidence'] in p['text'] and len(q['evidence'].split())>=3
    return True


def compile_author(manuscript,version='0.1'):
    d=json.loads(manuscript.read_text());bp=load_ref(d['source_bindings']);b=next(b for b in json.loads(bp.read_text())['bindings']if b['id']==d['source_binding']);s=next(s for s in json.loads(load_ref(b['source_index']).read_text())[b['collection']]if s['id']==b['source_group_id']);validate(d,b,s)
    material='\n\n'.join('### Passage '+str(i)+'\n\n'+p['text']for i,p in enumerate(d['passages'],1));tasks=[];pairs=[]
    for i,p in enumerate(d['passages'],1):
        for q in p['questions']:
            tasks.append({k:q[k]for k in ['number','options','answer']}|dict(stem=('Passage '+str(i)+' — 'if len(d['passages'])>1 else'')+q['stem'],rationale='原文依据：'+q['evidence']+'。'+'；'.join(k+'：'+q['candidate_reasons'][k]for k in 'ABCD')))
            pairs += [dict(number=q['number'],passage=i,candidate=k,text=v,is_best=k==q['answer'],reason=q['candidate_reasons'][k],support_span=q['evidence'])for k,v in q['options']]
    block=response_markdown(tasks);candidate=manuscript.with_name(d['id']+'-v'+version+'.md');ap=manuscript.with_name(d['id']+'-author-check-v'+version+'.json');assert not candidate.exists()and not ap.exists()
    candidate.write_text('# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n'+material+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+d['source_notice']+'\n')
    loads=[words(p['text'])for p in d['passages']]
    a=dict(version=version,id=d['id'],grade=d['grade'],questions=len(tasks),candidate_sha256=ref(candidate)['sha256'],source_binding=b['id'],source_bindings=ref(bp),source_group_id=s['id'],manuscript=ref(manuscript),review_response_tasks=tasks,canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),student_passage=material,inherited_cet_reading=True,subgroup_counts=[5]*len(loads),passage_word_counts=loads,choice_pair_audit=pairs,load_measure=dict(body_English_words=words(material),body_English_words_without_labels=sum(loads),material_label_English_words=len(loads),body_Han_characters=0,stem_English_words=sum(words(q['stem'])for q in tasks),options_English_words_with_repeated_bank=sum(words(v)for q in tasks for k,v in q['options']),output_response_positions=len(tasks)),source_count_increment=0,authored_student_inputs_complete=True,independent_teacher_student_commercial_production_validated=False)
    ap.write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n')
    return dict(id=d['id'],grade=d['grade'],family=d['family'],family_label='阅读单选',title=d['title'],questions=len(tasks),candidate=ref(candidate),author_check=ref(ap),source_group_ids=[s['id']],instruction=d['instruction'],source_form_notice=d['source_notice'],format_summary=str(len(loads))+'完整篇 / 每篇5题各4候选 / '+str(sum(loads))+'正文英文词 / '+('单篇完整任务，非整节'if len(loads)==1 else'整节两篇十题'))


def check(g,a,b,s):
    d=json.loads(load_ref(a['manuscript']).read_text());validate(d,b,s)
    assert a['inherited_cet_reading'] and a['subgroup_counts']==[5]*b['materials']
    assert a['passage_word_counts']==[words(p['text'])for p in d['passages']]
    assert len(a['choice_pair_audit'])==b['responses']*4
    for p in a['choice_pair_audit']:
        q=d['passages'][p['passage']-1]['questions'][(p['number']-1)%5]
        assert p['number']==q['number'] and p['reason']==q['candidate_reasons'][p['candidate']] and p['support_span']==q['evidence']
        assert p['is_best']==(q['answer']==p['candidate']) and p['reason']in g['questions'][q['number']-1]['rationale']
    return True
