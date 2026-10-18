"""Separate the current common-type review from preserved research observations."""
import json
from grade_mode_evidence import load_ref

def build_view(data,plan):
 if not plan.get('current_common_type_scope'):return None
 scope=json.loads(load_ref(plan['current_common_type_scope']).read_text())
 assert scope['owner_requests_common_types_only'] and not scope['one_observation_implies_required_type']
 assert not scope['unknown_cartesian_cells_are_backlog'] and scope['originals_and_historical_metadata_preserved']
 assert {r['level']for r in scope['levels']}==set(data['grades'])
 known={(c['grade'],c['family']):c for c in data['cells']};merged={};active=set()
 for level in scope['levels']:
  assert level['evidence'] and level['classification_status']
  for rr in level['evidence']:load_ref(rr)
  for rule in level['retained_types']:
   key=(level['level'],rule['display_family']);c=merged.setdefault(key,dict(grade=key[0],family=key[1],label=rule['label'],observed=True,state='common_type_author_review',groupId=None,groupIds=[],pendingSpecificModes=[],scopeNotice=level['notice'],scopeClassificationStatus=level['classification_status'],sourceFamilies=[]))
   assert c['label']==rule['label']
   for family in rule['source_families']:
    source=known[(level['level'],family)];assert source['observed']
    c['sourceFamilies'].append(family)
    for ident in source.get('groupIds',[]):
     assert ident not in active,'Author counted twice in common display'
     active.add(ident);c['groupIds'].append(ident)
   if c['groupIds']:c['groupId']=c['groupIds'][0]
 view=list(merged.values());assert all(any(c['grade']==g for c in view)for g in data['grades'])
 return dict(scope_ref=plan['current_common_type_scope'],cells=view,active_group_ids=sorted(active),active_groups=len(active),active_responses=sum(len(data['groups'][i]['questions'])for i in active),active_level_type_cells=len(view),reference_only_groups=len(data['groups'])-len(active),preserved_research_groups=len(data['groups']),commonness_review_complete=scope['commonness_review_complete'],notice=scope['display_notice'],required_specific_mode_ids=scope['required_specific_mode_ids'])

def apply(data,plan):
 view=build_view(data,plan)
 if view:
  data['common_type_view']=view
  data['display_coverage_audit']=dict(scope_notice='当前只处理代表性试卷中的常见客观题型。地方特别编排和未证常见的模式保留研究记录，不再自动成为必补目标。',issues=[dict(levels=data['grades'],label='逐档核常见性',state_label='高三与四六级有现成结构依据，其余档位继续核代表卷和跨地区重复情况',detail='已观察仅证明样本中存在，不等于常见。首轮范围是保守初筛，尚未完成全部档位的常见性复核；不以当前收缩后的数量宣称任务全部完成。'),dict(levels=data['grades'],label='题型与具体配置分开',state_label='不再每遇新配置强制编三稿',detail='同一常见题型内部保留完整材料、子组、题数和候选等规则；特别配图、篇数或题数差异作为来源变体，不另凑必须覆盖的类型。'),dict(levels=data['grades'],label='现有题目质量',state_label='判分变体、唯一最佳和完整媒体继续核验',detail='既有原创与原件保留；作者自审和本机行为验证不等于独立教师、学生或生产验证。')])
 return view

def check(data,plan):
 expected=build_view(data,plan)
 if expected:
  assert data['common_type_view']==expected
  assert all(c['observed']for c in data['cells']), 'Synthetic unknown grade/type cells must not be produced'
  assert not any(c['grade']==12 and c['family']=='phonetic_word_completion'for c in expected['cells'])
 return expected
