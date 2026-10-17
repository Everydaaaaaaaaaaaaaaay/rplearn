"""Five story events and four-person/five-item assignments remain whole tasks."""

def table_markdown(t):
 assert len(t['people'])==4 and len(t['columns'])==5
 return '\n'.join(['| 人物 / 物品 | '+' | '.join(t['columns'])+' |','| --- | '+' | '.join(['---']*5)+' |']+['| '+name+' | '+' | '.join(['□']*5)+' |'for _,name in t['people']])


def validate_draft(d):
 assert d['sequence_table_listening'] and d['grade']=='primary5' and d['render_repeat_count']==d['source_repeat_count']==3
 assert len(d['clips'])==1; c=d['clips'][0]
 assert len(c['questions'])==5 and len(c['turns'])==1 and c['turns'][0]['speaker']=='N' and c['preview_seconds']==c['answer_seconds']==25
 if d['family']=='listening_picture_ordering':
  assert d['source_group_id']=='primary5.guilin2024-25lower.listening.part4' and len(d['figures'])==5
  assert list(d['visual_panel_semantics'])==list('ABCDE')
  assert len(set(q['answer']for q in c['questions']))==5
  assert all(q['options']==[[k,'图'+k]for k in'ABCDE']for q in c['questions'])
 else:
  assert d['family']=='listening_table_matching' and d['source_group_id']=='primary5.guilin2024-25lower.listening.part5'
  t=d['response_table'];table_markdown(t);assert len(d['figures'])==1
  assert len(set(n for _,n in t['people']))==4 and [k for k,_ in t['people']]==list('ABCD')
  assert len(set(q['answer']for q in c['questions']))==4
  assert all(q['options']==t['people']for q in c['questions'])
 return d['family']
