"""Expose verified-but-unauthored concrete modes without counting them as drafts."""
import json
from grade_mode_evidence import load_ref


def records(plan, groups, levels):
    reference = plan.get('current_pending_source_modes')
    if not reference:
        return []
    catalog = json.loads(load_ref(reference).read_text())
    assert catalog['observations_count'] == len(catalog['rows'])
    assert catalog['source_counts_not_incremented'] and not catalog['national_taxonomy_exhaustive']
    result=[];seen=set()
    for row in catalog['rows']:
        assert row['id'] not in seen and row['grade'] in levels and row['evidence']
        seen.add(row['id'])
        assert row['source_structure_observed'] and not row['source_key_is_gold']
        assert row['target_whole_originals'] == 3 and row['configuration']['responses'] > 0
        assert row['source_group_id'] and row['source_gap'] and row['author_count_requires_same_specific_source_group']
        for evidence in row['evidence']:load_ref(evidence)
        authored=[g['id'] for g in groups.values() if g['grade']==row['grade'] and g['kind']==row['family'] and row['source_group_id'] in g['anchor_group_ids']]
        result.append({**row,'currentGroupIds':authored,'remainingWholeOriginals':max(0,row['target_whole_originals']-len(authored))})
    return result


def attach(cells, labels, modes):
    for row in modes:
        key=(row['grade'],row['family'])
        if row['family'] in labels:
            assert labels[row['family']]==row['label'],'Inconsistent family label: '+row['family']
        labels[row['family']]=row['label']
        cell=cells.setdefault(key,dict(grade=row['grade'],family=row['family'],label=row['label'],observed=True,state='source_structure_observed_author_pending',groupId=None,groupIds=[]))
        cell['observed']=True
        cell.setdefault('pendingSpecificModes',[])
        if row['remainingWholeOriginals']:
            cell['pendingSpecificModes'].append(row['id'])
            if not cell.get('groupId'):
                cell['pauseReason']='结构已观察，完整原创待补。'+row['title']+'：'+row['source_gap']
