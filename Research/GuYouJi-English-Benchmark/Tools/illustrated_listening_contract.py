"""Source-bound whole sections; image positions, if present, are exact."""
CONFIGS={
 'grade7-hefei2025-21cnjy26607976.listening.sectionI':(7,'listening_short_conversation_choice',[1]*5,3,2,[1,2]),
 'grade7.dingyuan2025-26upper.listening.part1':(7,'listening_short_conversation_choice',[1]*5,3,2,[1,2]),
 'primary4.fangshan2024-25upper.listening.part3':('primary4','listening_dialogue_choice',[1,2,2],3,1,[4]),
 'primary4.fangshan2024-25upper.listening.part5':('primary4','listening_passage_choice',[5],3,1,[]),
 'primary5.guilin2024-25lower.listening.part2':('primary5','listening_picture_choice',[1,1,1,1,1],2,2,[1,2,3,4,5]),
 'primary6.dongcheng2024-25upper.listening.part5':('primary6','listening_passage_choice',[5],3,1,[1,5]),
}

def validate_draft(d):
 grade,family,counts,options,repeats,pictures=CONFIGS[d['source_group_id']]
 assert d['illustrated_listening']and d['grade']==grade and d['family']==family and d['render_repeat_count']==repeats
 assert [len(c['questions'])for c in d['clips']]==counts
 tasks=[q for c in d['clips']for q in c['questions']]
 assert [i for i,q in enumerate(tasks,1)if q.get('optionImageAssets')]==pictures
 for c in d['clips']:
  assert c['preview_seconds']==c['answer_seconds']==5*len(c['questions'])
  assert set(t['speaker']for t in c['turns'])==({'M','W'}if grade in ['primary5',7] or family=='listening_dialogue_choice'else{'N'})
 for q in tasks:
  assert [k for k,_ in q['options']]==list('ABC'[:options])and q['answer']in list('ABC'[:options])
  if q.get('optionImageAssets'):assert list(q['optionImageAssets'])==list('ABC'[:options])and all(not v for _,v in q['options'])
  if grade==7:
   assert all(k+'：'in q['rationale']for k in 'ABC')
   if not q.get('optionImageAssets'):assert len({v.casefold()for k,v in q['options']})==3 and all(v for k,v in q['options'])
 assert (d.get('source_repeat_count')==2)if grade in ['primary5',7]else(d['source_replay_rule']=='not_printed')
 return grade,counts,options,repeats,pictures
