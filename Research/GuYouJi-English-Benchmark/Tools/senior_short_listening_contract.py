"""Two observed five-dialogue/two-pass senior modes, one with solved example."""
CONFIGS={
 'grade11-yinchuan2026-21cnjy25860535.listening.sectionA':(11,False),
 'grade12-yali2026-21cnjy25133058.listening.sectionA':(12,True),
}

def validate_draft(draft):
 grade,example=CONFIGS[draft['source_group_id']]
 assert draft['senior_short_source_bound'] and draft['grade']==grade and draft['family']=='listening_short_conversation_choice'
 assert len(draft['clips'])==5 and draft['source_repeat_count']==2
 for c in draft['clips']:
  assert len(c['questions'])==1 and set(t['speaker']for t in c['turns'])=={'M','W'}
  assert c['preview_seconds']==0 and c['answer_seconds']==10
  q=c['questions'][0];assert [k for k,_ in q['options']]==['A','B','C'] and q['answer']in'ABC'
  assert all(k+'：'in q['rationale']for k in'ABC')
 assert bool(draft.get('worked_example'))==example
 if example:
  e=draft['worked_example'];assert [t['speaker']for t in e['turns']]==['M','W'] and [k for k,_ in e['question']['options']]==['A','B','C']
  assert e['question']['answer']in'ABC' and e['render_repeat_count']==1 and e['not_an_assessed_response']
 return grade,example
