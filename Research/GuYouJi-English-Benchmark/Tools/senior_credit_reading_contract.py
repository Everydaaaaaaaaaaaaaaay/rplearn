"""Bind a fictional credit notice, nested conditions and complete source-derived reading section."""
import re
import html
from decimal import Decimal


def format_credit(v):
    return format(Decimal(str(v)).normalize(),'f')


def total_credits(p):
    return sum(Decimal(str(c['credits']))for c in p['compulsory'])+Decimal(str(p['optional_credits']))


def notice(p):
    return ('### '+p['school']+' certificate requirements\n\n'
        'The following rules belong to an invented school. Students must meet all the requirements to receive its upper-school certificate.\n\n'
        '### Compulsory credits\n\n'+ '\n'.join('- '+format_credit(c['credits'])+(' credit in 'if Decimal(str(c['credits'])) in [Decimal('0.5'),Decimal('1')]else' credits in ')+c['subject']for c in p['compulsory'])+'\n\n'
        '### Optional credits\n\nStudents must earn '+str(p['optional_credits'])+' optional credits from approved courses. Up to '+str(p['dual_credit_cap'])+' of these optional credits may come from approved partner-college courses; they are included, not added to the optional total.\n\n'
        '### Online learning\n\nStudents who entered Year 9 in '+p['online_cohort_start']+' or later must complete at least '+str(p['online_credits'])+' credits online. These online credits count within the compulsory or optional requirements above; they are not extra credits.\n\n'
        '### Literacy requirement\n\nThe literacy rule takes effect on '+p['literacy_effective']+'. Students graduating in '+p['literacy_graduation_year']+' or later must satisfy the school’s literacy check as well as its credit requirements.\n\n'
        '### Community involvement\n\nAt least '+str(p['community_hours'])+' hours of approved community activity are required. These hours are not course credits. Before beginning, students must:\n\n'
        '- check that the proposed activity meets the school’s approval rules;\n'
        '- consult the school’s list of approved and prohibited activities;\n'
        '- discuss the plan with a parent or guardian if they are under '+str(p['minor_age'])+'.\n\n'
        'Students aged '+str(p['minor_age'])+' or over must still verify that an activity qualifies, but the parent-or-guardian discussion rule does not apply to them.')


def validate(d,s):
    assert s['credit_requirement_blocks_bound'] and len(s['source_A_requirement_blocks'])==5
    assert s['configuration']['required_lists']==['A.credit_requirements']
    p=d['credit_notice'];assert len(p['compulsory'])==11
    assert len({c['subject']for c in p['compulsory']})==11
    assert all(Decimal(str(c['credits']))>0 for c in p['compulsory'])
    assert sum(c['credits']==0.5 for c in p['compulsory'])==2
    assert 0<p['dual_credit_cap']<=p['optional_credits'] and p['online_credits']==2
    assert p['online_included_in_total'] and p['community_hours']==40 and p['minor_age']==18
    assert p['adult_must_verify_approval'] and not p['adult_parent_discussion_required']
    assert d['sections'][0]['units']==[notice(p)]
    qs=d['questions'];assert qs[0]['operation']=='nested_credit_total'
    expected=format_credit(total_credits(p))+' credits.'
    assert dict(qs[0]['options'])[qs[0]['answer']]==expected
    assert p['online_cohort_start']in qs[0]['stem']
    assert qs[1]['operation']=='policy_effective_date'
    assert dict(qs[1]['options'])[qs[1]['answer']]==p['literacy_effective']+'.'
    assert qs[2]['operation']=='adult_conditional_requirement'
    assert dict(qs[2]['options'])[qs[2]['answer']]==d['adult_answer_text']
    assert qs[4]['operation']=='context_word_meaning'
    assert '**'+d['lexical_target']+'**'in d['sections'][1]['units'][0] and d['lexical_target']in qs[4]['stem']
    assert qs[8]['operation']=='narrow_result_scope' and qs[9]['operation']=='mental_rehearsal_application'
    assert qs[13]['operation']=='future_application_aim' and qs[14]['operation']=='research_author_attitude'
    assert len(d['mechanism_stages'])==3 and len(set(d['mechanism_stages']))==3
    assert all(stage in d['sections'][3]['units'][0]for stage in d['mechanism_stages'])
    assert d['future_aim']in d['sections'][3]['units'][0] and d['research_scope']['limitations']
    return True


def check_rendered(g,a,d):
    assert a['credit_notice']==d['credit_notice'] and a['source_bound_credit_notice_reading_section']
    first=g['passageHtml'].split('<h3>B组')[0]
    lists=re.findall(r'<ul class="reading-requirements">(.*?)</ul>',first,re.S)
    assert len(lists)==2
    actual=[[html.unescape(re.sub('<[^>]+>','',v))for v in re.findall(r'<li>(.*?)</li>',part,re.S)]for part in lists]
    expected=re.findall(r'(?m)^- (.+)$',notice(d['credit_notice']))
    assert actual[0]==expected[:11] and actual[1]==expected[11:]
    assert a['load_measure']['half_credit_entries']==2
    assert a['load_measure']['community_hours_not_credits']==40
    return True
