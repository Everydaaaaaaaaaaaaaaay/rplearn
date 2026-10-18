"""Source-specific full twenty-question section: advice, letter, migration, survey.

These are input/consistency gates. Author evidence pins are not an independent
judgement that a best answer is unique or that the exercise is calibrated.
"""
import html
import re


OPERATIONS = [
    'opening_problem', 'step_example_match', 'step_reason',
    'controlled_trial_condition', 'step_handover_purpose',
    'emotion_inference', 'paragraph_main_idea', 'contextual_sentence_inference',
    'letter_purpose', 'whole_message', 'seasonal_detail',
    'method_effort_inference', 'model_purpose', 'results_paragraph_main_idea',
    'whole_title', 'opening_function', 'report_construct',
    'age_comparison_inference', 'quantitative_paragraph_purpose',
    'bounded_association_conclusion',
]


def normal(text):
    return text.replace('’', "'")


def validate(d, source):
    c = source['configuration']
    assert c['response_distribution'] == [5, 5, 5, 5]
    assert c['points_each'] == 2.5 and c['selected_objective_points'] == 50
    assert c['required_lists'] == ['A.numbered_advice_steps']
    assert [s['genre'] for s in c['subgroups']] == [
        'advice_article_with_steps', 'personal_letter_narrative',
        'migration_research_report', 'survey_report']
    assert d['source_bound_steps_letter_migration_survey'] is True
    assert [q['operation'] for q in d['questions']] == OPERATIONS
    bodies = [s['units'][0] for s in d['sections']]
    advice, letter, migration, survey = bodies
    steps = re.findall(r'(?m)^(\d+)\. (.+)$', advice)
    assert [n for n, _ in steps] == list('1234')
    assert len(d['steps']) == 4 and len(set(d['steps'])) == 4
    for (_, text), title in zip(steps, d['steps']):
        assert text.startswith(title + ' ')
        assert len(text[len(title):].split()) >= 35  # supporting prose, not four labels
    l = d['letter']
    assert letter.startswith(l['salutation'] + '\n\n')
    assert letter.endswith('\n\n' + l['closing'])
    assert len(l['chain']) == 3 and len(set(l['chain'])) == 3
    positions = [normal(letter).casefold().index(normal(s).casefold()) for s in l['chain']]
    assert positions == sorted(positions)
    assert l['quote'] in letter
    m = d['migration']
    assert all(isinstance(m[k], int) and m[k] > 0 for k in
               ['caught', 'sampled', 'tracked', 'flights', 'years'])
    assert m['caught'] > m['sampled'] > m['tracked']
    assert m['flights'] > m['caught'] and 3 <= m['years'] <= 10
    assert str(m['caught']) + ' different birds' in migration
    assert str(m['sampled']) in migration and str(m['tracked']) in migration
    assert str(m['flights']) in migration
    assert m['condition'] in migration and m['projection'] in migration
    assert m['observation'] in migration
    assert d['migration_evidence']['counts_are_project_totals'] is True
    assert d['migration_evidence']['flights_are_not_individuals'] is True
    assert d['migration_evidence']['projection_not_observed_future'] is True
    for k, text in d['migration_evidence']['input_spans'].items():
        assert text in migration and len(text) > 20
        if k in m and isinstance(m[k], int):
            assert str(m[k]) in text
    assert set(d['migration_evidence']['input_spans']) == {
        'caught', 'sampled', 'tracked', 'flights', 'nonidentity', 'condition_limit'}
    sv = d['survey']
    assert sv['first_scale'] == '0 to 10' and sv['second_scale'] == '1 to 3'
    for k in ['first_scale', 'second_scale', 'first_construct', 'second_construct', 'association']:
        assert normal(sv[k]) in normal(survey)
    young, older = sv['first_young'], sv['first_older']
    assert len(young) == len(older) == 2
    assert young[0] > older[0] and young[1] < older[1]
    assert young[1] < young[0] and older[1] > older[0]
    for value in young + older:
        assert 0 <= value <= 10 and str(value) in survey
    assert len(sv['second_cohorts']) == 2
    declines = []
    for cohort, values in sv['second_cohorts'].items():
        assert cohort.lower() in survey.lower() and len(values) == 2
        assert 1 <= values[1] < values[0] <= 3
        assert all(f'{value:.2f}' in survey for value in values)
        declines.append(round(values[0] - values[1], 2))
    assert declines[0] > declines[1]
    assert d['survey_evidence']['separate_constructs_cohorts_and_scales'] is True
    assert d['survey_evidence']['fresh_samples_not_individual_panel'] is True
    assert d['survey_evidence']['association_not_causation'] is True
    assert set(d['survey_evidence']['input_spans']) == {
        'construct', 'age_order', 'separate_school_trend', 'noncausal_limit'}
    for text in d['survey_evidence']['input_spans'].values():
        assert text in survey and len(text) > 20
    # Every answer is paired with a reviewed evidence substring in its own material.
    assert len(d['answer_evidence']) == 20
    for q, ev in zip(d['questions'], d['answer_evidence']):
        body = bodies['ABCD'.index(q['materialLabel'])]
        assert ev['number'] == q['number']
        assert ev['best_text'] == dict(q['options'])[q['answer']]
        assert ev['evidence'] in body and len(ev['evidence']) > 20


def check_rendered(g, a, d):
    assert a['source_bound_steps_letter_migration_survey']
    assert a['steps'] == d['steps'] and a['letter'] == d['letter']
    assert a['migration'] == d['migration'] and a['survey'] == d['survey']
    rendered = g['passageHtml']
    lists = re.findall(r'<ol class="reading-activities">(.*?)</ol>', rendered, re.S)
    assert len(lists) == 1
    entries = re.findall(r'<li value="(\d+)">(.*?)</li>', lists[0], re.S)
    assert [n for n, _ in entries] == list('1234')
    for (_, text), title in zip(entries, d['steps']):
        assert html.unescape(text).startswith(title + ' ')
        assert len(html.unescape(text).split()) >= 35
    visible = html.unescape(re.sub('<[^>]+>', ' ', rendered))
    assert d['letter']['salutation'] in visible
    assert all(part in visible for part in d['letter']['closing'].splitlines())
    assert all(str(d['migration'][key]) in visible for key in ['caught', 'sampled', 'tracked', 'flights'])
    assert a['load_measure']['ordered_advice_steps'] == 4
