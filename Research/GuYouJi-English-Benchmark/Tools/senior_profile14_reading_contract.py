"""Fourteen-response senior profile/research section with explicit illustrations.

The source photos are not response-coded. Authored vectors preserve illustration
support and captions, without claiming photo/visual-load or difficulty equivalence.
"""
import base64
import hashlib
import html
import re
from grade_mode_evidence import load_ref

OPERATIONS=['volunteer_personal_benefit','volunteer_required_adaptation','allowance_purpose_not_salary',
 'profile_reading_influence','profile_original_purpose','profile_donation_route','profile_character_supported',
 'animal_study_trigger','animal_multilevel_finding','animal_report_main_purpose',
 'meal_method_and_findings','context_meal_omission_word','expert_nutrient_view_not_experiment','author_stance_to_routine_omission']


def notice(j):
    headings=['Why volunteer with '+j['organisation'],'Requirements','Conditions of Service']
    return j['title']+'\n\n'+j['intro']+'\n\n'+'\n\n'.join('#### '+h+'\n\n'+'\n'.join('- '+s for s in rows)for h,rows in zip(headings,[j['benefits'],j['requirements'],j['service']]))


def illustration(m):
    # One person/books or one bird; no keyed response, data point or route encoded.
    title=html.escape(m['alt'])
    if m['part']=='B':
        drawing='<circle cx="175" cy="78" r="30" fill="#b78466"/><path d="M144 72Q143 30 180 43Q208 43 205 76L190 64L160 68Z" fill="#3c3d3a"/><path d="M126 180V130Q128 107 151 105H196Q218 109 223 134V180Z" fill="'+m['colour']+'"/><path d="M146 128L199 151M202 128L161 151" fill="none" stroke="#b78466" stroke-width="15" stroke-linecap="round"/><g stroke="#47605b" stroke-width="2"><rect x="244" y="154" width="112" height="24" rx="3" fill="#d8bc82"/><rect x="252" y="132" width="100" height="21" rx="3" fill="#b8cfc1"/><rect x="240" y="108" width="108" height="23" rx="3" fill="#d5b7a6"/><path d="M251 119H335M263 143H337M257 166H340"/></g>'
    else:
        drawing='<path d="M126 135Q102 118 85 132L118 153Q172 179 232 147Q256 134 268 108Q300 105 293 77Q286 52 259 62Q237 71 237 94Q191 75 150 101Q131 113 126 135Z" fill="'+m['colour']+'" stroke="#47605b" stroke-width="3"/><path d="M148 117Q181 98 220 124Q196 151 163 142Z" fill="#b8cfc1" stroke="#47605b" stroke-width="2"/><circle cx="278" cy="77" r="3" fill="#203c35"/><path d="M294 85L311 92L294 98Z" fill="#d8bc82"/><path d="M186 154L184 183M209 152L213 183M172 184H192M204 184H224" fill="none" stroke="#47605b" stroke-width="3"/>'
    return '<svg xmlns="http://www.w3.org/2000/svg" width="440" height="220" viewBox="0 0 440 220" role="img" aria-labelledby="title desc"><title id="title">'+title+'</title><desc id="desc">Original schematic illustration, not a photograph or research diagram.</desc><rect width="440" height="220" rx="14" fill="#f0f4ee"/><path d="M70 187H370" stroke="#c3d1c6" stroke-width="2"/>'+drawing+'</svg>\n'


def validate(d,s):
    assert s['native14_author_gate']=='grade11_profile_research14_v1' and s['level']==11
    c=s['configuration'];assert c['response_distribution']==[3,4,3,4] and c['responses']==14
    assert c['points_each']==2 and c['selected_objective_points']==28
    assert c['required_lists']==['A.benefits_requirements_and_service_bullet_lists']
    assert c['illustrative_images']==['B.person_photo_with_caption','C.animal_photo_with_caption'] and not c['necessary_images']
    assert d['source_bound_native14_profile_research_section']
    assert [q['operation']for q in d['questions']]==OPERATIONS
    j=d['volunteer_notice'];assert all(len(j[k])==4 for k in ['benefits','requirements','service'])
    assert d['sections'][0]['units']==[notice(j)]
    assert len(re.findall(r'^- ',notice(j),re.M))==12
    assert j['minimum_age_inclusive']==25 and j['minimum_relevant_years_inclusive']==2
    assert j['languages_any_one']==['English','Spanish','French']
    assert j['degree_or_higher_technical_diploma'] and j['no_upper_age_limit']
    assert j['normal_assignment_months']==[6,12] and j['possible_extension_years']==[1,2]
    assert j['allowances_support_living_not_salary']
    for value in ['25 or older','at least two years','English, Spanish or French','six to twelve months','one to two years','not a salary']:
        assert value in notice(j)
    media=d['illustrative_media'];assert [m['part']for m in media]==['B','C']
    assert len({m['asset']['path']for m in media})==2
    assert d['illustrations_replace_photos_not_visual_equivalence']
    for m in media:
        assert m['role']=='illustrative_not_response_coded' and m['caption'] and m['alt']
        assert load_ref(m['asset']).read_text()==illustration(m)
        body=d['sections']['ABCD'.index(m['part'])]['units'][0]
        assert body.count('!['+m['alt']+']('+m['asset']['path']+')')==1
        assert body.count('*'+m['caption']+'*')==1
        assert 'not a photograph' in m['alt']
    assert sum(u.count('![')for sec in d['sections']for u in sec['units'])==2
    assert d['profile_donation_unique_route_evidence'] in d['sections'][1]['units'][0]
    assert d['profile_original_key_not_inherited_as_gold']
    bird=d['bird_study'];assert 0<bird['gps_subset']<bird['observed_total']
    assert bird['gps_subset_of_observed_not_all'] and bird['structure_observation_not_brain_causation']
    C=d['sections'][2]['units'][0]
    for k in ['trigger_evidence','method_evidence','findings_evidence','interpretation_evidence']:assert bird[k] in C and len(bird[k])>20
    assert str(bird['observed_total'])in bird['method_evidence'] and str(bird['gps_subset'])in bird['method_evidence']
    meal=d['meal_study'];D=d['sections'][3]['units'][0];paras=D.split('\n\n');assert len(paras)==7
    assert meal['method_evidence'] in paras[2] and meal['findings_evidence'] in paras[3]
    assert meal['recall_window_hours']==24 and meal['recall_collections_per_person']==1
    assert meal['recall_window_not_daily_frequency'] and meal['observational_not_randomized']
    assert '**'+meal['lexical_target']+'**' in paras[4]
    assert meal['lexical_target'] in d['questions'][11]['stem'] and 'paragraph 5'in d['questions'][11]['stem']
    for k in ['expert_comment_evidence','limitations_evidence','stance_evidence']:
        assert meal[k] in D and len(meal[k])>20
    assert meal['expert_comment_not_experimental_conclusion'] and meal['stance_omission_distinct_from_study_limits']
    assert meal['fictional_lowenergy_association_not_medical_or_mortality_evidence']
    assert d['fictional_research_and_programme_not_real_rules_or_health_advice']
    assert len(d['answer_evidence'])==14
    for q,e in zip(d['questions'],d['answer_evidence']):
        assert e['number']==q['number'] and e['best_text']==dict(q['options'])[q['answer']]
        assert len(e['evidence'])>20 and e['evidence'] in d['sections']['ABCD'.index(q['materialLabel'])]['units'][0]
    return True


def check_rendered(g,a,d):
    assert a['source_bound_native14_profile_research_section']
    for k in ['volunteer_notice','illustrative_media','bird_study','meal_study','answer_evidence']:assert a[k]==d[k]
    assert g['passageHtml'].count('<ul class="reading-requirements">')==3
    assert g['passageHtml'].count('<li>')==12
    images=g['requiredPassageImages'];assert len(images)==2
    assert g['passageHtml'].count('<figcaption>')==2
    for image,m in zip(images,d['illustrative_media']):
        assert image['asset']==m['asset'] and (image['width'],image['height'])==(440,220)
        assert image['alt']==m['alt'] and m['caption'] in html.unescape(g['passageHtml'])
        assert '<figcaption>'+html.escape(m['caption'])+'</figcaption>' in g['passageHtml']
        assert '*'+m['caption']+'*' not in g['passageHtml']
        assert hashlib.sha256(base64.b64decode(image['src'].split(',',1)[1])).hexdigest()==m['asset']['sha256']
    load=a['load_measure'];assert load['notice_bullet_entries']==12 and load['illustrative_images']==2
    assert load['image_caption_English_words']>0 and load['image_alt_English_words']>0
    assert load['image_markup_and_captions_excluded_from_body']
    return True
