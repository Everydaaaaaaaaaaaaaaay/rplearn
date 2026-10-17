"""Bind shared candidate matching to whole owned dialogue recordings."""
import hashlib,json
from urllib.parse import quote
from grade_mode_evidence import load_ref,REPO
from quality_review_contract import response_markdown
from compile_short_dialogue_listening import ref
from render_original_listening import words
from academic_shared_audio_matching_contract import validate_draft

def compile_author(manuscript,manifest):
    d=json.loads(manuscript.read_text());validate_draft(d);gen=json.loads(manifest.read_text())
    assert gen['manuscript']==ref(manuscript) and gen['whole_final_audio_decode_passed'] and gen['no_source_recording_reused']
    bp=load_ref(d['source_bindings']);b=next(b for b in json.loads(bp.read_text())['bindings'] if b['id']==d['source_binding']);s=next(s for s in json.loads(load_ref(b['source_index']).read_text())['groups'] if s['id']==d['source_group_id'])
    assert s['features']['responses']==len(d['clips'][0]['questions']) and s['features']['reuse_rule']==d['reuse_rule']
    track=gen['tracks'][0];audio=load_ref(track);qs=[]
    for n,q in enumerate(d['clips'][0]['questions'],1):qs.append(dict(number=n,stem=q['stem'],options=q['options'],answer=q['answer'],rationale=q['rationale']+'；'+'；'.join(k+'：'+v for k,v in q['candidate_reasons'].items())))
    bank='### 共享候选\n\n'+'\n\n'.join(k+'. '+v for k,v in d['candidates'])
    body='[完整原创对话（本机一遍，审阅可重播）](../../../../'+str(audio.relative_to(REPO))+')\n\n'+bank
    teacher='\n\n'.join(t['speaker']+': '+t['text'] for t in d['clips'][0]['turns'])+'\n\n'+d['source_notice'];block=response_markdown(qs);p=manuscript.parent/(d['id']+'-v0.1.md');ap=manuscript.parent/(d['id']+'-author-check-v0.1.json');assert not p.exists() and not ap.exists()
    p.write_text('# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n'+body+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+teacher+'\n')
    a=dict(version='0.1',id=d['id'],grade='advanced',questions=len(qs),candidate_sha256=ref(p)['sha256'],source_binding=b['id'],source_bindings=ref(bp),source_group_id=s['id'],manuscript=ref(manuscript),audio_generation=ref(manifest),audio_assets=[{k:track[k] for k in ['path','sha256','seconds','response_numbers','repeat_count','mime_type']}],audio_transcript_in_teacher_only=True,academic_shared_audio_matching=True,review_response_tasks=qs,canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),student_passage=body,body_load_text=bank,source_count_increment=0,authored_student_inputs_complete=True,load_measure=dict(body_English_words=words(bank),stem_English_words=sum(words(q['stem']) for q in qs),options_English_words_with_repeated_bank=sum(words(v) for q in qs for k,v in q['options']),options_English_words_unique_bank=sum(words(v) for k,v in d['candidates']),output_response_positions=len(qs),audio_dialogue_English_words_once=track['dialogue_words_once'],audio_spoken_words_with_instructions=track['spoken_words_with_instructions'],audio_seconds_with_pauses=track['seconds']),source_level_equivalence_established=False,independent_teacher_student_commercial_production_validated=False);ap.write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n')
    return dict(id=d['id'],grade='advanced',family=d['family'],family_label='听力选项意向归类' if len(qs)==5 else '听力描述配候选',title=d['title'],questions=len(qs),candidate=ref(p),author_check=ref(ap),source_group_ids=[s['id']],instruction=d['instruction'],source_form_notice=d['source_notice'],use_select_controls=True,format_summary='1完整双人对话 / '+str(len(qs))+'回应 / '+str(len(d['candidates']))+'共享候选 / '+('明确可复用' if len(qs)==5 else '源未印复用限制')+' / 源课堂无音频，本机原创一遍')

def check(g,a,b,s):
    d=json.loads(load_ref(a['manuscript']).read_text());validate_draft(d);gen=json.loads(load_ref(a['audio_generation']).read_text());track=gen['tracks'][0]
    assert gen['manuscript']==a['manuscript'] and gen['whole_final_audio_decode_passed'] and gen['no_source_recording_reused']
    assert s['source_full_printed_input_and_script_verified'] and s['source_audio_status']==d['source_audio_status'] and not s['source_original_key_is_gold']
    assert 'There is no audio for this activity' in load_ref(s['source_pages'][0]).read_text()
    assert len(g['requiredAudioAssets'])==1 and g['requiredAudioAssets'][0]['asset']=={k:track[k] for k in ['path','sha256']}
    assert g['requiredAudioAssets'][0]['src']=='../../'+quote(track['path'])
    assert track['response_numbers']==list(range(1,b['responses']+1)) and track['repeat_count']==1
    assert [(t['speaker'],t['text']) for t in track['segments'] if t['role']=='dialogue']==[(t['speaker'],t['text']) for t in d['clips'][0]['turns']]
    assert all(t['text'] in g['reviewText'] and t['text'] not in g['passageHtml'] for t in d['clips'][0]['turns'])
    assert g['fixedSharedBank'] and g['questions']==a['review_response_tasks']
    assert all(q['options']==d['candidates'] for q in g['questions'])
    return True
