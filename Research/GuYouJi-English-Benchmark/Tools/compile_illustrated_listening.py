#!/usr/bin/env python3
"""Complete audio and every illustrated candidate, with portable text metadata."""
import hashlib,json,re
import xml.etree.ElementTree as ET
from grade_mode_evidence import REPO,load_ref
from quality_review_contract import response_markdown
from quality_review_images import check_option_images,without_derived_images
from compile_short_dialogue_listening import ref
from illustrated_listening_contract import validate_draft
from render_original_listening import words


def check(group,audit,binding,source):
 sel=json.loads(load_ref(source['selected_native']).read_text());assert sel['source']==source['source']and sel['features']==source['features']
 for im in source.get('source_images',[]):load_ref(im)
 if sel.get('source_native'):
  raw=load_ref(sel['source_native']).read_text()
  for span in sel['spans']:assert hashlib.sha256(raw[span['start']:span['end']].encode()).hexdigest()==span['sha256']
 assert not source['source_full_input_verified']and not source['source_original_key_is_gold']and not source['original_school_authenticated']
 d=json.loads(load_ref(audit['manuscript']).read_text());grade,counts,options,repeats,pictures=validate_draft(d)
 assert grade==source['level']==group['grade']==binding['level']and d['source_group_id']==source['id']and source['features']['subgroup_responses']==counts
 assert source['features']['options_each']==options and source['features']['picture_response_positions']==pictures
 assert source['features']['repeat_count']==(2 if grade in ['primary5',7]else None)
 if grade==7:
  assert sel['source_full_printed_input_verified']
  if d['source_group_id']=='grade7-hefei2025-21cnjy26607976.listening.sectionI':
   assert sel['source_original_script_verified'] and sel['source_original_key_verified']
   assert source['source_original_script_acquired'] and source['source_original_key_acquired']
   assert sel['reference_keys']==list('BACBB') and sel['reference_key_script_visual_consistent_not_aural_gold']
   assert source['features']['first_picture_content']=='everyday_objects'
   assert source['features']['second_picture_content']=='person_pictures'
  else:
   assert not sel['source_original_script_verified'] and not sel['source_original_key_verified']
  assert sel['source_question_numbers']==list(range(1,6)) and source['features']['points_each']==1
  assert source['features']['roles_owned_not_source_gender_verified']
 assert check_option_images(group)==len(pictures)*options and not group['requiredPassageImages']
 assert without_derived_images(group['questions'])==audit['review_response_tasks']
 gen=json.loads(load_ref(audit['audio_generation']).read_text());assert gen['manuscript']==audit['manuscript']and gen['whole_final_audio_decode_passed']and gen['no_source_recording_reused']
 assert len(d['clips'])==len(gen['tracks'])==len(audit['audio_assets'])==len(group['requiredAudioAssets'])==len(counts)
 cursor=1
 for c,t,a,shown in zip(d['clips'],gen['tracks'],audit['audio_assets'],group['requiredAudioAssets']):
  ns=list(range(cursor,cursor+len(c['questions'])));assert t['response_numbers']==a['response_numbers']==shown['response_numbers']==ns and t['repeat_count']==a['repeat_count']==shown['repeat_count']==repeats
  assert t['sha256']==a['sha256']==shown['asset']['sha256'];load_ref(a)
  assert [(s['speaker'],s['text'],s['repeat'])for s in t['segments']if s['role']=='dialogue']==[(x['speaker'],x['text'],r)for r in range(1,repeats+1)for x in c['turns']]
  assert len([s for s in t['segments']if s['role']=='repeat_instruction'])==repeats-1
  for seg in[t['segments'][1],t['segments'][-1]]:assert seg['role']=='silence'and seg['end_frame']-seg['start_frame']==5*len(ns)*t['sample_rate']
  assert t['decoded_frames']>0 and t['peak_abs_sample']>0 and t['dialogue_words_once']==sum(words(x['text'])for x in c['turns'])
  for x in c['turns']:assert x['text']in group['reviewText']and x['text']not in group['passageHtml']
  cursor+=len(ns)
 assert len(group['questions'])==source['responses']==5
 return True


def compile_author(manuscript,version='0.1',audio_version='0.1'):
 d=json.loads(manuscript.read_text());grade,counts,options,repeats,pictures=validate_draft(d);mp=REPO/'build/english-benchmark-authority-20261017/original-audio'/(d['id']+'-audio-v'+audio_version+'.json');gen=json.loads(mp.read_text());assert gen['manuscript']==ref(manuscript)
 bp=load_ref(d['source_bindings']);b=next(x for x in json.loads(bp.read_text())['bindings']if x['id']==d['source_binding']);parts=[];teacher=[];tasks=[];assets=[];cursor=1
 for i,(c,t)in enumerate(zip(d['clips'],gen['tracks']),1):
  audio=load_ref(t);ns=list(range(cursor,cursor+len(c['questions'])));parts+=['### 材料'+str(i),'[材料'+str(i)+'（第'+str(ns[0])+'—'+str(ns[-1])+'题；本机'+str(repeats)+'遍）](../../../../'+str(audio.relative_to(REPO))+')'];teacher+=['### 材料'+str(i)+'完整原创脚本','\n\n'.join(x['speaker']+': '+x['text']for x in c['turns'])];tasks += [dict(number=n,**q)for n,q in zip(ns,c['questions'])];assets.append({k:t[k]for k in['path','sha256','seconds','response_numbers','repeat_count','mime_type']});cursor+=len(ns)
 teacher += [d['source_form_notice'],d.get('local_timing_notice','本机停顿/重播提示是审阅编排，原精确时序未知。')+('所有图候选为自有矢量图，仅以选项位置标识，不用英文对象名称代图；图形复用不当独立曝光或难度标定。'if pictures else'本组全部五题为文字候选，没有额外必要图片。')+'完整原创输入不补平来源缺口。独立教研、儿童识图/听辨、学生、商用和生产未验证。']
 body='\n\n'.join(parts);block=response_markdown(tasks);p=manuscript.parent/(d['id']+'-v'+version+'.md');ap=manuscript.parent/(d['id']+'-author-check-v'+version+'.json');assert not p.exists()and not ap.exists();p.write_text('# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n'+body+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+'\n\n'.join(teacher)+'\n')
 a=dict(version=version,id=d['id'],grade=grade,questions=5,candidate_sha256=ref(p)['sha256'],source_binding=b['id'],source_bindings=ref(bp),source_group_id=d['source_group_id'],review_response_tasks=tasks,canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),student_passage=body,body_load_text='',manuscript=ref(manuscript),audio_generation=ref(mp),audio_assets=assets,audio_transcript_in_teacher_only=True,illustrated_listening=True,source_timing_unknown_preserved=True,load_measure=dict(body_English_words=0,stem_English_words=sum(words(q['stem'])for q in tasks),options_English_words_with_repeated_bank=sum(words(v)for q in tasks for _,v in q['options']),picture_option_positions=len(pictures)*options,output_response_positions=5,audio_dialogue_English_words_once=sum(t['dialogue_words_once']for t in gen['tracks']),audio_spoken_words_with_instructions=sum(t['spoken_words_with_instructions']for t in gen['tracks']),audio_seconds_with_pauses=sum(t['seconds']for t in gen['tracks'])),source_count_increment=0,authored_student_inputs_complete=True,source_level_equivalence_established=False,independent_teacher_student_commercial_production_validated=False)
 image_text=' '.join(' '.join(node.itertext()) for task in tasks for asset in task.get('optionImageAssets',{}).values() for node in ET.fromstring(load_ref(asset).read_bytes()).iter() if node.tag.split('}')[-1]=='text')
 a['load_measure'].update(option_image_English_words=words(image_text),option_image_number_tokens=len(re.findall(r'\b\d+\b',image_text)))
 ap.write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n')
 return dict(id=d['id'],grade=grade,family=d['family'],family_label=d['family_label'],title=d['title'],questions=5,candidate=ref(p),author_check=ref(ap),source_group_ids=[d['source_group_id']],instruction=d['instruction'],source_form_notice=d['source_form_notice'],format_summary=d.get('format_summary','5独立对话各1题 / 每题2图 / 每段2遍'if grade=='primary5'else'1完整短文5题 / 1、5题各3图 / 中间3题各3文字选项 / 源遍数未知 / 本机1遍'))
