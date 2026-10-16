"""Verify complete variants against their own source modes, not a family envelope."""
import base64
import hashlib
import json
import re
import xml.etree.ElementTree as ET
from urllib.parse import quote
from grade_mode_evidence import load_ref
from quality_review_contract import response_markdown


def words(value):
    return len(re.findall(r"[A-Za-z]+(?:['’][A-Za-z]+)?", value))


def check(data, plan):
    if not plan.get('current_authority_variants'):
        return {'groups': 0, 'responses': 0}
    index = json.loads(load_ref(plan['current_authority_variants']).read_text())
    assert data['variant_authored_index'] == plan['current_authority_variants']
    seen = set()
    for meta in index['candidates']:
        assert meta['id'] not in seen
        seen.add(meta['id'])
        group = data['groups'][meta['id']]
        audit = json.loads(load_ref(meta['author_check']).read_text())
        text = load_ref(meta['candidate']).read_text()
        sources = json.loads(load_ref(audit['source_index']).read_text())['groups']
        source = next(s for s in sources if s['id'] == audit['source_group_id'])
        assert source['full_student_input'] and not source['is_independent_gold']
        load_ref(source['source'])
        assert meta['source_index'] == audit['source_index']
        assert audit['source_observation']['source_material'] == source['material']
        assert audit['source_observation']['source_candidates'] == source['candidates']
        assert audit['candidate_sha256'] == meta['candidate']['sha256']
        assert source['id'] in group['anchor_group_ids']
        assert group['grade'] == source['level'] == meta['grade']
        assert group['kind'] == meta['family']
        assert group['instruction'] == meta['instruction']
        assert group['sourceFormNotice'] == meta['source_form_notice']
        assert len(group['questions']) == audit['questions'] == source['responses'] == meta['questions']
        assert [q['number'] for q in group['questions']] == list(range(1, meta['questions']+1))
        assert [len(q['options']) for q in group['questions']] == source['candidates']['per_response']
        assert [q['answer'] for q in group['questions']] == audit['author_answer_vector']
        assert all(q['rationale'] and q['answer'] in dict(q['options']) for q in group['questions'])
        assert group['questions'] == audit['review_response_tasks']
        printed = text.split('<!-- responses:start -->')[1].split('<!-- responses:end -->')[0].strip()
        assert printed == response_markdown(group['questions'])
        assert hashlib.sha256(printed.encode()).hexdigest() == audit['canonical_response_block_sha256']
        assert audit['student_passage'] in text
        assert audit['load_measure']['body_English_words'] == words(audit.get('body_load_text',audit['student_passage']))
        assert audit['load_measure']['stem_English_words'] == sum(words(q['stem']) for q in group['questions'])
        assert audit['load_measure']['options_English_words_with_repeated_bank'] == sum(words(v) for q in group['questions'] for _,v in q['options'])
        assert audit['load_measure']['output_response_positions'] == len(group['questions'])
        assert not audit['independent_teacher_student_commercial_production_validated']
        if audit.get('figure_asset'):
            asset = load_ref(audit['figure_asset'])
            assert len(group['requiredPassageImages']) == 1
            assert base64.b64decode(group['requiredPassageImages'][0]['src'].split(',',1)[1]) == asset.read_bytes()
            assert audit['required_visual_panels'] == len(audit['visual_panel_semantics'])
            root=ET.fromstring(asset.read_bytes())
            assert len(root.findall('{http://www.w3.org/2000/svg}g')) == audit['required_visual_panels']
            assert not root.findall('.//{http://www.w3.org/2000/svg}image')
            assert not root.findall('.//{http://www.w3.org/2000/svg}script')
        else:
            assert not group['requiredPassageImages']
        if meta['family'] in {'listening_extract_choice','listening_interview_choice','listening_double_matching'}:
            manuscript=json.loads(load_ref(audit['manuscript']).read_text())
            generation=json.loads(load_ref(audit['audio_generation']).read_text())
            assert generation['manuscript']==audit['manuscript']
            assert generation['whole_final_audio_decode_passed'] and generation['no_source_recording_reused']
            assert not generation['independent_listening_pronunciation_prosody_student_commercial_production_validated']
            family=meta['family']
            expected_tracks=3 if family=='listening_extract_choice' else 1
            assert audit['extracts']==len(audit['audio_assets'])==len(group['requiredAudioAssets'])==len(manuscript['clips'])==expected_tracks
            expected_counts=[2,2,2] if family=='listening_extract_choice' else [source['responses']]
            assert audit['questions_per_extract']==expected_counts
            assert audit['audio_transcript_in_teacher_only'] and audit['synthetic_audio_not_natural_listening_calibration']
            assert [n for a in group['requiredAudioAssets'] for n in a['response_numbers']]==list(range(1,source['responses']+1))
            for n,(asset,track,clip,display) in enumerate(zip(audit['audio_assets'],generation['tracks'],manuscript['clips'],group['requiredAudioAssets']),1):
                load_ref(asset)
                assert asset['sha256']==track['sha256'] and asset['repeat_count']==track['repeat_count']==2
                assert display['asset']=={k:asset[k] for k in ['path','sha256']}
                assert display['src']=='../../'+quote(asset['path']) and display['repeat_count']==2
                assert asset['sha256'] not in {a['sha256'] for a in source['original_audio_assets']}
                numbers=[2*n-1,2*n] if family=='listening_extract_choice' else list(range(1,source['responses']+1))
                assert asset['response_numbers']==numbers and abs(asset['seconds']-track['seconds'])<.01
                assert [q['answer'] for q in clip['questions']]==[audit['author_answer_vector'][i-1] for i in numbers]
                assert all(t['text'] in group['reviewText'] for t in clip['turns'])
                assert all(t['text'] not in group['passageHtml'] for t in clip['turns'])
                for repeat in [1,2]:
                    segments=[s for s in track['segments'] if s['role']=='dialogue' and s['repeat']==repeat]
                    assert [(s['speaker'],s['text']) for s in segments]==[(t['speaker'],t['text']) for t in clip['turns']]
            assert audit['load_measure']['audio_dialogue_English_words_once']==sum(t['dialogue_words_once'] for t in generation['tracks'])
            assert audit['load_measure']['audio_spoken_words_including_repetition_and_introductions']==sum(t['spoken_words_with_instructions'] for t in generation['tracks'])
            if family=='listening_interview_choice':
                assert source['material']['interview']==1 and source['material']['interviewees']==2
                assert set(t['speaker'] for t in manuscript['clips'][0]['turns'])=={'I','G1','G2'}
                assert len(group['questions'])==6 and all(len(q['options'])==4 for q in group['questions'])
            if family=='listening_double_matching':
                assert group['fixedSharedBank']
                assert audit['same_five_speakers_for_both_tasks'] and audit['two_tasks_one_whole_group']
                assert audit['no_unprinted_once_rule_added'] and source['material']['monologues']==5
                assert [t['speaker'] for t in manuscript['clips'][0]['turns']]==['S1','S2','S3','S4','S5']
                assert len(group['questions'])==10 and len(audit['shared_banks'])==2
                assert all(len(b['options'])==8 for b in audit['shared_banks'])
                assert audit['shared_banks'][0]['options']!=audit['shared_banks'][1]['options']
                assert all(q['options']==audit['shared_banks'][i//5]['options'] for i,q in enumerate(group['questions']))
                assert '最多' not in group['instruction'] and 'once' not in group['instruction']
                assert audit['load_measure']['options_English_words_unique_shared_banks']==sum(words(v) for b in audit['shared_banks'] for _,v in b['options'])
        if meta['family'] == 'paragraph_gap_insertion':
            assert len(audit['shared_paragraphs']) == 7
            assert audit['removed_paragraph_count'] == 6 and audit['material_article_count'] == 1
            assert re.findall(r'\((\d+)\) ____',audit['student_passage']) == list('123456')
            assert audit['paragraph_insertion_not_sentence_gap']
            assert len(audit['filled_article']) > 1000 and '____' not in audit['filled_article']
            assert all(q['options'] == audit['shared_paragraphs'] for q in group['questions'])
            assert audit['reuse_rule'] == 'one_extra_paragraph_explicit;no_added_unprinted_max_once_rule'
            assert '最多用一次' not in meta['instruction']
        if meta['family'] == 'multiple_text_information_matching':
            assert audit['consultant_section_count'] == len(audit['consultant_sections']) == 5
            assert audit['material_article_count'] == 1 and len(group['questions']) == 10
            assert audit['reuse_rule'] == 'explicit_repeat_allowed'
            assert len(set(audit['author_answer_vector'])) < len(group['questions'])
        if source['id'] == 'p4.fangshan2025.two-picturebanks':
            assert audit['candidate_banks_are_independent']
            assert audit['required_visual_panels'] == 10
            assert [q['options'] for q in group['questions'][:5]] == [audit['subgroups'][0]['shared_bank']]*5
            assert [q['options'] for q in group['questions'][5:]] == [audit['subgroups'][1]['shared_bank']]*5
        if source['id'] == 'p6.dongcheng2025.closedmixed':
            assert audit['subgroups'] == [
                {'response_numbers':[1,2,3],'operation':'TF','options_each':2},
                {'response_numbers':[4,5],'operation':'choice','options_each':3}]
        if source['id'] == 'p6.dongcheng2025.booktable':
            assert audit['book_columns'] == 4 and audit['required_visual_panels'] == 4
            assert audit['pricing_and_discount_footer_required'] and audit['table_includes_all_cells']
        if source['id'] == 'p4.shijingshan2025.dialoguereading':
            assert source['response_identity_ambiguity']['question'] == 1
            assert source['response_identity_ambiguity']['A'] != source['response_identity_ambiguity']['C']
            assert source['not_truncated_from_mixed_material'] and audit['source_key_defect_not_reproduced']
    assert len(seen) == index['new_authored_groups']
    responses = sum(m['questions'] for m in index['candidates'])
    assert responses == index['new_response_positions']
    return {'groups': len(seen), 'responses': responses,
            'full_source_specific_contracts': True, 'not_independent_content_or_student_validation': True}
