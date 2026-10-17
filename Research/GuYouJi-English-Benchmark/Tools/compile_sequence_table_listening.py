#!/usr/bin/env python3
"""Five chronological events or five assignments in a whole 4x5 table."""
import hashlib,json
from grade_mode_evidence import REPO,load_ref
from quality_review_contract import response_markdown
from compile_short_dialogue_listening import ref
from listening_sequence_table_contract import validate_draft,table_markdown
from render_original_listening import words


def check(group,audit,binding,source):
 sel=json.loads(load_ref(source['selected_native']).read_text());assert sel['source']==source['source']and sel['features']==source['features']
 if sel.get('source_native'):
  raw=load_ref(sel['source_native']).read_text()
  for s in sel['spans']:assert hashlib.sha256(raw[s['start']:s['end']].encode()).hexdigest()==s['sha256']
 assert not source['source_full_input_verified']and not source['source_original_key_is_gold']and not source['original_school_authenticated']
 if source['level']=='primary4':
  assert not source['source_original_pictures_missing']
  for im in source['source_images']:load_ref(im)
 else:assert source['source_original_pictures_missing']
 d=json.loads(load_ref(audit['manuscript']).read_text());family=validate_draft(d);assert family==source['kind']==group['kind']and group['grade']==binding['level']==source['level']==d['grade']
 assert source['features']['repeat_count']==d['source_repeat_count'] and source['responses']==len(group['questions'])==5
 assert group['questions']==audit['review_response_tasks']
 assert [x['asset']for x in group['requiredPassageImages']]==d['figures']
 if family=='listening_table_matching':
  assert source['features']['people_rows']==4 and source['features']['item_columns']==5 and source['features']['response_assignments']==5 and source['features']['one_person_can_prepare_multiple_items']
  assert group['responseTable']==audit['response_table']==d['response_table']and table_markdown(d['response_table'])in audit['student_passage']
 else:
  assert len(group['requiredPassageImages'])==5 and group['fixedSharedBank']
  if d.get('picture_to_event_rank'):assert group['pictureToEventRank']and audit['picture_to_event_rank']
 gen=json.loads(load_ref(audit['audio_generation']).read_text());assert gen['manuscript']==audit['manuscript']and gen['whole_final_audio_decode_passed']and gen['no_source_recording_reused']
 assert len(gen['tracks'])==len(audit['audio_assets'])==len(group['requiredAudioAssets'])==1
 t=gen['tracks'][0];a=audit['audio_assets'][0];shown=group['requiredAudioAssets'][0];c=d['clips'][0]
 assert t['response_numbers']==a['response_numbers']==shown['response_numbers']==list(range(1,6)) and t['repeat_count']==a['repeat_count']==shown['repeat_count']==d['render_repeat_count']
 assert t['sha256']==a['sha256']==shown['asset']['sha256'];load_ref(a)
 assert [(s['speaker'],s['text'],s['repeat'])for s in t['segments']if s['role']=='dialogue']==[('N',c['turns'][0]['text'],r)for r in range(1,d['render_repeat_count']+1)]
 assert len([s for s in t['segments']if s['role']=='repeat_instruction'])==d['render_repeat_count']-1
 for seg in[t['segments'][1],t['segments'][-1]]:assert seg['role']=='silence'and seg['end_frame']-seg['start_frame']==25*t['sample_rate']
 assert t['decoded_frames']>0 and t['peak_abs_sample']>0 and c['turns'][0]['text']in group['reviewText']and c['turns'][0]['text']not in group['passageHtml']
 return True


def compile_author(manuscript):
 d=json.loads(manuscript.read_text());family=validate_draft(d);order=family=='listening_picture_ordering';version=d['version'];mp=REPO/'build/english-benchmark-authority-20261017/original-audio'/(d['id']+'-audio-v'+version+'.json');gen=json.loads(mp.read_text());assert gen['manuscript']==ref(manuscript)
 bp=load_ref(d['source_bindings']);b=next(x for x in json.loads(bp.read_text())['bindings']if x['id']==d['source_binding']);t=gen['tracks'][0];parts=['[完整故事/书信录音（全部5题；'+str(d['render_repeat_count'])+'遍）](../../../../'+str(load_ref(t).relative_to(REPO))+')']
 for i,fig in enumerate(d['figures']):
  label=('第'+str(i+1)+'图'if d.get('picture_to_event_rank')else'候选图'+'ABCDE'[i])if order else'物品图1—5';parts +=['### '+label,'!['+label+'](../../../../'+str(load_ref(fig).relative_to(REPO))+')']
 if not order:parts +=['### 四人五物品完整表',table_markdown(d['response_table'])]
 tasks=[dict(number=n,**q)for n,q in enumerate(d['clips'][0]['questions'],1)];body='\n\n'.join(parts);block=response_markdown(tasks)
 teacher=['### 完整原创脚本','N: '+d['clips'][0]['turns'][0]['text'],d['source_form_notice'],'自有图片语义：'+json.dumps(d['visual_panel_semantics'],ensure_ascii=False),d.get('local_timing_notice','每篇三遍、本机前后及重播间25秒另有提示；源精确停顿未印，不继承本机参数。')+'一整故事或书信只有五回应，不截断或按表二十格计二十题。必要自有图音完整不补平源图/音缺。图形/生活主题复用不当独立曝光，脚本默认隐藏。独立教研、学生、商用、生产未验证。']
 p=manuscript.parent/(d['id']+'-v'+version+'.md');ap=manuscript.parent/(d['id']+'-author-check-v'+version+'.json');assert not p.exists()and not ap.exists();p.write_text('# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n'+body+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+'\n\n'.join(teacher)+'\n')
 bodywords=''if order else' '.join(name for _,name in d['response_table']['people']);a=dict(version=version,id=d['id'],grade=d['grade'],questions=5,candidate_sha256=ref(p)['sha256'],source_binding=b['id'],source_bindings=ref(bp),source_group_id=d['source_group_id'],review_response_tasks=tasks,canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),student_passage=body,body_load_text=bodywords,manuscript=ref(manuscript),audio_generation=ref(mp),audio_assets=[{k:t[k]for k in['path','sha256','seconds','response_numbers','repeat_count','mime_type']}],figure_assets=d['figures'],audio_transcript_in_teacher_only=True,sequence_table_listening=True,load_measure=dict(body_English_words=words(bodywords),stem_English_words=sum(words(q['stem'])for q in tasks),options_English_words_with_repeated_bank=sum(words(v)for q in tasks for _,v in q['options']),visual_panel_positions=5,grid_cells=0 if order else 20,output_response_positions=5,audio_dialogue_English_words_once=t['dialogue_words_once'],audio_spoken_words_with_instructions=t['spoken_words_with_instructions'],audio_seconds_with_pauses=t['seconds']),source_count_increment=0,authored_student_inputs_complete=True,source_level_equivalence_established=False,independent_teacher_student_commercial_production_validated=False)
 if d.get('picture_to_event_rank'):a['picture_to_event_rank']=True
 if not order:a['response_table']=d['response_table']
 ap.write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n');return dict(id=d['id'],grade=d['grade'],family=family,family_label=d['family_label'],title=d['title'],questions=5,candidate=ref(p),author_check=ref(ap),source_group_ids=[d['source_group_id']],instruction=d['instruction'],source_form_notice=d['source_form_notice'],format_summary=d['format_summary'],use_select_controls=order)
