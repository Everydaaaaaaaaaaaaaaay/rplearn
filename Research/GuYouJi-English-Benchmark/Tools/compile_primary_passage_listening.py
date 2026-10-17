#!/usr/bin/env python3
"""A whole five-statement primary passage, not five separate mini passages."""
import hashlib,json
from grade_mode_evidence import REPO,load_ref
from quality_review_contract import response_markdown
from compile_short_dialogue_listening import ref
from render_original_listening import words


def check(group,audit,binding,source):
 s=json.loads(load_ref(source['selected_native']).read_text())
 assert s['source']==source['source']and s['source_images']==source['source_images']and s['question_numbers']==source['source_question_numbers']==list(range(21,26))
 assert s['options']==['T','F']and s['repeats_and_timing_not_printed']and source['features']['repeats']is None
 for p in source['source_images']:load_ref(p)
 assert not any(source[k]for k in ['source_key_acquired','source_script_acquired','source_original_audio_acquired','source_full_input_verified'])
 d=json.loads(load_ref(audit['manuscript']).read_text());g=json.loads(load_ref(audit['audio_generation']).read_text());c=d['clips'][0];t=g['tracks'][0];a=audit['audio_assets'][0];shown=group['requiredAudioAssets'][0]
 assert d['grade']==group['grade']==binding['level']==source['level']=='primary6'and d['source_group_id']==source['id']
 assert g['manuscript']==audit['manuscript']and g['whole_final_audio_decode_passed']and g['no_source_recording_reused']
 assert len(d['clips'])==len(g['tracks'])==len(audit['audio_assets'])==len(group['requiredAudioAssets'])==1
 assert len(c['questions'])==len(group['questions'])==source['responses']==5 and len(c['turns'])==1 and c['turns'][0]['speaker']=='N'
 assert d['source_replay_rule']=='not_printed'and d['render_repeat_count']==1
 assert t['response_numbers']==a['response_numbers']==shown['response_numbers']==list(range(1,6))and t['repeat_count']==shown['repeat_count']==1
 assert t['sha256']==a['sha256']==shown['asset']['sha256'];load_ref(a)
 assert t['decoded_frames']>0 and t['peak_abs_sample']>0 and t['dialogue_words_once']==words(c['turns'][0]['text'])
 heard=[s for s in t['segments']if s['role']=='dialogue'];assert [(s['speaker'],s['text'],s['repeat'])for s in heard]==[('N',c['turns'][0]['text'],1)]
 assert not any(s['role']=='repeat_instruction'for s in t['segments'])
 for segment in[t['segments'][1],t['segments'][-1]]:assert segment['role']=='silence'and segment['end_frame']-segment['start_frame']==25*t['sample_rate']
 assert all(group['questions'][n-1]==dict(number=n,**q)and[k for k,_ in q['options']]==['T','F']for n,q in enumerate(c['questions'],1))
 assert c['turns'][0]['text']in group['reviewText']and c['turns'][0]['text']not in group['passageHtml']
 assert not group.get('requiredPassageImages')and audit['primary_passage_listening']
 return True


def compile_author(manuscript):
 d=json.loads(manuscript.read_text());mp=REPO/'build/english-benchmark-authority-20261017/original-audio'/(d['id']+'-audio-v0.1.json');g=json.loads(mp.read_text());assert g['manuscript']==ref(manuscript)
 bp=load_ref(d['source_bindings']);binding=next(x for x in json.loads(bp.read_text())['bindings']if x['id']==d['source_binding']);c=d['clips'][0];t=g['tracks'][0];audio=load_ref(t);tasks=[dict(number=n,**q)for n,q in enumerate(c['questions'],1)];body='[完整短文五题音频（本机一遍，可重播）](../../../../'+str(audio.relative_to(REPO))+')';block=response_markdown(tasks)
 teacher='### 完整原创脚本\n\nN: '+c['turns'][0]['text']+'\n\n'+d['source_form_notice']+'\n\n原卷未印播放遍数、暂停或逐题分值。本机一遍、听前后25秒属于审阅安排，可重播，不当源卷限制。全五个判断依据同一完整短文，不拆成五独立材料。自然语流、儿童听辨、独立难度/教研、学生、商用、生产未验证。'
 p=manuscript.parent/(d['id']+'-v0.1.md');ap=manuscript.parent/(d['id']+'-author-check-v0.1.json');assert not p.exists()and not ap.exists();p.write_text('# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n'+body+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+teacher+'\n')
 asset={k:t[k]for k in ['path','sha256','seconds','response_numbers','repeat_count','mime_type']};a=dict(version='0.1',id=d['id'],grade='primary6',questions=5,candidate_sha256=ref(p)['sha256'],source_binding=binding['id'],source_bindings=ref(bp),source_group_id=d['source_group_id'],review_response_tasks=tasks,canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),student_passage=body,body_load_text='',manuscript=ref(manuscript),audio_generation=ref(mp),audio_assets=[asset],audio_transcript_in_teacher_only=True,primary_passage_listening=True,source_timing_unknown_preserved=True,load_measure=dict(body_English_words=0,stem_English_words=sum(words(q['stem'])for q in tasks),options_English_words_with_repeated_bank=0,output_response_positions=5,audio_dialogue_English_words_once=t['dialogue_words_once'],audio_spoken_words_with_instructions=t['spoken_words_with_instructions'],audio_seconds_with_pauses=t['seconds']),source_count_increment=0,authored_student_inputs_complete=True,source_level_equivalence_established=False,independent_teacher_student_commercial_production_validated=False);ap.write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n')
 return dict(id=d['id'],grade='primary6',family=d['family'],family_label='听短文判断',title=d['title'],questions=5,candidate=ref(p),author_check=ref(ap),source_group_ids=[d['source_group_id']],instruction=d['instruction'],source_form_notice=d['source_form_notice'],format_summary='1完整短文 / 5印出陈述T-F / 源遍数时序未知 / 本机一遍可重播')
