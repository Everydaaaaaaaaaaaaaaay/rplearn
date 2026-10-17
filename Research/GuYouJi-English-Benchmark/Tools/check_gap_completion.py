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
            if b.get('task_mode') == 'lowprimary_lexical_listening':
                from compile_lowprimary_lexical_listening import check as check_lowprimary_lexical
                check_lowprimary_lexical(g,a,b,source)
            if b.get('task_mode') == 'shop_grid_reading':
                from compile_shop_grid_reading import check as check_shop_grid
                check_shop_grid(g,a,b,source)
            if b.get('task_mode') == 'senior_short_source_bound_listening':
                from compile_senior_short_listening import check as check_senior_short
                check_senior_short(g,a,b,source)
            if b.get('task_mode') == 'junior_source_bound_listening':
                from compile_junior_listening import check as check_junior_listening
                check_junior_listening(g,a,b,source)
            if b.get('task_mode') == 'controlled_sentence_transformation':
                from compile_controlled_transformations import check as check_transformations
                check_transformations(g,a,b,source)
            if b.get('task_mode') == 'academic_form_listening':
                from compile_academic_form_listening import check as check_academic_form
                check_academic_form(g,a,b,source)
            if b.get('task_mode') == 'academic_bundle_listening':
                from compile_academic_bundle_listening import check as check_academic_bundle
                check_academic_bundle(g,a,b,source)
            if b.get('task_mode') == 'academic_shared_audio_matching':
                from compile_academic_audio_matching import check as check_academic_audio_matching
                check_academic_audio_matching(g,a,b,source)
            if b.get('task_mode') == 'academic_information_tristate':
                from compile_academic_information import check as check_academic_information
                check_academic_information(g,a,b,source)
            if b.get('task_mode') == 'cambridge_additional_academic_modes':
                from compile_cambridge_additional import check as check_cambridge_additional
                check_cambridge_additional(g,a,b,source)
            if b.get('task_mode') == 'academic_summary_or_diagram':
                from compile_academic_visual import check as check_academic_visual
                check_academic_visual(g,a,b,source)
            if b.get('task_mode') == 'academic_text_extraction':
                from compile_academic_text_extraction import check as check_academic_text_extraction
                check_academic_text_extraction(g,a,b,source)
            if b.get('task_mode') == 'academic_reading_choice_sets':
                from compile_academic_choice_sets import check as check_academic_choice_sets
                check_academic_choice_sets(g,a,b,source)
            if b.get('task_mode') == 'academic_shared_pairing':
                from compile_academic_pairing import check as check_academic_pairing
                check_academic_pairing(g,a,b,source)
            if b.get('task_mode') == 'academic_extracted_completion':
                from compile_academic_extraction import check as check_academic_extraction
                check_academic_extraction(g,a,b,source)
            if b.get('task_mode') == 'academic_matching_features':
                from compile_academic_features import check as check_academic_features
                check_academic_features(g,a,b,source)
            if b.get('task_mode') == 'inherited_cet_reading':
                from compile_inherited_reading import check as check_inherited_reading
                check_inherited_reading(g,a,b,source)
            if b.get('task_mode') == 'inherited_shared_five':
                from compile_inherited_shared import check as check_inherited_shared
                check_inherited_shared(g,a,b,source)
            if b.get('task_mode') == 'inherited_complete_cloze':
                from compile_inherited_cloze import check as check_inherited_cloze
                check_inherited_cloze(g,a,b,source)
            if b.get('task_mode') in {'primary_dialogue_pictures5','primary_dialogue_pictures6','primary_dialogue_rank_pictures5'}:
                from compile_dialogue_picture_matching import check as check_dialogue_pictures
                check_dialogue_pictures(g,a,b,source)
            if b.get('task_mode') == 'primary_whole_five_three_pass':
                from compile_primary_whole_listening import check as check_primary_whole
                check_primary_whole(g,a,b,source)
            if b.get('task_mode') == 'primary_wordphrase10twice':
                from compile_word_listening import check as check_word_listening
                check_word_listening(g,a,b,source)
            if b.get('task_mode') == 'sequence_table_listening':
                from compile_sequence_table_listening import check as check_sequence_table
                check_sequence_table(g,a,b,source)
            if b.get('task_mode') == 'shared_picture_listening':
                from compile_shared_picture_listening import check as check_shared_picture
                check_shared_picture(g,a,b,source)
            if b.get('task_mode') == 'illustrated_listening':
                from compile_illustrated_listening import check as check_illustrated
                check_illustrated(g,a,b,source)
            if b.get('task_mode') == 'primary_passageTF5':
                from compile_primary_passage_listening import check as check_primary_passage
                check_primary_passage(g,a,b,source)
            if b.get('task_mode') in {'primary_pictureTF10','primary_pictureTF9','primary_pictureTF5'}:
                from compile_picture_listening import check as check_picture_listening
                check_picture_listening(g,a,b,source)
            if b.get('task_mode') == 'primary_dialogue122':
                from compile_primary_dialogue_listening import check as check_primary_listening
                check_primary_listening(g,a,b,source)
            if b.get('task_mode') == 'source_bound_multi_question_listening':
                from compile_multi_question_listening import check as check_multi_listening
                check_multi_listening(g,a,b,source)
            if b.get('task_mode') == 'ordinary_short_dialogues5once':
                from compile_short_dialogue_listening import check as check_short_listening
                check_short_listening(g,a,b,source)
            if b.get('task_mode') == 'publisher_conversation_tf4':
                from compile_school_listening import check as check_school_listening
                check_school_listening(g,a,b,source)
            if b.get('task_mode') == 'bounded_source_prompt_completion':
                view=next(v for v in json.loads(load_ref(source['source_view_manifest']).read_text())['views']if v['group_id']==source['id'])
                assert hashlib.sha256(json.dumps(view,ensure_ascii=False,sort_keys=True).encode()).hexdigest()==source['inherited_view_record_sha256']
                raw=load_ref(view['source_text']).read_text()
                for component in view['components']+view['material_segments']:
                    fragment=raw[component['start_offset']:component['end_offset']]
                    assert hashlib.sha256(fragment.encode()).hexdigest()==component['sha256']
                instruction=next(c for c in view['components']if c['role']=='student_instruction')
                assert instruction['sha256']==source['instruction_sha256']
                given=[c.get('item_id')for c in view['components']if c['role']=='given_form_hint']
                assert given==source['given_positions']==a['given_positions']
                assert a['bounded_source_prompt_completion'] and a['source_count_increment']==0
                assert len(view.get('items',view.get('units',[])))==b['responses']
                if b['family']=='sentence_form':
                    assert given==[2,3,5,6,7,8,10,11,13,14] and b['responses']==15
                    assert all(q['fillMarking']['maxWords']==(None if q['number']in given else 1)for q in a['review_response_tasks'])
                else:
                    assert all(q['fillMarking']['maxWords']==source.get('maximum_words_each') for q in a['review_response_tasks'])
                if source.get('mixed_chinese_initial_eight'):
                    assert b['responses']==8 and source['Chinese_hint_positions']==[1,2,3,4] and source['initial_hint_positions']==[5,6,7,8]
                    assert [c['item_id']for c in view['components']if c['role']=='Chinese_hint_or_gloss']==source['Chinese_hint_positions']
                    assert [i['ordinal']for i in view['items']if i['visible_blanks'][0]['printed_initial']is not None]==source['initial_hint_positions']
                    for q in a['review_response_tasks']:
                        hint=re.search(r'([A-Za-z])____',q['stem'])
                        assert (hint is not None)==(q['number']in source['initial_hint_positions'])
                        assert q['fillMarking'].get('requiredInitial')==(hint[1]if hint else None)
                if b['family']=='passage_chinese_completion':
                    assert re.findall(r'\((\d+)\) ____',a['student_passage'])==[str(n)for n in range(1,11)]
                    assert '____'not in a['filled_passage']
                assert a['full_fill_variant_combinations']==__import__('math').prod(len(q['acceptedAnswers'])for q in a['review_response_tasks'])
                for q,row in zip(a['review_response_tasks'],a['full_slot_substitutions']):
                    frame=a['student_passage']if b['family']=='passage_chinese_completion'else q['stem']
                    filled=[frame.replace('('+str(q['number'])+') ____',v)if b['family']=='passage_chinese_completion'else re.sub(r'[a-z]?____',v,frame,count=1)for v in q['acceptedAnswers']]
                    assert row['accepted_full_inputs']==filled and row['number']==q['number']
            if b.get('task_mode') == 'complete_root_word_bank':
                view=next(v for v in json.loads(load_ref(source['source_view_manifest']).read_text())['views']if v['group_id']==source['id'])
                assert hashlib.sha256(json.dumps(view,ensure_ascii=False,sort_keys=True).encode()).hexdigest()==source['inherited_view_record_sha256']
                if b['level']==7:
                    raw=json.loads(load_ref(view['snapshot']).read_text())['native_pages_private'][view['page_pointer'][-1]]
                    assert hashlib.sha256(raw.encode()).hexdigest()==view['native_page_sha256']
                    instruction=raw[view['student_instruction']['start_offset']:view['student_instruction']['end_offset']]
                    original_bank=view['shared_bank']['entries']
                    pair=view['alternative_choice'];assert pair['required_choice_count']==1 and pair['mandatory_responses_across_pair']==10
                    assert not view['strict_no_form_change_explicit']
                    assert view['form_change_explicit']==(source['form_policy']=='change')
                    if source['form_policy']=='not_explicit':
                        assert '未明确' in meta['instruction'] and '不得变形' not in meta['instruction']
                        assert all(q['fillMarking']['unlisted']=='review' for q in a['review_response_tasks'])
                else:
                    raw=load_ref(view['source_text']).read_text()
                    component=next(c for c in view['components']if c['role']=='student_instruction')
                    instruction=raw[component['start_offset']:component['end_offset']]
                    assert hashlib.sha256(instruction.encode()).hexdigest()==component['sha256']
                    original_bank=view['source_bank_entries_observed']
                    body=raw[view['start_offset']:view['end_offset']]
                    assert hashlib.sha256(body.encode()).hexdigest()==view['material_sha256']
                    assert [int(n)for n in re.findall(r'_{3,}(\d+)_{3,}',body)]==view['expected_blank_ids']
                    assert len(view['expected_blank_ids'])==10
                assert '只用一次' in instruction or '仅用一次' in instruction or '限用一次' in instruction
                assert len(original_bank)==source['entries']==len(a['bank_entries'])
                assert source['responses']==10 and a['word_bank_completion'] and source['materials']==1
                assert source['form_policy']==a['form_policy'] and source['max_words_each']==a['max_words_each']
                if b['level']==8: assert '每空仅填一词' in instruction and a['max_words_each']==1
                else: assert a['max_words_each'] is None
                assert a['reuse_rule']==source['reuse_rule']=='once'
                assert len(a['used_root_entries'])==len(set(a['used_root_entries']))==10
                assert set(a['used_root_entries'])<=set(a['bank_entries'])
                assert a['unused_root_entries']==[r for r in a['bank_entries']if r not in a['used_root_entries']]
                assert len(a['unused_root_entries'])==(2 if b['level']==9 else 0)
                assert [q['bankEntry']for q in a['review_response_tasks']]==a['used_root_entries']
                assert all(q['bankReuse']=='once'for q in a['review_response_tasks'])
                forms=[v.casefold()for q in a['review_response_tasks']for v in q['acceptedAnswers']]
                assert len(forms)==len(set(forms)), 'Reference forms cannot silently map to two different reused roots'
                assert all(q['fillMarking']['maxWords']==a['max_words_each']for q in a['review_response_tasks'])
                assert a['load_measure']['word_bank_English_words_once']==sum(words(v)for v in a['bank_entries'])
                assert a['full_fill_variant_combinations']==__import__('math').prod(len(q['acceptedAnswers'])for q in a['review_response_tasks'])
                assert re.findall(r'\((\d+)\) ____',a['student_passage'])==[str(n)for n in range(1,11)]
                assert '____' not in a['filled_passage']
            if b.get('task_mode') == 'listening_sentence_completion8':
                selected=json.loads(load_ref(source['selected_native']).read_text())
                assert selected['paper']==source['source'] and selected['paper_page']==4
                assert re.findall(r'\((\d+)\)',selected['student_task'])==[str(n)for n in range(7,15)]
                assert 'a word or short phrase' in ' '.join(selected['student_task'].split())
                assert source['features']==b['source_features'] and source['features']['no_numeric_max_words']
                assert len(selected['published_key_forms'])==8 and 'Josh Brady' in selected['script']
                assert selected['source_audio']==source['original_audio_assets'][0]
                load_ref(selected['source_audio']);load_ref(selected['source_audio_decode'])
                from compile_sentence_completion_listening import check as check_listenfill
                check_listenfill(g,a,b,source)
            if b.get('task_mode') == 'junior_mixed10_bound_positions':
                view=next(v for v in json.loads(load_ref(source['source_view_manifest']).read_text())['views'] if v['group_id']==source['id'])
                assert hashlib.sha256(json.dumps(view,ensure_ascii=False,sort_keys=True).encode()).hexdigest()==source['inherited_view_record_sha256']
                load_ref(source['source_catalogue'])
                if b['level']==7:
                    raw=load_ref(view['source_text']).read_text()
                    body=raw[view['start_offset']:view['end_offset']]
                    assert hashlib.sha256(body.encode()).hexdigest()==view['material_sha256']
                    numbers=view['expected_blank_ids']
                    hinted=[n for n,hint in re.findall(r'_{3,}(\d+)_{3,}\s*(?:\(([^)]+)\))?',body) if hint]
                    given=[int(n)-numbers[0]+1 for n in hinted]
                    assert given==[n-numbers[0]+1 for n in view['observed_given_hint_slots']]
                    component=next(c for c in view['components']if c['role']=='student_instruction')
                    instruction=raw[component['start_offset']:component['end_offset']]
                    assert hashlib.sha256(instruction.encode()).hexdigest()==component['sha256']
                else:
                    record=json.loads(load_ref(view['transcription']).read_text())['records'][view['record_index']]
                    assert record['id']==source['id']
                    instruction=next(c['text']for c in record['components']if c['role']=='instruction')
                    hints=[c['item_id']for c in record['components']if c['role']=='given_hint']
                    numbers=source['source_question_numbers']
                    given=[n-numbers[0]+1 for n in hints]
                    for asset in view['source_images']: load_ref(asset)
                assert re.search('[1一]个适当的单词',instruction) and '括号内单词的正确形式' in instruction
                assert numbers==source['source_question_numbers'] and len(numbers)==10
                assert given==b['given_positions']==source['given_positions']==a['given_positions']
                assert len(given)==7 and source['ungiven_max_words']==1 and source['given_max_words'] is None
                assert a['mixed_given_ungiven_grammar'] and a['subgroup_counts']==[10]
            if b.get('task_mode') == 'keyword_transformation_six3to6':
                selected=json.loads(load_ref(source['selected_native']).read_text())
                assert selected['original']==source['source'] and selected['key']==source['key_reference']
                raw=' '.join(' '.join(selected['selected_task_pages']).split())
                assert 'between three and six words' in raw and 'Do not change the word given.' in raw
                assert re.findall(r'^\s*(2[5-9]|30)\s', '\n'.join(selected['selected_task_pages']), re.M)==[str(n)for n in range(25,31)]
                assert b['source_features']==source['features']
                assert a['keyword_transformation'] and a['worked_examples']==1 and a['worked_example_count']==4
                assert len(a['transformation_rows'])==b['responses']==6
                for row,q in zip(a['transformation_rows'],a['review_response_tasks']):
                    assert row['number']==q['number'] and row['target_frame'].count('____')==1
                    assert row['keyword']==q['fillMarking']['requiredWord']
                    assert q['fillMarking']['minWords']==3 and q['fillMarking']['maxWords']==6
                    assert q['fillMarking']['wordCountAmbiguity']=='review'
                    assert row['word_counts']==[len(v.split())for v in q['acceptedAnswers']]
                    assert all(3<=n<=6 for n in row['word_counts'])
                    assert all(row['keyword'].lower() in v.lower().split() for v in q['acceptedAnswers'])
                    assert row['accepted_full_sentences']==[row['target_frame'].replace('____',v)for v in q['acceptedAnswers']]
                    assert row['scoring_segments_count']==len(row['reference_scoring_segments'])==2
                    assert ' '.join(row['reference_scoring_segments'])==q['acceptedAnswers'][0]
                    assert row['lead_in'] in a['student_passage'] and row['target_frame'] in a['student_passage']
            if b.get('task_mode') == 'single_passage_mixed_grammar_slot_exceptions':
                selected=json.loads(load_ref(source['selected_native']).read_text())
                raw=selected['student_grammar']
                assert selected['original']==source['source_html']
                assert source['complete_selected_group_reviewed'] and source['kind']==b['family']=='passage_form'
                slots=re.findall(r'_{3,}(\d+)_{3,}\s*(?:\(([^)]+)\))?', raw)
                assert [int(n)for n,_ in slots]==source['source_question_numbers']
                assert [i for i,(_,hint)in enumerate(slots,1)if re.fullmatch('[A-Za-z]+',hint)]==b['given_positions']
                assert b['slot_rules']==source['slot_rules']==a['slot_rules']
                assert source['responses']==b['responses']==10 and source['materials']==1
                assert 'use one word that best fits each blank' in ' '.join(raw.split())
                for i,(_,hint)in enumerate(slots,1):
                    exception=re.fullmatch(r'填(\d+)词',hint)
                    rule=b['slot_rules'][i-1]
                    if exception:
                        assert rule['exact_words']==int(exception[1])==2 and rule['kind']=='word_count_exception'
                        assert '(10) ____ (填2词)' in a['student_passage']
                    elif hint:
                        assert rule['kind']=='given_lemma' and rule['max_words'] is None
                    else:
                        assert rule['kind']=='ungiven_one_word' and rule['max_words']==1
            if b.get('task_mode') == 'four_of_six_sentence_insertion':
                selected=json.loads(load_ref(source['selected_native']).read_text())
                raw=selected['selected_student_insertion']
                assert selected['original']==source['source_html']
                assert source['complete_selected_group_reviewed'] and source['kind']==b['family']=='shared_insertion'
                assert [int(n) for n in re.findall(r'_{3,}(\d+)_{3,}',raw)]==source['source_question_numbers']
                source_options=re.findall(r'^([A-F])[.．]\s*(.+)$',raw,re.M)
                assert [label for label,_ in source_options]==list('ABCDEF')
                assert source['responses']==b['responses']==4 and b['options_each']==6
                assert source['reuse_rule']==b['reuse_rule']==a['source_reuse_rule']
                if b['reuse_rule']=='once_explicit':
                    assert 'Each sentence can be used only once.' in raw
                    assert 'two more sentences than you need' in raw
                    assert len(set(q['answer']for q in g['questions']))==4
                else:
                    assert b['reuse_rule']=='not_visible_not_inferred'
                assert re.findall(r'\((\d+)\) ____',a['student_passage'])==list('1234')
                assert all(q['options']==a['shared_candidates'] for q in g['questions'])
                assert a['shared_candidates_unique']==6 and len(a['choice_pair_audit'])==24
                assert {(r['response_number'],r['candidate'])for r in a['choice_pair_audit']}=={(n,c)for n in range(1,5)for c in 'ABCDEF'}
                assert all(r['is_best']==(g['questions'][r['response_number']-1]['answer']==r['candidate']) and r['reason'] for r in a['choice_pair_audit'])
                assert load_ref(meta['candidate']).read_text().count('### 共享候选')==1
                assert a['load_measure']['options_English_words_unique_bank']==sum(words(t)for _,t in a['shared_candidates'])
                assert a['subgroup_counts']==[4] and a['materials']==1 and '____' not in a['filled_passage']
            if b.get('task_mode') == 'one_word_open_cloze':
                assert source['complete_selected_group_reviewed'] and source['kind']==b['family']=='open_cloze'
                selected=json.loads(load_ref(source['selected_native']).read_text())
                assert selected['original']==source['source'] and selected['key']==source['key_reference']
                assert selected['physical_page']==source['source_physical_pages'][0]==4
                assert 'For questions 9' in selected['selected_task_text']
                assert 'Use only one word in each gap.' in ' '.join(selected['selected_task_text'].split())
                assert len(selected['original_key_forms'])==8 and all(selected['original_key_forms'])
                assert source['features']==b['source_features']=={'materials':1,'solved_examples':1,'responses':8,'hints':0,'word_limit_each':1,'shared_candidates':0}
                assert a['one_word_open_cloze'] and a['answered_examples']==1
                assert re.findall(r'\((\d+)\) ____', a['student_passage'])==list('12345678')
                assert '(0)' in a['student_passage'] and '____' not in a['filled_passage']
                assert a['subgroup_counts']==[8] and a['given_positions']==[]
            if b.get('source_view') and b.get('task_mode') != 'inherited_shared_five':
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
        assert b.get('source_original_key_not_gold') or (b.get('source_script_audio_and_key_missing') and source.get('source_key_acquired') is False)
        assert b['source_group_id'] in g['anchor_group_ids']
        assert g['grade'] == a['grade'] == b['level'] == meta['grade']
        assert g['kind'] == b['family'] == meta['family']
        assert g['instruction'] == meta['instruction'] and g['sourceFormNotice'] == meta['source_form_notice']
        if meta.get('format_summary'):
            assert g['formatSummary']==meta['format_summary']
        if a.get('illustrated_listening'):
            from quality_review_images import check_option_images,without_derived_images
            check_option_images(g)
            assert without_derived_images(g['questions'])==a['review_response_tasks']
        else:
            assert g['questions'] == a['review_response_tasks']
        assert len(g['questions']) == b['responses'] == a['questions'] == meta['questions']
        assert [len(q['options']) for q in g['questions']] == (b['options_per_response'] if a.get('academic_multi_response_multi_select') else [b['options_each']] * b['responses'])
        assert a['authored_student_inputs_complete'] and not a['independent_teacher_student_commercial_production_validated']
        assert meta['candidate']['sha256'] == a['candidate_sha256']
        printed = text.split('<!-- responses:start -->')[1].split('<!-- responses:end -->')[0].strip()
        assert printed == response_markdown(g['questions'])
        assert hashlib.sha256(printed.encode()).hexdigest() == a['canonical_response_block_sha256']
        assert a['student_passage'] in text
        load = a['load_measure']
        assert load['body_English_words'] == words(a['body_load_text'] if a.get('lowprimary_lexical_listening') or a.get('shop_grid_reading') or a.get('academic_form_listening') or a.get('academic_bundle_listening') or a.get('academic_shared_audio_matching') or a.get('listening_sentence_completion') or a.get('publisher_listening_true_false') or a.get('short_dialogue_listening') or a.get('multi_question_listening') or a.get('primary_dialogue_listening') or a.get('picture_listening') or a.get('word_phrase_listening') or a.get('primary_whole_listening') or a.get('dialogue_picture_matching') or a.get('junior_source_bound') or a.get('senior_short_source_bound') or a.get('primary_passage_listening') or a.get('illustrated_listening') or a.get('shared_picture_listening') or a.get('sequence_table_listening') else a['student_passage'])
        assert load['stem_English_words'] == sum(words(q['stem']) for q in g['questions'])
        assert load['options_English_words_with_repeated_bank'] == sum(words(t) for q in g['questions'] for _, t in q['options'])
        assert load['output_response_positions'] == len(g['questions'])
        for q in g['questions']:
            assert q['rationale']
            if q['options']:
                assert q['answer'] in dict(q['options'])
                assert len(set(k for k, _ in q['options'])) == (b['options_per_response'][q['number']-1] if a.get('academic_multi_response_multi_select') else b['options_each'])
            else:
                assert q['acceptedAnswers'] and len(set(q['acceptedAnswers'])) == len(q['acceptedAnswers'])
                c = q['fillMarking']
                assert c['review'] == 'author_context_checked' and c['version'] == 1
                expected_protocol='english_phrase_v1' if a.get('mixed_given_ungiven_grammar') or a.get('one_word_open_cloze') or a.get('keyword_transformation') or a.get('listening_sentence_completion') or a.get('word_bank_completion') or a.get('bounded_source_prompt_completion') or a.get('primary_whole_listening') or a.get('junior_source_bound') or a.get('controlled_sentence_transformation') else 'ascii_integer_v1' if meta['family']=='number_word_completion' else 'latin_word_v1'
                if meta['family']=='listening_table_completion' and a.get('junior_source_bound'):
                    if meta['grade']==7 and q['number'] in [1,4]:expected_protocol='small_count_v1'
                    elif meta['grade']==9 and q['number']==1:expected_protocol='clock_hour_v1'
                if a.get('academic_bundle_listening') or a.get('academic_extracted_completion') or a.get('academic_text_extraction') or a.get('academic_summary_or_diagram'):expected_protocol='source_excerpt_v1'
                if a.get('cambridge_additional_academic'):
                    expected_protocol='source_list_v1' if q['number']==2 else 'source_excerpt_v1'
                if a.get('academic_form_listening'):expected_protocol={3:'uk_postcode_v1',4:'metric_length_v1',5:'metric_length_v1',8:'sterling_amount_v1'}.get(q['number'],'source_excerpt_v1')
                if a.get('note_table_structure') and q['number']==9:expected_protocol='sterling_amount_v1'
                assert c['normalization'] == expected_protocol
                assert c['unlisted'] == ('different' if meta['family'] == 'number_word_completion' else 'review')
                assert not set(c['rejectedAnswers']) & set(q['acceptedAnswers'])
                pattern='(?:[0-9]{1,2}(?:[:.][0-9]{2})?|[A-Za-z]+)' if c['normalization']=='clock_hour_v1' else '(?:[0-9]+|[A-Za-z]+)' if c['normalization']=='small_count_v1' else '[0-9]+' if c['normalization']=='ascii_integer_v1' else "[A-Za-z]+(?:['’-][A-Za-z]+)*(?: [A-Za-z]+(?:['’-][A-Za-z]+)*)*" if c['normalization']=='english_phrase_v1' else '[A-Za-z]+'
                if c['normalization']=='source_excerpt_v1':pattern="[A-Za-z0-9]+(?:['-][A-Za-z0-9]+)*(?: [A-Za-z0-9]+(?:['-][A-Za-z0-9]+)*)*"
                if c['normalization']=='source_list_v1':pattern='[A-Za-z]+(?: [A-Za-z]+)*'
                if c['normalization']=='uk_postcode_v1':pattern='[A-Z]{1,2}[0-9][A-Z0-9]? [0-9][A-Z]{2}'
                if c['normalization']in {'metric_length_v1','sterling_amount_v1'}:pattern='[A-Za-z0-9£½¾][A-Za-z0-9£½¾.,/ -]*'
                assert all(re.fullmatch(pattern, value) for value in q['acceptedAnswers'] + c['rejectedAnswers'])
                if c['normalization']=='small_count_v1':
                    names='zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty'.split()
                    value=c['wholeCount'];assert type(value)is int and 0<=value<=20
                    assert c['unknownSyntax']=='review' and c['maxWords']==1
                    assert set(q['acceptedAnswers'])=={str(value),names[value]}
                if a.get('one_word_open_cloze'):
                    assert c['maxWords']==1 and all(len(v.split())==1 for v in q['acceptedAnswers'])
                if a.get('mixed_given_ungiven_grammar'):
                    rule=b.get('slot_rules',[None]*b['responses'])[q['number']-1]
                    assert c['maxWords']==(rule['max_words'] if rule else None if q['number'] in b['given_positions'] else 1)
                    if rule and rule['kind']=='word_count_exception':
                        assert c['minWords']==rule['exact_words']==c['maxWords']==2
                        assert c['wordCountAmbiguity']=='review' and not q['givenLemma']
                        assert all(len(value.split())==2 for value in q['acceptedAnswers'])
                    else:
                        assert 'minWords' not in c
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
            if a.get('inherited_shared_five'):
                assert b['reuse_rule']=='not_explicit' and '不额外限制' in meta['instruction']
            else:
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
    selected_modes = json.loads(load_ref(plan['current_complete_coverage_source_modes']).read_text()) if plan.get('current_complete_coverage_source_modes') else {}
    return {'groups': len(seen), 'responses': index['new_response_positions'],
            'new_sources': selected_modes.get('new_source_papers', 0),
            'new_sources_count_scope': selected_modes.get('source_parent_count_scope', 'no_new_source_parents'),
            'new_source_papers': selected_modes.get('new_source_papers', 0),
            'new_selected_specific_modes': selected_modes.get('new_selected_specific_modes', 0),
            'accepted_forms_bound': True, 'unlisted_lexical_forms_need_review': True,
            'teacher_student_commercial_production_verified': False}
