#!/usr/bin/env python3
"""Full shared bank and all person-description assignments, with owned audio."""
import hashlib,json
from grade_mode_evidence import REPO,load_ref
from quality_review_contract import response_markdown
from compile_short_dialogue_listening import ref
from shared_picture_listening_contract import validate_draft
from render_original_listening import words


def check(group,audit,binding,source):
 sel=json.loads(load_ref(source['selected_native']).read_text());assert sel['source']==source['source']and sel['features']==source['features']
 for im in source.get('source_images',[]):load_ref(im)
 if sel.get('source_native'):
  raw=load_ref(sel['source_native']).read_text()
  for s in sel['spans']:assert hashlib.sha256(raw[s['start']:s['end']].encode()).hexdigest()==s['sha256']
 assert not source['source_full_input_verified']and not source['source_original_key_is_gold']and not source['original_school_authenticated']
 d=json.loads(load_ref(audit['manuscript']).read_text());grade,counts,repeats=validate_draft(d)
 assert d['grade']==source['level']==group['grade']==binding['level']and source['features']['repeat_count']==d['source_repeat_count']
 assert source['features']['reuse_rule']=='not_printed'and len(group['requiredPassageImages'])==1 and group['fixedSharedBank']
 assert group['requiredPassageImages'][0]['asset']==d['figures'][0]and group['questions']==audit['review_response_tasks']
 gen=json.loads(load_ref(audit['audio_generation']).read_text());assert gen['manuscript']==audit['manuscript']and gen['whole_final_audio_decode_passed']and gen['no_source_recording_reused']
 assert len(gen['tracks'])==len(audit['audio_assets'])==len(group['requiredAudioAssets'])==len(counts)
 cursor=1
 for c,t,a,shown in zip(d['clips'],gen['tracks'],audit['audio_assets'],group['requiredAudioAssets']):
  ns=list(range(cursor,cursor+len(c['questions'])));assert t['response_numbers']==a['response_numbers']==shown['response_numbers']==ns and t['repeat_count']==a['repeat_count']==shown['repeat_count']==repeats
  assert t['sha256']==a['sha256']==shown['asset']['sha256'];load_ref(a)
  assert [(s['speaker'],s['text'],s['repeat'])for s in t['segments']if s['role']=='dialogue']==[(x['speaker'],x['text'],r)for r in range(1,repeats+1)for x in c['turns']]
  assert len([s for s in t['segments']if s['role']=='repeat_instruction'])==repeats-1
  for seg in[t['segments'][1],t['segments'][-1]]:assert seg['role']=='silence'and seg['end_frame']-seg['start_frame']==c['answer_seconds']*t['sample_rate']
  assert t['decoded_frames']>0 and t['peak_abs_sample']>0
  for x in c['turns']:assert x['text']in group['reviewText']and x['text']not in group['passageHtml']
  cursor+=len(ns)
 assert len(group['questions'])==source['responses']==5
 return True


def compile_author(manuscript):
 d=json.loads(manuscript.read_text());grade,counts,repeats=validate_draft(d);mp=REPO/'build/english-benchmark-authority-20261017/original-audio'/(d['id']+'-audio-v0.1.json');gen=json.loads(mp.read_text());assert gen['manuscript']==ref(manuscript)
 bp=load_ref(d['source_bindings']);b=next(x for x in json.loads(bp.read_text())['bindings']if x['id']==d['source_binding']);parts=['### 共享候选图A—E','![共享候选图A—E](../../../../'+str(load_ref(d['figures'][0]).relative_to(REPO))+')'];teacher=[];tasks=[];assets=[];cursor=1
 for i,(c,t)in enumerate(zip(d['clips'],gen['tracks']),1):
  ns=list(range(cursor,cursor+len(c['questions'])));parts+=['### 材料'+str(i),'[材料'+str(i)+'（第'+str(ns[0])+'—'+str(ns[-1])+'题；本机'+str(repeats)+'遍）](../../../../'+str(load_ref(t).relative_to(REPO))+')'];teacher+=['### 材料'+str(i)+'完整原创脚本','\n\n'.join(x['speaker']+': '+x['text']for x in c['turns'])];tasks +=[dict(number=n,**q)for n,q in zip(ns,c['questions'])];assets.append({k:t[k]for k in['path','sha256','seconds','response_numbers','repeat_count','mime_type']});cursor+=len(ns)
 teacher+=[d['source_form_notice'],'自有共享图A—E语义：'+json.dumps(d['visual_panel_semantics'],ensure_ascii=False),'本机分段、停顿、重播提示不作为源规则；源图/音/键完整性与自有输入分层。每图标签可重复选择，不以参考恰为排列证明原每项一次。三个版本复用同一共享图，不当十五独立视觉题。脚本默认隐藏；独立教研、儿童识图听辨、学生、商用、生产未验证。']
 body='\n\n'.join(parts);block=response_markdown(tasks);p=manuscript.parent/(d['id']+'-v0.1.md');ap=manuscript.parent/(d['id']+'-author-check-v0.1.json');assert not p.exists()and not ap.exists();p.write_text('# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n'+body+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+'\n\n'.join(teacher)+'\n')
 a=dict(version='0.1',id=d['id'],grade=grade,questions=5,candidate_sha256=ref(p)['sha256'],source_binding=b['id'],source_bindings=ref(bp),source_group_id=d['source_group_id'],review_response_tasks=tasks,canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),student_passage=body,body_load_text='',manuscript=ref(manuscript),audio_generation=ref(mp),audio_assets=assets,figure_assets=d['figures'],audio_transcript_in_teacher_only=True,shared_picture_listening=True,load_measure=dict(body_English_words=0,stem_English_words=sum(words(q['stem'])for q in tasks),options_English_words_with_repeated_bank=sum(words(v)for q in tasks for _,v in q['options']),shared_visual_panels=5,output_response_positions=5,audio_dialogue_English_words_once=sum(t['dialogue_words_once']for t in gen['tracks']),audio_spoken_words_with_instructions=sum(t['spoken_words_with_instructions']for t in gen['tracks']),audio_seconds_with_pauses=sum(t['seconds']for t in gen['tracks'])),source_count_increment=0,authored_student_inputs_complete=True,source_level_equivalence_established=False,independent_teacher_student_commercial_production_validated=False);ap.write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n')
 return dict(id=d['id'],grade=grade,family=d['family'],family_label=d['family_label'],title=d['title'],questions=5,candidate=ref(p),author_check=ref(ap),source_group_ids=[d['source_group_id']],instruction=d['instruction'],source_form_notice=d['source_form_notice'],format_summary=d['format_summary'],use_select_controls=True)
