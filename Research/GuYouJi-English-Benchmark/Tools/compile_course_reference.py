"""Complete authored learning packets plus ten source-shaped initial prompts.

The learning packets are new author materials. Visible-reference review does not
replicate a pupil's prior teaching or delayed recall conditions, which are unknown.
"""
import hashlib,json,re
from grade_mode_evidence import load_ref
from compile_primary6_written_groups import ref,words
from quality_review_contract import response_markdown


def validate(d,b,s):
    assert d['grade']==b['level']==s['level']=='primary6'
    assert d['family']==b['family']==s['kind']=='context_word_completion'
    assert d['source_group_id']==b['source_group_id']==s['id']
    assert s['source_full_input_verified']is False and s['source_key_acquired']is False
    assert s['school_exam_authentication']is False and b['raw_exam_not_repaired']is True
    assert s['features']==b['source_features']==dict(sentence_tasks=10,responses=10,printed_initials=list('bfbtasmbqe'),max_words_each=1,external_course_text_required=True,external_course_text_identified=False)
    # The observed initials are b/f/b/t/a/s/m/b/q/e; no textbook sentence is reconstructed.
    assert [x['initial'].lower()for x in d['slots']]==s['features']['printed_initials']
    witness=json.loads(load_ref(b['current_source_companion_review']).read_text())
    assert witness['course_positions_matched']==[1,2,3,5,6,8,10]and witness['course_positions_not_matched']==[4,7,9]
    assert witness['course_mode_full_input_not_upgraded']and witness['original_key_still_missing']
    assert b['source_curriculum_visibility_or_delay_conditions']=='unknown'
    assert b['authored_packet_design_not_source_passage_count']
    assert d['study_visibility']=='visible_reference_practice_not_controlled_delayed_recall'
    assert d['source_input_not_repaired']and d['author_packet_is_complete']
    assert len(d['lessons'])==4 and all(v['text']and v['title']for v in d['lessons'])and len(d['slots'])==10
    for n,q in enumerate(d['slots'],1):
        assert q['number']==n and q['lesson']in range(1,5)
        assert len(re.findall(r'([A-Za-z])____',q['frame']))==1 and q['frame'].count('____')==1
        assert re.search(r'([A-Za-z])____',q['frame'])[1]==q['initial']
        assert q['accepted']and len(set(q['accepted']))==len(q['accepted'])and set(q['grounds'])==set(q['accepted'])and all(q['grounds'].values())
        for a in q['accepted']:
            assert re.fullmatch('[A-Za-z]+',a)and a[0].casefold()==q['initial'].casefold()
            filled=q['frame'].replace(q['initial']+'____',a)
            assert q['reference_sentence']in d['lessons'][q['lesson']-1]['text']
            assert filled in d['lessons'][q['lesson']-1]['text']
            assert filled==q.get('reference_alternative_sentences',{}).get(a,q['reference_sentence'])
    assert '完整单词' in d['instruction']and '首字母' in d['instruction']and '每空一词' in d['instruction']
    return True


def compile_author(mp,version='0.2'):
    d=json.loads(mp.read_text());bp=load_ref(d['source_bindings']);b=next(v for v in json.loads(bp.read_text())['bindings']if v['id']==d['source_binding']);s=next(v for v in json.loads(load_ref(b['source_index']).read_text())['groups']if v['id']==b['source_group_id']);validate(d,b,s)
    passage='自有课文配套（可参照；不是受控延时记忆测验）\n\n'+'\n\n'.join(v['title']+'\n\n'+v['text']for v in d['lessons'])
    tasks=[dict(number=q['number'],stem=q['frame']+'〔配套'+str(q['lesson'])+'〕',options=[],acceptedAnswers=q['accepted'],fillMarking=dict(version=1,review='author_context_checked',normalization='english_phrase_v1',maxWords=1,requiredInitial=q['initial'],unlisted='review',unknownSyntax='review',rejectedAnswers=[]),rationale='；'.join(k+'：'+v for k,v in q['grounds'].items())+'；依据：配套'+str(q['lesson'])+'原句 '+q['reference_sentence']+' 未列形式待复核，不宣称合法表达穷尽。')for q in d['slots']]
    block=response_markdown(tasks);teacher='\n\n'.join('### '+str(q['number'])+'：'+' / '.join(q['acceptedAnswers'])+'\n\n'+q['rationale']for q in tasks)
    text='# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n'+passage+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+teacher+'\n\n'+d['source_notice']+'\n'
    p=mp.parent/(d['id']+'-v'+version+'.md');ap=mp.parent/(d['id']+'-author-check-v'+version+'.json')
    a=dict(version=version,id=d['id'],grade=d['grade'],questions=10,source_binding=b['id'],source_bindings=ref(bp),source_group_id=s['id'],manuscript=ref(mp),candidate_sha256=hashlib.sha256(text.encode()).hexdigest(),canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),review_response_tasks=tasks,student_passage=passage,course_reference_ten=True,study_lessons=d['lessons'],full_slot_substitutions=[dict(number=q['number'],lesson=q['lesson'],accepted_full_inputs=[q['frame'].replace(q['initial']+'____',v)for v in q['accepted']],reference_sentence=q['reference_sentence'])for q in d['slots']],source_count_increment=0,authored_student_inputs_complete=True,raw_exam_not_repaired=True,prior_teaching_or_delayed_recall_replicated=False,independent_teacher_student_commercial_production_validated=False,load_measure=dict(body_English_words=words(passage),stem_English_words=sum(words(q['stem'])for q in tasks),options_English_words_with_repeated_bank=0,output_response_positions=10,output_known_forms=sum(len(q['accepted'])for q in d['slots'])))
    for path,t in [(p,text),(ap,json.dumps(a,ensure_ascii=False,indent=2)+'\n')]:
        if path.exists():assert path.read_text()==t
        else:path.write_text(t)
    return dict(id=d['id'],grade=d['grade'],family=d['family'],family_label='语境词汇补全',title=d['title'],questions=10,candidate=ref(p),author_check=ref(ap),source_group_ids=[s['id']],instruction=d['instruction'],source_form_notice=d['source_notice'],format_summary='10独立句 / 给首字母 / 每空1词 / 完整自有课文配套随题提供 / 原课文7/10、课堂与延时条件未复现')


def check(g,a,b,s):
    d=json.loads(load_ref(a['manuscript']).read_text());validate(d,b,s)
    selected=json.loads(load_ref(s['selected_native']).read_text());native=json.loads(load_ref(selected['native_text']).read_text())
    assert selected['source']==s['source']and selected['configuration']==s['features']and selected['source_full_inputs_verified']is False
    for span in selected['spans']:
        t=native['pages'][span['physical_page']-1]['text'][span['start']:span['end']];assert t==span['text']and hashlib.sha256(t.encode()).hexdigest()==span['sha256']
    assert a['course_reference_ten']and a['raw_exam_not_repaired']and not a['prior_teaching_or_delayed_recall_replicated']
    assert a['study_lessons']==d['lessons']and g['questions']==a['review_response_tasks']
    assert a['student_passage']=='自有课文配套（可参照；不是受控延时记忆测验）\n\n'+'\n\n'.join(v['title']+'\n\n'+v['text']for v in d['lessons'])
    for q,r,filled in zip(g['questions'],d['slots'],a['full_slot_substitutions']):
        assert q['stem']==r['frame']+'〔配套'+str(r['lesson'])+'〕'and q['acceptedAnswers']==r['accepted']and q['options']==[]
        assert q['fillMarking']==dict(version=1,review='author_context_checked',normalization='english_phrase_v1',maxWords=1,requiredInitial=r['initial'],unlisted='review',unknownSyntax='review',rejectedAnswers=[])
        assert filled==dict(number=r['number'],lesson=r['lesson'],accepted_full_inputs=[r['frame'].replace(r['initial']+'____',v)for v in r['accepted']],reference_sentence=r['reference_sentence'])
    return True
