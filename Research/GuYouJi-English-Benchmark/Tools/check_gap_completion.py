"""Check the direct follow-up without weakening prior frozen-source checks."""
import hashlib
import json
import re
import base64
from itertools import product
from grade_mode_evidence import load_ref
from quality_review_contract import response_markdown


def words(text):
    return len(re.findall(r"[A-Za-z]+(?:['’][A-Za-z]+)?", text))


def check(data, plan):
    if not plan.get('current_gap_completion'):
        return {'groups': 0, 'responses': 0}
    index = json.loads(load_ref(plan['current_gap_completion']).read_text())
    assert data['gap_completion_index'] == plan['current_gap_completion']
    seen = set()
    for meta in index['candidates']:
        assert meta['id'] not in seen
        seen.add(meta['id'])
        g = data['groups'][meta['id']]
        a = json.loads(load_ref(meta['author_check']).read_text())
        text = load_ref(meta['candidate']).read_text()
        bindings = json.loads(load_ref(a['source_bindings']).read_text())
        b = next(b for b in bindings['bindings'] if b['id'] == a['source_binding'])
        if b.get('source_index'):
            source = next(s for s in json.loads(load_ref(b['source_index']).read_text())[b['collection']] if s['id'] == b['source_group_id'])
            assert hashlib.sha256(json.dumps(source, sort_keys=True, ensure_ascii=False).encode()).hexdigest() == b['source_record_sha256']
            for key in ['references', 'source_images', 'visuals']:
                for reference in source.get(key, []):
                    load_ref(reference)
            for key in ['source', 'source_html', 'key_reference', 'key_visual']:
                if source.get(key):
                    load_ref(source[key])
            assert source.get('responses',len(source.get('question_numbers',[]))) == b['responses']
            assert source.get('level',source.get('grade')) == b['level']
            if b.get('source_view'):
                view=next(v for v in json.loads(load_ref(b['source_view']).read_text())['views'] if v['group_id']==b['source_group_id'])
                load_ref(view['parent_document'])
                assert source['complete_selected_group_reviewed']
                if view.get('response_slots'):
                    assert source['features']['subgroup_slots']==b['subgroup_counts']
                    assert [len(m['blank_numbers']) for m in view['materials']]==b['subgroup_counts']
                    assert b['given_positions']==[slot['ordinal'] for slot in view['response_slots'] if slot['given_hint']]
                    assert [slot['word_limit'] for slot in view['response_slots']]==[None if i in b['given_positions'] else 1 for i in range(1,b['responses']+1)]
                else:
                    assert source['features']['materials']==1
                    assert b['given_positions']==[n-55 for n in view['source_policy']['given_word_numbers']]
                assert a['subgroup_counts']==b['subgroup_counts']
                assert a['given_positions']==b['given_positions']
        else:
            inherited = json.loads(load_ref(b['source_author_audit']).read_text())
            assert inherited['questions'] == b['responses'] == 4
            for key in ['parent_document', 'transcription']:
                load_ref(b['source_reference'][key])
        assert b['new_source_count'] == a['source_count_increment'] == 0
        assert b['source_original_key_not_gold']
        assert b['source_group_id'] in g['anchor_group_ids']
        assert g['grade'] == a['grade'] == b['level'] == meta['grade']
        assert g['kind'] == b['family'] == meta['family']
        assert g['instruction'] == meta['instruction'] and g['sourceFormNotice'] == meta['source_form_notice']
        if meta.get('format_summary'):
            assert g['formatSummary']==meta['format_summary']
        assert g['questions'] == a['review_response_tasks']
        assert len(g['questions']) == b['responses'] == a['questions'] == meta['questions']
        assert [len(q['options']) for q in g['questions']] == [b['options_each']] * b['responses']
        assert a['authored_student_inputs_complete'] and not a['independent_teacher_student_commercial_production_validated']
        assert meta['candidate']['sha256'] == a['candidate_sha256']
        printed = text.split('<!-- responses:start -->')[1].split('<!-- responses:end -->')[0].strip()
        assert printed == response_markdown(g['questions'])
        assert hashlib.sha256(printed.encode()).hexdigest() == a['canonical_response_block_sha256']
        assert a['student_passage'] in text
        load = a['load_measure']
        assert load['body_English_words'] == words(a['student_passage'])
        assert load['stem_English_words'] == sum(words(q['stem']) for q in g['questions'])
        assert load['options_English_words_with_repeated_bank'] == sum(words(t) for q in g['questions'] for _, t in q['options'])
        assert load['output_response_positions'] == len(g['questions'])
        for q in g['questions']:
            assert q['rationale']
            if q['options']:
                assert q['answer'] in dict(q['options'])
                assert len(set(k for k, _ in q['options'])) == b['options_each']
            else:
                assert q['acceptedAnswers'] and len(set(q['acceptedAnswers'])) == len(q['acceptedAnswers'])
                c = q['fillMarking']
                assert c['review'] == 'author_context_checked' and c['version'] == 1
                expected_protocol='english_phrase_v1' if a.get('mixed_given_ungiven_grammar') else 'ascii_integer_v1' if meta['family']=='number_word_completion' else 'latin_word_v1'
                assert c['normalization'] == expected_protocol
                assert c['unlisted'] == ('different' if meta['family'] == 'number_word_completion' else 'review')
                assert not set(c['rejectedAnswers']) & set(q['acceptedAnswers'])
                pattern='[0-9]+' if c['normalization']=='ascii_integer_v1' else '[A-Za-z]+(?: [A-Za-z]+)*' if c['normalization']=='english_phrase_v1' else '[A-Za-z]+'
                assert all(re.fullmatch(pattern, value) for value in q['acceptedAnswers'] + c['rejectedAnswers'])
                if a.get('mixed_given_ungiven_grammar'):
                    assert c['maxWords']==(None if q['number'] in b['given_positions'] else 1)
                    assert bool(q['givenLemma'])==(q['number'] in b['given_positions'])
                    assert all(c['maxWords'] is None or len(value.split())<=c['maxWords'] for value in q['acceptedAnswers'])
        if a.get('mixed_given_ungiven_grammar'):
            assert re.findall(r'\((\d+)\) ____',a['student_passage'])==[str(i) for i in range(1,11)]
            assert '____' not in a['filled_passage']
            assert a['full_fill_variant_combinations']==__import__('math').prod(len(q['acceptedAnswers']) for q in g['questions'])
        if a.get('figure_asset'):
            raw = load_ref(a['figure_asset']).read_bytes()
            assert len(g['requiredPassageImages']) == 1
            assert base64.b64decode(g['requiredPassageImages'][0]['src'].split(',', 1)[1]) == raw
            assert b'<script' not in raw and b'<image' not in raw
        if meta['family'] == 'word_picture_choice':
            assert a['visual_panels'] == 18
            for q, row in zip(g['questions'], a['visual_candidate_objects']):
                assert q['answer'] == 'ABC'[row['candidate_objects'].index(row['word'])]
        if meta['family'] == 'word_picture_matching':
            for q in g['questions']:
                assert q['answer'] == 'ABCD'[a['visual_objects'].index(q['stem'])]
        if meta['family'] == 'picture_sentence_choice':
            assert a['visual_panels'] == 5
            for q, scene in zip(g['questions'], a['visual_semantics']):
                assert dict(q['options'])[q['answer']] == scene['correct_sentence']
        if meta['family'] == 'dialogue_matching':
            assert a['source_reuse'] == 'not_explicit' and '只用一次' in meta['instruction']
            assert '不额外规定' in meta['instruction']
            assert all(q['options'] == g['questions'][0]['options'] for q in g['questions'])
        if meta['family'] == 'passage_form' and meta['grade']=='advanced':
            assert a['one_derived_word'] and a['answered_examples'] == 1
            assert re.findall(r'\((\d+)\) ____', a['student_passage']) == list('12345678')
            assert '(0)' in a['student_passage']
            load_ref(a['lexical_evidence'])
            assert a['fully_filled_passage'] and '____' not in a['fully_filled_passage']
            # Exercise every allowed combination, not just the first answer vector.
            # The structural check does not assert linguistic truth/independence.
            variants = 0
            for answers in product(*(q['acceptedAnswers'] for q in g['questions'])):
                filled = a['student_passage']
                for i, value in enumerate(answers, 1):
                    filled = filled.replace('('+str(i)+') ____', '('+str(i)+') '+value)
                assert '____' not in filled and all(value in filled for value in answers)
                variants += 1
            assert variants == a['full_fill_variant_combinations_context_reviewed']
    assert len(seen) == index['new_complete_groups']
    assert sum(m['questions'] for m in index['candidates']) == index['new_response_positions']
    return {'groups': len(seen), 'responses': index['new_response_positions'], 'new_sources': 0,
            'accepted_forms_bound': True, 'unlisted_lexical_forms_need_review': True,
            'teacher_student_commercial_production_verified': False}
