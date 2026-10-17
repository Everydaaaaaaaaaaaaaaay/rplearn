"""Named people select labelled shared pictures; no invented one-use rule."""
CONFIGS={
 'primary3.dongcheng2025-26upper.listening.part3':('primary3','listening_person_sport_matching',[5],1,None),
 'primary5.guilin2024-25lower.listening.part3':('primary5','listening_description_picture_matching',[1]*5,2,2),
}

def validate_draft(d):
 grade,family,counts,repeats,source_repeats=CONFIGS[d['source_group_id']]
 assert d['shared_picture_listening'] and d['grade']==grade and d['family']==family
 assert d['render_repeat_count']==repeats and d['source_repeat_count']==source_repeats
 assert [len(c['questions'])for c in d['clips']]==counts and len(d['figures'])==1
 assert list(d['visual_panel_semantics'])==list('ABCDE') and len(set(d['visual_panel_semantics'].values()))==5
 tasks=[q for c in d['clips']for q in c['questions']]
 assert len({q['stem']for q in tasks})==5
 for c in d['clips']:
  assert c['preview_seconds']==c['answer_seconds']==(15 if grade=='primary3'else 5)
  assert len(c['turns'])==len(c['questions']) and all(t['speaker']=='N'for t in c['turns'])
 for q in tasks:
  assert q['options']==[[k,'图'+k]for k in'ABCDE'] and q['answer'] in list('ABCDE') and 'bankReuse'not in q
 assert '没有额外规定'in d['instruction']
 return grade,counts,repeats
