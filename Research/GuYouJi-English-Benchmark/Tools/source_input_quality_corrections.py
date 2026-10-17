"""Keep known source defects effective without changing frozen source records."""
import hashlib
import json
from functools import lru_cache
from grade_mode_evidence import load_ref


def payload_sha(group):
    return hashlib.sha256(json.dumps(group,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()


def records(plan):
    if not plan.get('current_source_input_quality_corrections'):
        return ()
    reference=plan['current_source_input_quality_corrections']
    return _records(reference['path'],reference['sha256'])


@lru_cache(maxsize=8)
def _records(path,sha256):
    # These manifests are immutable. Verify their referenced originals once per
    # process, rather than rehashing the same pages for every authored group.
    index=json.loads(load_ref(dict(path=path,sha256=sha256)).read_text())
    result=index['records']
    assert len({r['canonical_source_id']for r in result})==len(result)
    for r in result:
        # An acknowledged damaged source may describe a bounded form; it cannot
        # become a complete-input or correct-key anchor through a legacy flag.
        assert r['canonical_source_id']=='primary6.minzhi2016-17.contexts'
        assert r['source_ids']==['p6.minzhi.functions','primary6.minzhi2016-17.contexts']
        assert r['level']=='primary6' and r['family']=='function_choice'
        assert r['responses']==5 and r['options_per_response']==[3]*5
        assert r['structure_observed'] is True
        assert r['current_source_full_input_verified'] is False and r['source_key_positive_clearance'] is False
        assert r['question_physical_pages']==[2,3] and r['key_physical_pages']==[4]
        assert r['missing_input_positions']==['14.2.B'] and r['key_quality_hold_positions']==['14.2','14.5']
        assert len(r['groups'])==3 and len({g['id']for g in r['groups']})==3
        for evidence in r['evidence']:load_ref(evidence)
    return tuple(result)


def source_status(plan,source,legacy_complete):
    correction=next((r for r in records(plan)if source['id'] in r['source_ids']),None)
    if correction:
        assert source['level']==correction['level'] and source['responses']==correction['responses']
        counts=source.get('candidates',{}).get('per_response',[source.get('options_each')]*source['responses'])
        assert counts==correction['options_per_response']
        return dict(structure_reference=True,full_source_input_verified=False,key_positive_clearance=False)
    assert legacy_complete is True
    return dict(structure_reference=True,full_source_input_verified=True,key_positive_clearance=False)


def expected_notice(plan,group_id,legacy_notice):
    for r in records(plan):
        for g in r['groups']:
            if g['id']==group_id:
                assert hashlib.sha256(legacy_notice.encode()).hexdigest()==g['prior_source_notice_sha256']
                return r['current_source_notice']
    return legacy_notice


def apply(data,plan):
    rows=records(plan)
    if not rows:return
    for r in rows:
        for m in r['groups']:
            g=data['groups'][m['id']]
            assert payload_sha(g)==m['prior_payload_sha256']
            assert g['grade']==r['level'] and g['kind']==r['family']
            assert set(g['anchor_group_ids']) & set(r['source_ids'])
            assert len(g['questions'])==r['responses']
            assert [len(q['options'])for q in g['questions']]==r['options_per_response']
            g['sourceFormNotice']=expected_notice(plan,g['id'],g['sourceFormNotice'])
    data['source_input_quality_corrections']=plan['current_source_input_quality_corrections']


def check(data,plan):
    rows=records(plan)
    if not rows:return 0
    assert data['source_input_quality_corrections']==plan['current_source_input_quality_corrections']
    for r in rows:
        for m in r['groups']:
            assert data['groups'][m['id']]['sourceFormNotice']==r['current_source_notice']
    return sum(len(r['groups'])for r in rows)
