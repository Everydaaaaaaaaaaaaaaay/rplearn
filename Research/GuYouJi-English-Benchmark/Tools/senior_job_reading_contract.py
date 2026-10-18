"""Full reading section with a bounded job notice, survey and robotics account.

This gate checks complete inputs and authored consistency; it does not establish
unique-best answer quality, age calibration, factual truth or production marking.
"""
import html
import re


HEADINGS = ['Key duties', 'Schedule', 'Location', 'Qualifications',
            'Compensation', 'Work challenges']
OPERATIONS = [
    'job_duties_detail', 'inclusive_qualification_case', 'job_challenge_detail',
    'project_origin_detail', 'reported_volunteer_benefit', 'context_word_meaning',
    'whole_title', 'survey_association_detail', 'unfamiliar_task_inference',
    'quote_implication', 'whole_material_purpose', 'design_principle_inference',
    'attached_mechanism_detail', 'bounded_future_attitude', 'whole_title',
]


def notice(j):
    blocks = [
        j['duties'],
        'The placement has two phases: spring (' + j['spring_phase'] + '), ' +
        j['spring_days'] + '; summer (' + j['summer_phase'] + '), ' +
        j['summer_days'] + '. Leaders work ' + str(j['weekly_hours']) +
        ' hours per week in either phase. The change of season changes the regular working days, not the weekly hours.',
        j['location'],
        'Applicants must be at least ' + str(j['minimum_age']) +
        ' on the first working day and hold a current driving licence held for at least ' +
        str(j['minimum_licensed_years']) +
        ' years; exactly three years satisfies that minimum. Applicants must be able to lift ' +
        str(j['lift_pounds']) +
        ' pounds and work outdoors. Current CPR and outdoor first-aid certificates are required before field duties; training to obtain them is available before the placement. Previous conservation work and project leadership are preferred, not compulsory.',
        '$' + str(j['weekly_pay']) + ' per week, paid every ' + str(j['pay_every_weeks']) +
        ' weeks. The payment for two ordinary weeks is $' + str(j['weekly_pay'] * j['pay_every_weeks']) +
        ' before deductions. The placement includes staff training; this is a fictional notice, not an actual offer of employment.',
        j['challenge'],
    ]
    return j['organisation'] + ' — ' + j['role'] + '\n\n' + j['intro'] + '\n\n' + '\n\n'.join(
        '#### ' + title + '\n\n' + text for title, text in zip(HEADINGS, blocks))


def applicant_text(c, version='0.1'):
    if version == 'compact0.2':
        return ('Age ' + str(c['age']) + '; ' +
                ('current licence: exactly ' if c['current'] else 'licence expired after ') +
                str(c['licensed_years']) + ' years.')
    assert version == '0.1'
    if c['current']:
        return ('Aged ' + str(c['age']) + ', with a current driving licence held for exactly ' +
                str(c['licensed_years']) + ' years.')
    return ('Aged ' + str(c['age']) + ', with an expired licence first held ' +
            str(c['licensed_years']) + ' years ago.')


def eligible(c, j):
    return (c['age'] >= j['minimum_age'] and c['current'] and
            c['licensed_years'] >= j['minimum_licensed_years'])


def validate(d, source):
    c = source['configuration']
    assert c['response_distribution'] == [3, 4, 4, 4]
    assert c['text_unit_count'] == 4 and c['points_each'] == 2.5
    assert c['selected_objective_points'] == 37.5
    assert c['subgroups'][0]['genre'] == 'job_qualification_advertisement_with_subheadings'
    assert source['first_section37_5_not_whole_reading50']
    assert len(source['A_required_subheadings']) == 6
    assert [q['operation'] for q in d['questions']] == OPERATIONS
    j = d['job_notice']
    assert (j['minimum_age'], j['minimum_licensed_years'], j['lift_pounds'],
            j['weekly_hours'], j['weekly_pay'], j['pay_every_weeks']) == (21, 3, 40, 40, 750, 2)
    assert j['current_license_required'] and j['license_endpoint_inclusive']
    assert j['certificates'] == ['CPR', 'outdoor first aid']
    assert j['certificates_before_field_duties'] and j['training_before_placement_available']
    assert j['preferred_not_mandatory'] == ['previous conservation work', 'project leadership']
    assert j['spring_days'] == 'Tuesday to Saturday' and j['summer_days'] == 'Monday to Friday'
    assert j['spring_phase'] != j['summer_phase'] and j['location'].strip()
    assert d['sections'][0]['units'] == [notice(j)]
    assert re.findall(r'(?m)^#### (.+)$', d['sections'][0]['units'][0]) == HEADINGS
    cases = d['applicant_options']
    assert set(cases) == set('ABCD')
    for label, case in cases.items():
        assert dict(d['questions'][1]['options'])[label] == applicant_text(case, d.get('applicant_render_version', '0.1'))
    winners = [label for label, case in cases.items() if eligible(case, j)]
    assert winners == [d['questions'][1]['answer']]
    best = cases[winners[0]]
    assert best['age'] == 21 and best['licensed_years'] == 3 and best['current']
    assert d['applicant_other_requirements_assumed_met']
    assert 'certificate' in d['questions'][1]['stem'] and 'availability' in d['questions'][1]['stem']
    b = d['sections'][1]['units'][0]
    paragraphs = b.split('\n\n')
    assert '**' + d['lexical_target'] + '**' in paragraphs[3]
    assert 'paragraph 4' in d['questions'][5]['stem'] and d['lexical_target'] in d['questions'][5]['stem']
    survey = d['survey'];text = d['sections'][2]['units'][0]
    assert 0 < survey['separate_fair'] < survey['joint_fair'] <= survey['n_each']
    assert survey['joint_fair'] == 2 * survey['separate_fair']
    assert survey['n_each'] == 100
    assert all(str(survey[k]) in text for k in ['separate_fair', 'joint_fair', 'n_each'])
    assert survey['same_reported_total_share_not_same_chore_ownership']
    assert survey['existing_arrangements_not_random_assignment']
    assert survey['alternative_causal_directions_not_adjudicated']
    assert d['C_quote'] in text
    robot = d['robot'];text = d['sections'][3]['units'][0]
    assert robot['digit_total'] == 6 and robot['support_carry_modes'] == [[4, 2], [5, 1]]
    assert all(sum(pair) == robot['digit_total'] for pair in robot['support_carry_modes'])
    assert robot['six_digits_explicit_authored_choice_not_source_literal_claim']
    for key in ['four_two_evidence', 'five_one_evidence', 'attached_two_sides_evidence', 'simulation_testing_evidence', 'future_control_limit_evidence']:
        assert robot[key] in text and len(robot[key]) > 25
    assert d['D_quote'] in text and d['research_scope']['limitations']
    assert d['future_human_control_open'] and not d['human_interface_or_clinical_benefit_validated']
    assert len(d['answer_evidence']) == 15
    for q, ev in zip(d['questions'], d['answer_evidence']):
        body = d['sections']['ABCD'.index(q['materialLabel'])]['units'][0]
        assert ev['number'] == q['number'] and ev['best_text'] == dict(q['options'])[q['answer']]
        assert ev['evidence'] in body and len(ev['evidence']) > 20


def check_rendered(g, a, d):
    assert a['source_bound_job_notice_reading_section']
    assert a['job_notice'] == d['job_notice'] and a['applicant_options'] == d['applicant_options']
    assert a['survey'] == d['survey'] and a['robot'] == d['robot']
    rendered = g['passageHtml']
    headings = [html.unescape(re.sub('<[^>]+>', '', t)) for t in re.findall(r'<h3>(.*?)</h3>', rendered, re.S)]
    assert [h for h in headings if h in HEADINGS] == HEADINGS
    visible = html.unescape(re.sub('<[^>]+>', ' ', rendered))
    for text in ['Tuesday to Saturday', 'Monday to Friday', '$750', '$1500',
                 'preferred, not compulsory', 'exactly three years']:
        assert text in visible
    assert a['load_measure']['job_advert_subheadings'] == 6
