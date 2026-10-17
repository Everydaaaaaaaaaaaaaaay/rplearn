"""Five story events and four-person/five-item assignments remain whole tasks."""

def table_markdown(t):
 assert len(t['people'])==4 and len(t['columns'])==5
 return '\n'.join(['| 人物 / 物品 | '+' | '.join(t['columns'])+' |','| --- | '+' | '.join(['---']*5)+' |']+['| '+name+' | '+' | '.join(['□']*5)+' |'for _,name in t['people']])


def validate_draft(d):
 assert d['sequence_table_listening'] and d['grade']in {'primary4','primary5'}
 if d['grade']=='primary4':assert d['render_repeat_count']==1 and d['source_repeat_count']is None and d['source_replay_rule']=='not_printed'
 else:assert d['render_repeat_count']==d['source_repeat_count']==3
 assert len(d['clips'])==1; c=d['clips'][0]
 assert len(c['questions'])==5 and len(c['turns'])==1 and c['turns'][0]['speaker']=='N' and c['preview_seconds']==c['answer_seconds']==25
 if d['family']=='listening_picture_ordering':
  assert d['source_group_id']==('primary4.fangshan2024-25upper.listening.part4'if d['grade']=='primary4'else'primary5.guilin2024-25lower.listening.part4') and len(d['figures'])==5
  assert list(d['visual_panel_semantics'])==(list('12345')if d['grade']=='primary4'else list('ABCDE'))
  assert len(set(q['answer']for q in c['questions']))==5
  expected=[[k,'第'+str(i)+'件事']for i,k in enumerate('ABCDE',1)]if d['grade']=='primary4'else[[k,'图'+k]for k in'ABCDE']
  assert all(q['options']==expected for q in c['questions'])
  if d['grade']=='primary4':assert d['picture_to_event_rank']
 else:
  assert d['grade']=='primary5' and d['family']=='listening_table_matching' and d['source_group_id']=='primary5.guilin2024-25lower.listening.part5'
  t=d['response_table'];table_markdown(t);assert len(d['figures'])==1
  assert len(set(n for _,n in t['people']))==4 and [k for k,_ in t['people']]==list('ABCD')
  assert len(set(q['answer']for q in c['questions']))==4
  assert all(q['options']==t['people']for q in c['questions'])
 return d['family']
