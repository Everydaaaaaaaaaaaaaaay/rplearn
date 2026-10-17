"""Four feature-origin matches against one explicitly reusable five-group bank."""
import hashlib,json
from grade_mode_evidence import load_ref
from quality_review_contract import response_markdown
from compile_short_dialogue_listening import ref
from render_original_listening import words

def validate(d,s):
    assert d['grade']==s['level']=='advanced' and d['family']==s['kind']=='matching_features'
    assert d['source_group_id']==s['id']
    assert s['features']==dict(materials=1,responses=4,shared_candidates=5,labels=list('ABCDE'),reuse_rule='explicit_more_than_once',matching_relation='first_invented_or_used_by')
    assert [k for k,v in d['candidates']]==list('ABCDE') and len({v for k,v in d['candidates']})==5
    assert len(d['items'])==4 and d['passage'] and d['fictional_illustrative_case']
    assert '可重复使用' in d['instruction'] and '只能使用一次'not in d['instruction']
    assert set(d['candidate_roles'])==set('ABCDE')
    for item in d['items']:
        assert item['answer']in'ABCDE' and item['evidence_quote']in d['passage'] and item['evidence_quote']
        assert set(item['candidate_reasons'])==set('ABCDE') and all(item['candidate_reasons'].values())
    return True

def check(g,a,b,s):
    texts=[load_ref(r).read_text()for r in s['source_pages']]
    assert 'NB You may use any letter more than once.' in texts[1]
    assert all(line in texts[2]for line in ['7 A','8 A','9 B','10 E']) and s['reference_keys']==list('AABE')
    assert s['source_full_input_verified'] and not s['source_original_key_is_gold']
    d=json.loads(load_ref(a['manuscript']).read_text());validate(d,s)
    assert g['fixedSharedBank'] and a['shared_candidates']==d['candidates']
    assert len(g['questions'])==b['responses']==4 and all(q['options']==d['candidates']for q in g['questions'])
    assert len(a['choice_pair_audit'])==20 and a['source_reuse_rule']=='explicit_more_than_once'
    assert not a['max_once_added'] and a['authored_student_inputs_complete']
    for q,item in zip(g['questions'],d['items']):
        assert q['answer']==item['answer'] and q['stem']==item['feature']
        assert all(reason in q['rationale']for reason in item['candidate_reasons'].values())
    return True

def compile_author(manuscript):
    d=json.loads(manuscript.read_text());bp=load_ref(d['source_bindings']);b=next(b for b in json.loads(bp.read_text())['bindings']if b['id']==d['source_binding']);s=next(s for s in json.loads(load_ref(b['source_index']).read_text())['groups']if s['id']==b['source_group_id']);validate(d,s)
    tasks=[];pairs=[]
    for n,item in enumerate(d['items'],1):
        why='；'.join(k+'：'+item['candidate_reasons'][k]for k in'ABCDE');tasks.append(dict(number=n,stem=item['feature'],options=d['candidates'],answer=item['answer'],rationale=why))
        for k,v in d['candidates']:pairs.append(dict(number=n,candidate=k,is_best=k==item['answer'],reason=item['candidate_reasons'][k],first_origin_evidence=item['evidence_quote']))
    bank='\n\n### 共享群体候选\n\n'+'\n\n'.join(k+'. '+v for k,v in d['candidates']);block=response_markdown(tasks);p=manuscript.parent/(d['id']+'-v0.1.md');ap=manuscript.parent/(d['id']+'-author-check-v0.1.json');assert not p.exists()and not ap.exists();p.write_text('# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n'+d['passage']+bank+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+d['source_notice']+'\n')
    a=dict(version='0.1',id=d['id'],grade='advanced',questions=4,candidate_sha256=ref(p)['sha256'],source_binding=b['id'],source_bindings=ref(bp),source_group_id=s['id'],manuscript=ref(manuscript),review_response_tasks=tasks,canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),student_passage=d['passage'],academic_matching_features=True,shared_candidates=d['candidates'],choice_pair_audit=pairs,source_reuse_rule='explicit_more_than_once',max_once_added=False,source_count_increment=0,authored_student_inputs_complete=True,load_measure=dict(body_English_words=words(d['passage']),stem_English_words=sum(words(q['stem'])for q in tasks),options_English_words_with_repeated_bank=4*sum(words(v)for k,v in d['candidates']),options_English_words_unique_bank=sum(words(v)for k,v in d['candidates']),output_response_positions=4),source_level_equivalence_established=False,independent_teacher_student_commercial_production_validated=False);ap.write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n')
    return dict(id=d['id'],grade='advanced',family=d['family'],family_label='特征归类配对',title=d['title'],questions=4,candidate=ref(p),author_check=ref(ap),source_group_ids=[s['id']],instruction=d['instruction'],source_form_notice=d['source_notice'],use_select_controls=True,format_summary='1完整材料 / 4项目 / 5共享群体 / 最初发明或使用关系 / 字母可重复')
