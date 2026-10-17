"""Source-bound five-gap shared word/phrase/sentence banks, without inferred once rules."""
import hashlib,json,re
from grade_mode_evidence import load_ref
from compile_short_dialogue_listening import ref
from quality_review_contract import response_markdown
from compile_inherited_cloze import words


def validate(d,b,s):
    assert d['grade']==b['level']==s['level']=='primary5'
    assert d['family']==b['family'] and d['family'] in ['shared_bank','dialogue_matching']
    assert d['source_group_id']==b['source_group_id']==s['id']
    assert hashlib.sha256(json.dumps(s,ensure_ascii=False,sort_keys=True).encode()).hexdigest()==b['source_record_sha256']
    view=next(v for v in json.loads(load_ref(b['source_view']).read_text())['views']if v['id']==s['id'])
    assert view['responses']==b['responses']==s['responses']==5 and view['source_index']==b['source_index']
    assert view['reuse_rule']=='not_explicit' and b['reuse_rule']=='not_explicit'
    count=b['options_each']; assert count in [5,6] and len(view['original_shared_candidates'])==count
    if s.get('options_each'):assert s['options_each']==count and s['input_complete']
    else:assert s['candidates']['shared_entries']==count and s['full_student_input']
    for evidence in view['references']:load_ref(evidence)
    if view.get('HTML_selected_text'):
        from bs4 import BeautifulSoup
        visible=BeautifulSoup(load_ref(s['source']).read_text(),'html.parser').get_text(' ',strip=True)
        assert view['HTML_selected_text'] in visible
    assert [k for k,v in d['shared_candidates']]==list('ABCDEF')[:count]
    assert len(set(v for k,v in d['shared_candidates']))==count
    assert re.findall(r'\((\d+)\) ____',d['passage'])==list('12345')
    assert len(d['slots'])==5
    for slot in d['slots']:
        assert slot['answer'] in dict(d['shared_candidates']) and slot['rule']
    if count==6:
        assert '有一项多余' in d['instruction']
        assert len(set(slot['answer'] for slot in d['slots']))==5
    if b['candidate_unit']=='词':
        assert all(re.fullmatch('[A-Za-z]+',v) for k,v in d['shared_candidates'])
    assert set(d['candidate_roles'])==set(dict(d['shared_candidates']))
    assert '每项只能' not in d['instruction'] and '每项限用' not in d['instruction']
    return view


def compile_author(manuscript, version='0.1'):
    d=json.loads(manuscript.read_text());bp=load_ref(d['source_bindings']);b=next(b for b in json.loads(bp.read_text())['bindings']if b['id']==d['source_binding']);s=next(s for s in json.loads(load_ref(b['source_index']).read_text())[b['collection']]if s['id']==b['source_group_id']);validate(d,b,s)
    tasks=[];pairs=[];filled=d['passage']
    for n,slot in enumerate(d['slots'],1):filled=filled.replace('('+str(n)+') ____',dict(d['shared_candidates'])[slot['answer']])
    for n,slot in enumerate(d['slots'],1):
        reasons={k:('本项符合：'if k==slot['answer']else'本项不合：')+slot['rule']+'。'+v+'表示'+d['candidate_roles'][k]+'。'for k,v in d['shared_candidates']}
        tasks.append(dict(number=n,stem='第'+str(n)+'空',options=d['shared_candidates'],answer=slot['answer'],rationale='；'.join(k+'：'+reasons[k]for k,v in d['shared_candidates'])))
        for k,v in d['shared_candidates']:
            text=d['passage']
            for i,other in enumerate(d['slots'],1):text=text.replace('('+str(i)+') ____',v if i==n else dict(d['shared_candidates'])[other['answer']])
            pairs.append(dict(number=n,candidate=k,is_best=k==slot['answer'],reason=reasons[k],full_group_substitution=text))
    bank='\n\n### 共享候选\n\n'+'\n\n'.join(k+'. '+v for k,v in d['shared_candidates']);body=d['passage']+bank;block=response_markdown(tasks)
    candidate=manuscript.with_name(d['id']+'-v'+version+'.md');ap=manuscript.with_name(d['id']+'-author-check-v'+version+'.json');assert not candidate.exists()and not ap.exists()
    candidate.write_text('# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n'+body+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+d['source_notice']+'\n\n### 全组回填\n\n'+filled+'\n')
    a=dict(version=version,id=d['id'],grade=d['grade'],questions=5,candidate_sha256=ref(candidate)['sha256'],source_binding=b['id'],source_bindings=ref(bp),source_group_id=s['id'],manuscript=ref(manuscript),review_response_tasks=tasks,canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),student_passage=d['passage'],filled_passage=filled,inherited_shared_five=True,shared_candidates=d['shared_candidates'],choice_pair_audit=pairs,load_measure=dict(body_English_words=words(d['passage']),body_Han_characters=len(re.findall('[\u3400-\u9fff]',d['passage'])),stem_English_words=0,options_English_words_with_repeated_bank=sum(words(v)for k,v in d['shared_candidates'])*5,options_English_words_unique_bank=sum(words(v)for k,v in d['shared_candidates']),output_response_positions=5),body_load_text=d['passage'],source_count_increment=0,authored_student_inputs_complete=True,independent_teacher_student_commercial_production_validated=False)
    ap.write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n')
    return dict(id=d['id'],grade='primary5',family=d['family'],family_label='共享词库填空'if d['family']=='shared_bank'else'共享候选对话补全',title=d['title'],questions=5,candidate=ref(candidate),author_check=ref(ap),source_group_ids=[s['id']],instruction=d['instruction'],source_form_notice=d['source_notice'],use_select_controls=True,format_summary='1完整'+('对话'if d['family']=='dialogue_matching'else'语篇')+' / 5空 / '+str(b['options_each'])+'共享'+b['candidate_unit']+' / 原形选择 / 源未明确每项一次')


def check(g,a,b,s):
    d=json.loads(load_ref(a['manuscript']).read_text());validate(d,b,s)
    assert a['inherited_shared_five'] and g['fixedSharedBank']
    assert a['shared_candidates']==d['shared_candidates'] and len(a['choice_pair_audit'])==5*b['options_each']
    assert all(q['options']==d['shared_candidates'] and q['answer']==d['slots'][i]['answer']for i,q in enumerate(g['questions']))
    filled=d['passage']
    for n,slot in enumerate(d['slots'],1):filled=filled.replace('('+str(n)+') ____',dict(d['shared_candidates'])[slot['answer']])
    assert a['filled_passage']==filled and '____'not in filled
    for p in a['choice_pair_audit']:
        text=d['passage']
        for n,slot in enumerate(d['slots'],1):text=text.replace('('+str(n)+') ____',dict(d['shared_candidates'])[p['candidate']if n==p['number']else slot['answer']])
        assert p['full_group_substitution']==text and p['is_best']==(d['slots'][p['number']-1]['answer']==p['candidate'])
        assert p['reason']in g['questions'][p['number']-1]['rationale']
    return True
