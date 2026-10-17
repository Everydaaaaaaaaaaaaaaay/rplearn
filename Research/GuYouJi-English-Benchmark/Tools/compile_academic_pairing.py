"""Main-idea headings with a solved section; whole-sentence ending matches."""
import hashlib,json
from grade_mode_evidence import load_ref
from quality_review_contract import response_markdown
from compile_short_dialogue_listening import ref
from render_original_listening import words

def validate(d,s):
    assert d['grade']==s['level']=='advanced' and d['family']==s['kind'] and d['source_group_id']==s['id']
    headings=d['family']=='paragraph_heading_matching';count=4 if headings else 3;labels=['i','ii','iii','iv','v','vi','vii','viii']if headings else list('ABCDEF')
    assert [k for k,_ in d['candidates']]==s['features']['labels']==labels and len({v for k,v in d['candidates']})==len(labels)
    assert len(d['items'])==s['responses']==count and d['fictional_illustrative_case']
    body='\n\n'.join(d['sections'].values())if headings else d['passage']
    if headings:
        assert list(d['sections'])==list('ABCDE') and d['example']==dict(section='B',answer='i')==s['features']['example']
        assert d['example_evidence']in d['sections']['B'] and d['example_reason']
        assert [i['section']for i in d['items']]==list('ACDE')
        assert len({i['answer']for i in d['items']})==4 and all(i['answer']!='i'for i in d['items'])
        assert '每个标题最多使用一次' in d['instruction'] and 'Section B → i'in d['instruction']
        assert s['features']['reuse_rule']=='no_heading_more_than_once_on_official_current_format'
    else:
        assert d['source_reuse_rule']==s['features']['reuse_rule']=='not_explicit_in_sample_or_current_format'
        assert '不额外规定每个句尾最多一次' in d['instruction'] and '每个句尾只能使用一次'not in d['instruction']
        assert [i['information_order']for i in d['items']]==[1,2,3]
        assert all(i['stem'].endswith('because')for i in d['items'])
    for i in d['items']:
        assert i['answer']in labels and i['evidence_quote']in(body if not headings else d['sections'][i['section']])
        assert set(i['candidate_reasons'])==set(labels) and all(i['candidate_reasons'].values())
        if not headings:assert i['completed_sentence']==i['stem']+' '+dict(d['candidates'])[i['answer']]
    return True

def compile_author(manuscript):
    d=json.loads(manuscript.read_text());bp=load_ref(d['source_bindings']);b=next(b for b in json.loads(bp.read_text())['bindings']if b['id']==d['source_binding']);s=next(s for s in json.loads(load_ref(b['source_index']).read_text())['groups']if s['id']==d['source_group_id']);validate(d,s);headings=d['family']=='paragraph_heading_matching'
    body='\n\n'.join('### Section '+k+'\n\n'+v for k,v in d['sections'].items())if headings else d['passage'];bank='\n\n### '+('List of Headings'if headings else'Sentence Endings')+'\n\n'+'\n\n'.join(k+'. '+v for k,v in d['candidates']);body+=bank
    qs=[dict(number=n,stem=('Section '+i['section'])if headings else i['stem'],options=d['candidates'],answer=i['answer'],rationale='；'.join(k+'：'+i['candidate_reasons'][k]for k,v in d['candidates']))for n,i in enumerate(d['items'],1)];block=response_markdown(qs);p=manuscript.parent/(d['id']+'-v0.1.md');ap=manuscript.parent/(d['id']+'-author-check-v0.1.json');teacher=d['source_notice']+('\n\n已解示例：'+d['example_reason']if headings else'');candidate_text='# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n'+body+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+teacher+'\n'
    if p.exists():assert p.read_text()==candidate_text
    else:p.write_text(candidate_text)
    a=dict(version='0.1',id=d['id'],grade='advanced',questions=len(qs),candidate_sha256=ref(p)['sha256'],source_binding=b['id'],source_bindings=ref(bp),source_group_id=s['id'],manuscript=ref(manuscript),review_response_tasks=qs,canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),student_passage=body,academic_shared_pairing=True,full_shared_bank=d['candidates'],pair_judgements=[dict(number=n,candidate=k,is_best=k==i['answer'],reason=i['candidate_reasons'][k])for n,i in enumerate(d['items'],1)for k,v in d['candidates']],example=d.get('example'),example_count_not_response=1 if headings else 0,complete_sentences=[i['completed_sentence']for i in d['items']]if not headings else[],source_reuse_rule=s['features']['reuse_rule'],source_count_increment=0,authored_student_inputs_complete=True,load_measure=dict(body_English_words=words(body),passage_English_words=words(' '.join(d['sections'].values())if headings else d['passage']),stem_English_words=sum(words(q['stem'])for q in qs),options_English_words_with_repeated_bank=len(qs)*sum(words(v)for k,v in d['candidates']),options_English_words_unique_bank=sum(words(v)for k,v in d['candidates']),output_response_positions=len(qs)),source_level_equivalence_established=False,independent_teacher_student_commercial_production_validated=False);audit_text=json.dumps(a,ensure_ascii=False,indent=2)+'\n'
    if ap.exists():assert ap.read_text()==audit_text
    else:ap.write_text(audit_text)
    return dict(id=d['id'],grade='advanced',family=d['family'],family_label='段落标题配对'if headings else'句首句尾衔接配对',title=d['title'],questions=len(qs),candidate=ref(p),author_check=ref(ap),source_group_ids=[s['id']],instruction=d['instruction'],source_form_notice=d['source_notice'],use_select_controls=True,format_summary='1全文 / A—E五节 / B→i已解示例 / A、C、D、E四回应 / i—viii八标题 / 不复用'if headings else'1全文 / 3句首 / 6共享句尾 / 依文次序 / 源未印复用限制')

def check(g,a,b,s):
    d=json.loads(load_ref(a['manuscript']).read_text());validate(d,s)
    assert g['fixedSharedBank'] and g['questions']==a['review_response_tasks'] and all(q['options']==d['candidates']for q in g['questions'])
    assert len(a['pair_judgements'])==b['responses']*b['options_each']
    texts=[load_ref(r).read_text()for r in s['source_pages']]
    if d['family']=='paragraph_heading_matching':
        assert s['reference_keys']==['iii','viii','v','vii'] and 'Section B i'in texts[0]
        assert 'No heading may be used more than once.'in load_ref(s['features']['format_rule_reference']).read_text()
        assert a['example_count_not_response']==1 and len(g['questions'])==4
    else:
        assert s['reference_keys']==list('BDF') and all('1 B'in t or '2 D'in t or '3 F'in t for t in texts[-1:])
        assert a['complete_sentences']==[i['completed_sentence']for i in d['items']]
    return True
