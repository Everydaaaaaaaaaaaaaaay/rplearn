"""Five complete sentence transformations, keeping ten separately scored slots."""
import hashlib,json,re
from itertools import product
from grade_mode_evidence import load_ref
from quality_review_contract import response_markdown
from compile_short_dialogue_listening import ref
from render_original_listening import words

OPERATIONS=['combine_both_and','why_not_to_what_how_about','not_same_to_different_from','underlined_possessor_question','firstperson_be_to_secondperson_question']

def validate(draft,source):
    assert draft['source_group_id']==source['id'] and draft['grade']==source['level']==7
    assert draft['family']=='sentence_transformation' and len(draft['sentences'])==5
    assert source['features']==dict(sentence_tasks=5,slots_each=2,response_positions=10,operations=OPERATIONS,points_each_slot=0.5,section_points=5,source_max_words_per_blank=None)
    assert [s['operation']for s in draft['sentences']]==OPERATIONS
    pairs=[[['Both'],['and']],[['What','How'],['about']],[['different'],['from','to','than']],[['Whose'],['are']],[['Are'],['you']]]
    usage=load_ref(draft['different_usage_evidence']).read_text()
    assert 'oxfordlearnersdictionaries.com/us/definition/english/different' in usage
    assert all(term in usage for term in ['different from somebody/something','different to somebody/something','different than somebody/something'])
    for i,(row,pair)in enumerate(zip(draft['sentences'],pairs)):
        assert row['original'] and row['direction'] and row['rationale']
        assert re.findall(r'\((\d+)\) ____',row['target'])==[str(2*i+1),str(2*i+2)]
        assert row['accepted']==pair
        if i==3:assert row['marked_target'] and '**'+row['marked_target']+'**' in row['original']
        else:assert not row.get('marked_target')
    return True

def check(group,audit,binding,source):
    sel=json.loads(load_ref(source['selected_native']).read_text());raw=load_ref(sel['source']).read_text()
    for s in sel['spans']:assert hashlib.sha256(raw[s['start']:s['end']].encode()).hexdigest()==s['sha256']
    assert sel['configuration']==source['features'] and sel['source_underline_not_reconstructed']
    assert not source['source_full_input_verified'] and not source['source_marked_target_span_verified'] and not source['source_original_key_is_gold']
    draft=json.loads(load_ref(audit['manuscript']).read_text());validate(draft,source)
    assert binding['responses']==len(group['questions'])==10 and audit['sentence_task_count']==5
    assert audit['source_underline_gap_visible'] and audit['authored_target_marker']=='bold_plus_explicit_target_instruction'
    assert audit['full_fill_variant_combinations']==6
    assert audit['fully_filled_sentence_sets'] and len(audit['fully_filled_sentence_sets'])==6
    for n,q in enumerate(group['questions']):
        assert q['acceptedAnswers']==draft['sentences'][n//2]['accepted'][n%2]
        assert q['fillMarking']['maxWords'] is None and q['fillMarking']['unlisted']=='review'
    return True

def compile_author(manuscript,version='0.1'):
    d=json.loads(manuscript.read_text());bp=load_ref(d['source_bindings']);b=next(x for x in json.loads(bp.read_text())['bindings']if x['id']==d['source_binding']);s=next(x for x in json.loads(load_ref(b['source_index']).read_text())['groups']if x['id']==b['source_group_id']);validate(d,s)
    body='五项转换任务，共十个空。每空0.5分，共5分；原源未印统一每空词数上限。第4项加粗文字为本稿明确标出的提问目标。'
    qs=[]
    for i,row in enumerate(d['sentences'],1):
        body+='\n\n### 转换任务'+str(i)+'\n\n'+row['direction']+'\n\n原句：'+row['original']+'\n\n改写：'+row['target']
        for j,forms in enumerate(row['accepted']):
            n=2*i-1+j;qs.append(dict(number=n,stem='转换任务'+str(i)+'：第'+str(n)+'空',options=[],acceptedAnswers=forms,fillMarking=dict(version=1,review='author_context_checked',normalization='english_phrase_v1',maxWords=None,unlisted='review',rejectedAnswers=[]),rationale=row['rationale']+' 本空接受：'+' / '.join(forms)+'；未列形式待复核，不以少量答案证明穷尽。'))
    filled=[]
    for answers in product(*(q['acceptedAnswers']for q in qs)):
        result=[]
        for i,row in enumerate(d['sentences']):
            t=row['target']
            for n in [2*i+1,2*i+2]:t=t.replace('('+str(n)+') ____',answers[n-1])
            assert '____'not in t;result.append(t)
        filled.append(result)
    teacher='\n\n'.join('### 第'+str(i+1)+'套合法完整回填\n\n'+'\n\n'.join(rows)for i,rows in enumerate(filled))+'\n\n'+d['source_notice']
    block=response_markdown(qs);p=manuscript.parent/(d['id']+'-v'+version+'.md');ap=manuscript.parent/(d['id']+'-author-check-v'+version+'.json');assert not p.exists()and not ap.exists();p.write_text('# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n'+body+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+teacher+'\n')
    a=dict(version=version,id=d['id'],grade=7,questions=10,candidate_sha256=ref(p)['sha256'],source_binding=b['id'],source_bindings=ref(bp),source_group_id=s['id'],review_response_tasks=qs,canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),student_passage=body,manuscript=ref(manuscript),controlled_sentence_transformation=True,sentence_task_count=5,source_underline_gap_visible=True,authored_target_marker='bold_plus_explicit_target_instruction',fully_filled_sentence_sets=filled,full_fill_variant_combinations=len(filled),source_count_increment=0,authored_student_inputs_complete=True,load_measure=dict(body_English_words=words(body),stem_English_words=sum(words(q['stem'])for q in qs),options_English_words_with_repeated_bank=0,output_response_positions=10),source_level_equivalence_established=False,independent_teacher_student_commercial_production_validated=False);ap.write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n')
    return dict(id=d['id'],grade=7,family=d['family'],family_label='受约束句型转换',title=d['title'],questions=10,candidate=ref(p),author_check=ref(ap),source_group_ids=[s['id']],instruction=d['instruction'],source_form_notice=d['source_notice'],format_summary='5句转换 / 每句2空 / 共10个计分空 / 每空0.5分 / 本稿明确标示所有者提问目标')
