"""Full four-question reading and two choose-two prompts with separate banks."""
import hashlib,json
from grade_mode_evidence import load_ref
from quality_review_contract import response_markdown
from compile_short_dialogue_listening import ref
from render_original_listening import words

def validate(d,s):
    assert d['grade']==s['level']=='advanced' and d['family']==s['kind'] and d['source_group_id']==s['id']
    assert d['fictional_illustrative_case'] and d['passage'] and s['responses']==4
    multi=d['family']=='reading_multiselect'
    if multi:
        assert len(d['prompts'])==2 and [len(p['candidates'])for p in d['prompts']]==s['features']['candidates_per_prompt']==[7,6]
        assert s['features']['response_positions']==[[1,2],[3,4]] and s['features']['order_within_prompt']=='either'
        assert '同一提示内顺序任意' in d['instruction'] and '重复选择不重复计入' in d['instruction']
        records=d['prompts']
    else:
        assert len(d['items'])==4 and s['features']['options_each']==4
        records=d['items']
    for n,row in enumerate(records):
        labels=list('ABCDEFG')[:7-n]if multi else list('ABCD')
        assert [k for k,_ in row['candidates']]==labels and len({v for k,v in row['candidates']})==len(labels)
        assert set(row['candidate_reasons'])==set(labels) and all(row['candidate_reasons'].values())
        keys=row['correct']if multi else[row['answer']]
        assert len(keys)==(2 if multi else 1) and len(set(keys))==len(keys) and all(k in labels for k in keys)
        assert set(row['evidence'])==set(keys) and all(v in d['passage']for v in row['evidence'].values())
    return True

def compile_author(manuscript,version="0.1"):
    d=json.loads(manuscript.read_text());bp=load_ref(d['source_bindings']);b=next(b for b in json.loads(bp.read_text())['bindings']if b['id']==d['source_binding']);s=next(s for s in json.loads(load_ref(b['source_index']).read_text())['groups']if s['id']==d['source_group_id']);validate(d,s);multi=d['family']=='reading_multiselect';qs=[];pairs=[];body=d['passage'];records=d['prompts']if multi else d['items']
    for n,row in enumerate(records):
        why='；'.join(k+'：'+row['candidate_reasons'][k]for k,v in row['candidates'])
        if multi:
            positions=[2*n+1,2*n+2];contract=dict(version=1,id=d['id']+'-prompt'+str(n+1),positions=positions,correct=row['correct'],order='either',distinct=True,localMatchingRule='distinct_correct_options_once')
            body+='\n\n### 提示'+str(n+1)+'（作答位'+str(positions[0])+'、'+str(positions[1])+'）\n\n'+row['stem']+'\n\n'+'\n\n'.join(k+'. '+v for k,v in row['candidates'])
            for i,num in enumerate(positions):qs.append(dict(number=num,stem='提示'+str(n+1)+'，作答位'+str(num)+'：'+row['stem'],options=row['candidates'],answer=row['correct'][i],selectionSet=contract,rationale='本提示两项顺序任意，重复同一字母不重复计入。'+why))
        else:qs.append(dict(number=n+1,stem=row['stem'],options=row['candidates'],answer=row['answer'],rationale=why))
        pairs += [dict(prompt=n+1,candidate=k,is_correct=k in(row['correct']if multi else[row['answer']]),reason=row['candidate_reasons'][k])for k,v in row['candidates']]
    block=response_markdown(qs);p=manuscript.parent/(d['id']+'-v'+version+'.md');ap=manuscript.parent/(d['id']+'-author-check-v'+version+'.json');assert not p.exists()and not ap.exists();p.write_text('# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n'+body+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+d['source_notice']+'\n')
    a=dict(version=version,id=d['id'],grade='advanced',questions=4,candidate_sha256=ref(p)['sha256'],source_binding=b['id'],source_bindings=ref(bp),source_group_id=s['id'],manuscript=ref(manuscript),review_response_tasks=qs,canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),student_passage=body,academic_reading_choice_sets=True,academic_multi_response_multi_select=multi,unique_prompt_candidate_audit=pairs,source_partial_credit_rule_verified=False if multi else None,source_count_increment=0,authored_student_inputs_complete=True,load_measure=dict(body_English_words=words(body),passage_English_words=words(d['passage']),stem_English_words=sum(words(q['stem'])for q in qs),options_English_words_with_repeated_bank=sum(words(v)for q in qs for k,v in q['options']),options_English_words_unique_prompt_banks=sum(words(v)for row in records for k,v in row['candidates']),output_response_positions=4),source_level_equivalence_established=False,independent_teacher_student_commercial_production_validated=False);ap.write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n')
    m=dict(id=d['id'],grade='advanced',family=d['family'],family_label='阅读多选'if multi else'阅读单选',title=d['title'],questions=4,candidate=ref(p),author_check=ref(ap),source_group_ids=[s['id']],instruction=d['instruction'],source_form_notice=d['source_notice'],format_summary='1材料 / 2提示各选2 / 7与6项独立候选 / 4回应 / 各提示内无序不重复'if multi else'1材料 / 4题 / 每题4独立候选 / 无示例')
    if multi:m['use_select_controls']=True
    return m

def check(g,a,b,s):
    d=json.loads(load_ref(a['manuscript']).read_text());validate(d,s);multi=d['family']=='reading_multiselect'
    assert g['questions']==a['review_response_tasks'] and len(g['questions'])==4
    texts=[load_ref(r).read_text()for r in s['source_pages']]
    if multi:
        assert g['fixedSharedBank'] and s['reference_keys']==[['B','G'],['C','E']]
        assert texts[2].count('IN EITHER ORDER')==2 and not s['features']['source_partial_credit_verified']
        for n,row in enumerate(d['prompts']):
            for q in g['questions'][n*2:n*2+2]:assert q['selectionSet']['correct']==row['correct'] and q['options']==row['candidates']
    else:assert s['reference_keys']==list('ACDB') and len(d['items'])==4
    assert len(a['unique_prompt_candidate_audit'])==(13 if multi else 16)
    return True
