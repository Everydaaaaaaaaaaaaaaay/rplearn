"""Two actual mixed/picture-choice blueprints, not a generic grade template."""
CONFIGS={
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
  assert set(t['speaker']for t in c['turns'])==({'M','W'}if grade=='primary5'else{'N'})
 for q in tasks:
  assert [k for k,_ in q['options']]==list('ABC'[:options])and q['answer']in'ABC'[:options]
  if q.get('optionImageAssets'):assert list(q['optionImageAssets'])==list('ABC'[:options])and all(not v for _,v in q['options'])
 assert (d.get('source_repeat_count')==2)if grade=='primary5'else(d['source_replay_rule']=='not_printed')
 return grade,counts,options,repeats,pictures
