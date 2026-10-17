#!/usr/bin/env python3
"""Whole senior short-dialogue sections; solved example remains unscored input."""
import argparse,hashlib,json,re
from pathlib import Path
from grade_mode_evidence import REPO,load_ref
from quality_review_contract import response_markdown
from compile_short_dialogue_listening import ref
from senior_short_listening_contract import validate_draft
from render_original_listening import words


def example_text(draft):
 if not draft.get('worked_example'):return ''
 q=draft['worked_example']['question']
 return '### 示例（已解，不计入五题）\n\n'+q['stem']+'\n\n'+'\n\n'.join(k+'. '+v for k,v in q['options'])+'\n\n答案：'+q['answer']+'。'+q['rationale']+'\n\n示例录音在材料1开头一遍，为本机示范编排；原示例精确播放次数未核，不把示例算第六道作答题。'


def check(group,audit,binding,source):
 sel=json.loads(load_ref(source['selected_native']).read_text());raw=load_ref(sel['source']).read_text()
 for s in sel['spans']:assert hashlib.sha256(raw[s['start']:s['end']].encode()).hexdigest()==s['sha256']
 assert sel['configuration']==source['features'] and source['source_structure_verified']
 student=next(s for s in sel['spans']if s['role']=='whole_first_section');student_text=raw[student['start']:student['end']]
 repeats=source['features']['repeat_count']
 assert ('每段对话读两遍' if repeats==2 else '每段对话仅读一遍')in student_text and '10秒钟'in student_text
 if source['features']['worked_examples']:
  assert '答案是C'in student_text and '例:'in student_text
  ks=next(s for s in sel['spans']if s['role']=='printed_key_first15');keytext=raw[ks['start']:ks['end']]
  assert '答案 C A C B A'in keytext
  script=next(s for s in sel['spans']if s['role']=='annotated_script_first5');scripttext=raw[script['start']:script['end']]
  assert all('Text'+str(n)in scripttext.replace(' ','')for n in range(1,6))
 elif source['id']=='grade12-shandong202411-21cnjy21677145.listening.sectionA':
  assert repeats==1 and '例'not in student_text
  key=next(s for s in sel['spans']if s['role']=='printed_key_first5');assert '1-5 BCBAC'in raw[key['start']:key['end']]
  script=next(s for s in sel['spans']if s['role']=='printed_script_first5');scripttext=raw[script['start']:script['end']]
  assert all('Text'+str(n)in scripttext.replace(' ','')for n in range(1,6))
  assert source['source_layer']=='public_reader_snapshot_text_not_original_scan_or_audio'
 assert not source['source_full_input_verified'] and not source['source_original_audio_acquired'] and not source['original_school_authenticated']
 d=json.loads(load_ref(audit['manuscript']).read_text());grade,example=validate_draft(d)
 assert grade==source['level']==group['grade']==binding['level'] and d['source_group_id']==source['id']
 assert source['features']==dict(conversations=5,responses=5,options_each=3,repeat_count=repeats,after_each_seconds=10,points_each=1.5,worked_examples=int(example))
 assert repeats==d['source_repeat_count']
 gen=json.loads(load_ref(audit['audio_generation']).read_text());assert gen['manuscript']==audit['manuscript'] and gen['whole_final_audio_decode_passed'] and gen['no_source_recording_reused']
 if gen.get('reused_verified_audio_manifest'):
  prior=json.loads(load_ref(gen['reused_verified_audio_manifest']).read_text())
  assert gen['rerendered_track_numbers']==[1] and gen['unchanged_tracks_reused_without_copy']
  assert gen['manuscript']==prior['manuscript'] and gen['tracks'][1:]==prior['tracks'][1:] and gen['tracks'][0]['sha256']!=prior['tracks'][0]['sha256']
 assert len(d['clips'])==len(gen['tracks'])==len(audit['audio_assets'])==len(group['requiredAudioAssets'])==len(group['questions'])==5
 for n,(clip,track,asset,shown)in enumerate(zip(d['clips'],gen['tracks'],audit['audio_assets'],group['requiredAudioAssets']),1):
  assert track['response_numbers']==asset['response_numbers']==shown['response_numbers']==[n]
  assert track['repeat_count']==asset['repeat_count']==shown['repeat_count']==repeats
  assert track['sha256']==asset['sha256']==shown['asset']['sha256'];load_ref(asset)
  heard=[s for s in track['segments']if s['role']=='dialogue'];assert [(s['speaker'],s['text'],s['repeat'])for s in heard]==[(t['speaker'],t['text'],r)for r in range(1,repeats+1)for t in clip['turns']]
  assert len([s for s in track['segments']if s['role']=='repeat_instruction'])==repeats-1
  last=track['segments'][-1];assert last['role']=='silence' and last['end_frame']-last['start_frame']==10*track['sample_rate']
  assert track['dialogue_words_once']==sum(words(t['text'])for t in clip['turns']) and track['peak_abs_sample']>0
  assert group['questions'][n-1]==dict(number=n,**clip['questions'][0])
  for t in clip['turns']:assert t['text']in group['reviewText'] and t['text']not in group['passageHtml']
  examples=[s for s in track['segments']if s['role']=='worked_example']
  if example and n==1:
   assert [(s['speaker'],s['text'])for s in examples]==[(t['speaker'],t['text'])for t in d['worked_example']['turns']]
   assert track['worked_example_assessed_responses']==0 and example_text(d)in audit['student_passage']
   assert len([s for s in track['segments']if s['role']=='worked_example_solution'])==1
   assert all(ord(c)<128 for c in next(s['text']for s in track['segments']if s['role']=='worked_example_solution'))
  else:assert not examples and 'worked_example_spoken_words'not in track
 return True


def compile_author(manuscript,version="0.1",audio_version="0.1"):
 d=json.loads(manuscript.read_text());grade,example=validate_draft(d);repeats=d['source_repeat_count'];repeat_label='一遍'if repeats==1 else'两遍';mp=REPO/'build/english-benchmark-authority-20261017/original-audio'/(d['id']+'-audio-v'+audio_version+'.json');gen=json.loads(mp.read_text());assert gen['manuscript']==ref(manuscript)
 bp=load_ref(d['source_bindings']);b=next(x for x in json.loads(bp.read_text())['bindings']if x['id']==d['source_binding'])
 parts=[example_text(d)]if example else [];teacher=[];tasks=[];assets=[]
 for n,(c,t)in enumerate(zip(d['clips'],gen['tracks']),1):
  audio=load_ref(t);parts+=['### 材料'+str(n),'[材料'+str(n)+'（第'+str(n)+'题；'+repeat_label+('；开头含已解示例'if example and n==1 else'')+'）](../../../../'+str(audio.relative_to(REPO))+')'];tasks.append(dict(number=n,**c['questions'][0]));assets.append({k:t[k]for k in ['path','sha256','seconds','response_numbers','repeat_count','mime_type']});teacher+=['### 材料'+str(n)+'完整原创脚本','\n\n'.join(t['speaker']+': '+t['text']for t in c['turns'])]
 if example:teacher+=['### 示例完整原创脚本','\n\n'.join(t['speaker']+': '+t['text']for t in d['worked_example']['turns'])]
 teacher += [d['source_notice'],'每题1.5分、五题7.5分，属本源卷配置。五段各'+repeat_label+'、末尾10秒；'+('两遍间一秒与重播提示是本机编排。'if repeats==2 else'单遍源十秒兼作本题作答与读下一题，不另加一段预览。')+'完整原创合成试听，不当自然语流、独立难度、教研、学生、商用或生产通过。']
 body='\n\n'.join(parts);block=response_markdown(tasks);p=manuscript.parent/(d['id']+'-v'+version+'.md');ap=manuscript.parent/(d['id']+'-author-check-v'+version+'.json');assert not p.exists()and not ap.exists()
 p.write_text('# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n'+body+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+'\n\n'.join(teacher)+'\n')
 a=dict(version=version,id=d['id'],grade=grade,questions=5,candidate_sha256=ref(p)['sha256'],source_binding=b['id'],source_bindings=ref(bp),source_group_id=d['source_group_id'],review_response_tasks=tasks,canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),student_passage=body,body_load_text=example_text(d),manuscript=ref(manuscript),audio_generation=ref(mp),audio_assets=assets,audio_transcript_in_teacher_only=True,senior_short_source_bound=True,source_companion_gap_visible=True,load_measure=dict(body_English_words=words(example_text(d)),stem_English_words=sum(words(q['stem'])for q in tasks),options_English_words_with_repeated_bank=sum(words(v)for q in tasks for _,v in q['options']),output_response_positions=5,audio_dialogue_English_words_once=sum(t['dialogue_words_once']for t in gen['tracks']),audio_spoken_words_with_instructions=sum(t['spoken_words_with_instructions']for t in gen['tracks']),audio_example_spoken_words=sum(t.get('worked_example_spoken_words',0)for t in gen['tracks']),audio_seconds_with_pauses=sum(t['seconds']for t in gen['tracks']),artifact_URLs_excluded_from_reading_load=True),source_count_increment=0,authored_student_inputs_complete=True,source_level_equivalence_established=False,independent_teacher_student_commercial_production_validated=False);ap.write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n')
 return dict(id=d['id'],grade=grade,family=d['family'],family_label='短对话听力单选',title=d['title'],questions=5,candidate=ref(p),author_check=ref(ap),source_group_ids=[d['source_group_id']],instruction=d['instruction'],source_form_notice=d['source_notice'],format_summary='5独立短对话 / 每段1题三选 / 共5回应 / 每段'+repeat_label+' / 听后10秒'+(' / 另1已解示例不计作答题'if example else''))
