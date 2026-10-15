#!/usr/bin/env python3
"""Source-page-bound student transcriptions, separately from frozen empty native text."""
import argparse
import json
import re
from itertools import combinations
from pathlib import Path
from grade_mode_evidence import BASE, evidence, load_ref
from audit_school_material_families import digest
from audit_baseline_native_materials import native_views
from audit_baseline_prepared_materials import prior_bodies, prepared_views
from audit_cloze_materials import normalized, shingles
from profile_task_load import count

MANIFEST = BASE / 'FirstRelease/Sampling/image-transcribed-material-views-v0.1.json'


def transcribed_views(manifest):
    sources = {r['id']: r for r in evidence()}
    acquisitions = {r['id']: r for r in json.loads((BASE / 'Registry/acquisitions.json').read_text())['acquisitions']}
    records, bodies, layouts = [], {}, {}
    for case in manifest['views']:
        row = sources[case['group_id']]
        if row['layer'] != 'baseline_selected117' or row['paper_id'] != case['source_parent_id']:
            raise ValueError('Transcription belongs to another source layer/parent')
        parent = acquisitions[case['source_parent_id']]
        if case['parent_document'] != {'path': parent['path'], 'sha256': parent['sha256']}:
            raise ValueError('Transcription cites another parent version')
        load_ref(case['parent_document'])
        catalogue = json.loads(load_ref(case['source_catalogue']).read_text())
        obs = next(r for r in catalogue['groups'] if r['id'] == case['group_id'])
        logical_image = case.get('source_page_kind', 'PDF') == 'logical_paper_image'
        page_key = 'logical_paper_page' if logical_image else 'PDF_page'
        source_pages = case['logical_paper_pages'] if logical_image else case['PDF_pages']
        observed_pages = obs['logical_paper_pages'] if logical_image else obs['material_and_question_PDF_pages']
        if obs.get('acquisition_id', obs.get('source_paper_acquisition_id')) != case['source_parent_id'] or observed_pages != source_pages:
            raise ValueError('Original page scope differs')
        data = json.loads(load_ref(case['transcription']).read_text())
        record = data['records'][case['record_index']]
        if record['id'] != row['id'] or record['grade'] != row['shape']['grade'] or record['family'] != row['shape']['family']:
            raise ValueError('Student source record/grade/mode differs')
        if record['item_ids'] != obs['question_numbers'] or record['options_each'] != row['shape']['options_each']:
            raise ValueError('Source response/option configuration differs')
        if record['images'] != case['source_images'] or not record['all_body_questions_options_actually_visually_read']:
            raise ValueError('Reviewed image binding missing')
        if case['student_text_reviewed_complete'] is not True or case['independent_transcription'] is not False or record['independent_gold']:
            raise ValueError('Review scope or gold status differs')
        page_sets = case.get('image_logical_page_sets') if logical_image else None
        if page_sets is not None:
            page_key = 'logical_paper_pages'
            if not isinstance(page_sets, list) or any(not isinstance(group, list) or not group or any(type(p) is not int or p < 1 for p in group) for group in page_sets):
                raise ValueError('Empty logical page coverage')
            image_pages = page_sets
            covered_pages = {p for group in page_sets for p in group}
        else:
            image_pages = case.get('image_logical_paper_pages', source_pages) if logical_image else source_pages
            covered_pages = set(image_pages)
        if len(case['source_images']) != len(image_pages) or covered_pages != set(source_pages):
            raise ValueError('Original page/image allocation incomplete')
        shared = case.get('shared_context_images', [])
        shared_pages = case.get('shared_context_pages', [])
        if len(shared) != len(shared_pages) or set(shared_pages) & set(source_pages):
            raise ValueError('Shared instruction page allocation differs')
        all_images = case['source_images'] + shared
        all_pages = image_pages + shared_pages
        author_bindings = case.get('author_page_bindings')
        if author_bindings is not None:
            expected_bindings = [{'parent_id': case['source_parent_id'], page_key: page, 'image': image}
                                 for page, image in zip(all_pages, all_images)]
            if author_bindings != expected_bindings or record.get('author_page_bindings') != author_bindings:
                raise ValueError('Explicit author-reviewed parent/page binding differs')
        for page, image in zip(all_pages, all_images):
            matches = [r for r in acquisitions.values() if r.get('path') == image['path'] and r.get('sha256') == image['sha256']]
            if len(matches) != 1:
                raise ValueError('Unregistered source image')
            provenance = matches[0].get('derivation', {})
            registered_pages = [provenance[k] for k in ['PDF_page', 'pdf_page', 'file_page'] if k in provenance]
            page_provenance = 'acquisition_id' in provenance or bool(registered_pages)
            declared_page = registered_pages[0] if registered_pages else None
            if len(set(registered_pages)) > 1:
                raise ValueError('Conflicting registered physical PDF page fields')
            if page_provenance and (provenance.get('acquisition_id') != case['source_parent_id'] or declared_page != page):
                raise ValueError('Image belongs to another original source/page')
            if provenance.get('related_acquisition_ids') and case['source_parent_id'] not in provenance['related_acquisition_ids']:
                raise ValueError('Image origin names a different source parent')
            if not page_provenance and author_bindings is None:
                raise ValueError('Missing render provenance or explicit author page binding')
            load_ref(image)
        if logical_image:
            from PIL import Image
            pixels = case['source_image_pixel_bindings']
            if pixels != record.get('source_image_pixel_bindings') or len(pixels) != len(all_images):
                raise ValueError('Original image crop bindings omitted or changed')
            with Image.open(load_ref(case['parent_document'])) as original:
                original_rgb = original.convert('RGB')
                for image, binding in zip(all_images, pixels):
                    acquired = next(a for a in acquisitions.values() if a.get('path') == image['path'])
                    box = acquired.get('source_pixel_box')
                    if binding != {'image': image, 'parent_id': case['source_parent_id'], 'pixel_box': box} or acquired.get('source_parent_acquisition_id') != case['source_parent_id'] or not box or not (0 <= box[0] < box[2] <= original_rgb.width and 0 <= box[1] < box[3] <= original_rgb.height):
                        raise ValueError('Crop rectangle differs from registered original image')
                    with Image.open(load_ref(image)) as tile:
                        if tile.size != (box[2] - box[0], box[3] - box[1]) or tile.convert('RGB').tobytes() != original_rgb.crop(tuple(box)).tobytes():
                            raise ValueError('Existing tile pixels differ from original image crop')
        if [c['pointer'] for c in case['components']] != [['records', case['record_index'], 'components', i, 'text'] for i in range(len(record['components']))]:
            raise ValueError('Student components missing/reordered/foreign')
        totals = {};parts = []
        for binding, c in zip(case['components'], record['components']):
            if any(binding.get(k) != c.get(k) for k in ['id', 'role', 'item_id']) or digest(c['text']) != binding['sha256']:
                raise ValueError('Source component binding differs')
            if c['role'] not in ['passage', 'material_label', 'instruction', 'prompt', 'option', 'scoring_declaration', 'illustrated_gloss_label', 'given_hint', 'shared_option', 'bank_entry', 'diagram_label', 'Chinese_meaning', 'initial_letter', 'survey_prompt', 'survey_category', 'table_header', 'table_cell'] or any(t in c['text'] for t in ['【答案】', '【解析】']):
                raise ValueError('Private key/author reason is not student input')
            text = c['text']
            if c['role'] == 'passage':
                parts.append(text)
                if row['shape']['family'] == 'passage_form':
                    text = re.sub(r'_+\d+_+\s*\([^()]+\)', ' ', text)
                text = re.sub(r'_+\d+_+', ' ', text)
            if c['role'] == 'prompt' and row['shape']['family'] == 'context_word_completion':
                text = re.sub(r'_+\d+_+', ' ', text)
            role = totals.setdefault(c['role'], {'english_digit_tokens': 0, 'han_characters': 0, 'components': 0})
            for k, v in count(text).items():
                role[k] += v
            role['components'] += 1
        body = '\n'.join(parts)
        blanks = [int(n) for n in re.findall(r'_+(\d+)_+', body)]
        if blanks != record['blank_numbers'] or (row['shape']['family'] == 'choice_cloze' and blanks != obs['question_numbers']):
            raise ValueError('Cloze blank sequence incomplete')
        if row['shape']['family'] == 'reading_choice':
            prompts = [c for c in record['components'] if c['role'] == 'prompt']
            if [c['item_id'] for c in prompts] != record['item_ids']:
                raise ValueError('Reading prompt order/identity incomplete')
            if totals.get('option', {}).get('components') != row['shape']['responses'] * record['options_each']:
                raise ValueError('Reading option count incomplete or foreign')
            policy = case.get('source_policy', {})
            if policy.get('reading_layout_version') == '0.1':
                if record.get('source_policy') != policy or policy['source_features'] != obs['features']:
                    raise ValueError('Reading source marks/selection/catalogue differ')
                optional = bool(obs.get('optional_source_layer') or obs['features'].get('optional_score_component') or obs['features'].get('optional6points'))
                if policy['optional_source_component'] is not optional:
                    raise ValueError('Optional reading cannot become mandatory by default')
                by_id = {c['id']: c for c in record['components']}
                if len(by_id) != len(record['components']):
                    raise ValueError('Repeated reading component identity')
                marks = policy['required_marks']
                for mark in marks:
                    component = by_id.get(mark['component_id'], {})
                    if mark['kind'] not in ['underline', 'heading_blank', 'quoted_target'] or component.get('role') != 'passage' or component.get('text', '').count(mark['text']) != 1 or mark['question_number'] not in record['item_ids']:
                        raise ValueError('Required reading mark belongs to another material/question')
                for style in policy.get('question_target_styles', []):
                    targets = [m for m in marks if m['question_number'] == style['question_number'] and m['text'] == style['target_text']]
                    expected_kind = 'underline' if style['printed_underline_confirmed'] is True else 'quoted_target'
                    if len(targets) != 1 or targets[0]['kind'] != expected_kind or style['question_claims_underline'] is not True:
                        raise ValueError('Question wording cannot certify an unconfirmed printed underline')
                heading_marks = [m for m in marks if m['kind'] == 'heading_blank']
                heading = obs['features'].get('placeholder_heading_number')
                if heading is not None and [m['question_number'] for m in heading_marks] != [heading]:
                    raise ValueError('Printed heading blank is not a shared insertion group')
                if obs['features'].get('first_section_heading_blank_with_four_choice_question_not_sentence_insertion') and (len(heading_marks) != 1 or heading_marks[0]['question_number'] != record['item_ids'][0] or blanks):
                    raise ValueError('Unnumbered heading blank must bind one four-choice question')
                for cid in policy.get('source_figure_component_ids', []):
                    if by_id.get(cid, {}).get('role') not in ['diagram_label', 'illustrated_gloss_label']:
                        raise ValueError('Figure labels omitted from complete reading input')
                panels = policy.get('source_panels')
                if panels is not None:
                    expected_panels = obs['features'].get('intro_cards')
                    if obs['features'].get('genre') == 'four_AI_profiles':
                        expected_panels = 4
                    if expected_panels is None or len(panels) != expected_panels or len({p['component_id'] for p in panels}) != len(panels):
                        raise ValueError('Reading panels are not response units or shared options')
                    for panel in panels:
                        component = by_id.get(panel['component_id'], {})
                        if component.get('role') != 'passage' or component.get('text', '').splitlines().count(panel['heading']) != 1 or any(component.get('text', '').count(text) != 1 for text in panel['protected_snippets']):
                            raise ValueError('Card heading/address/time/price belongs to another panel')
                if obs['features'].get('complete_numbered_problem_list_and_graph_required'):
                    categories = [c for c in record['components'] if c['role'] == 'survey_category']
                    if [c['category_id'] for c in categories] != policy['survey_category_ids'] or len(categories) != obs['features']['categories'] or policy['survey_population'] != obs['features']['population'] or policy['survey_multiple_choices_allowed'] is not True or policy['survey_percent_denominator'] != 'class50_per_category' or policy['survey_y_axis'] != 'students' or policy['survey_bar_labels_unit'] != 'percent' or policy['survey_x_axis'] != 'problems':
                        raise ValueError('Survey categories/population/multiselect/axis units differ')
                    review = acquisitions[catalogue['private_review_acquisition_id']]
                    if review['sha256'] != catalogue['private_review_sha256']:
                        raise ValueError('Prior visual survey review version differs')
                    graph = json.loads(load_ref({'path': review['path'], 'sha256': review['sha256']}).read_text())['survey_graph']
                    if policy['survey_percentages'] != graph['percentages'] or policy['survey_category_ids'] != graph['category_ids'] or by_id['surveyBars']['text'] != ' '.join(str(p) + '%' for p in graph['percentages']):
                        raise ValueError('Survey bars do not match earlier source-page observation')
                    material_ids = policy['material_component_ids']
                    expected_ids = [c['id'] for c in record['components'] if c['role'] in ['passage', 'survey_prompt', 'survey_category']]
                    if material_ids != expected_ids:
                        raise ValueError('Survey material omits/reorders questionnaire inputs')
                    body = '\n'.join(by_id[cid]['text'] for cid in material_ids)
                table = policy.get('source_table')
                if table:
                    material_ids = table['material_component_ids']
                    expected_ids = [c['id'] for c in record['components'] if c['role'] in ['passage', 'table_header', 'table_cell']]
                    if len(material_ids) != len(set(material_ids)) or set(material_ids) != set(expected_ids):
                        raise ValueError('Table/prose material components omitted or repeated')
                    if table['kind'] == 'climate_matrix':
                        cells = [c for c in record['components'] if c['role'] == 'table_cell']
                        headers = [c for c in record['components'] if c['role'] == 'table_header']
                        if not obs['features'].get('six_row_climate_table_with_text') or table['row_count'] != 6 or table['column_count'] != 3 or table['units_by_column'] != [None, '°C', 'cm'] or [c['text'] for c in headers] != table['headers'] or len(headers) != 3 or len(cells) != 18:
                            raise ValueError('Climate table dimensions/header/units differ')
                        if [(c['row_index'], c['column_index'], c['text']) for c in cells] != [(i, j, text) for i, row_values in enumerate(table['rows']) for j, text in enumerate(row_values)] or len(table['rows']) != 6 or any(len(values) != 3 for values in table['rows']):
                            raise ValueError('Climate table month/temperature/rainfall association differs')
                    elif table['kind'] == 'numbered_advice':
                        ids = table['row_ids'];labels = table['label_component_ids'];advice = table['advice_component_ids']
                        if not obs['features'].get('numbered_rows_required') or ids != [1, 2, 3, 4, 5] or table['row_count'] != 5 or len(labels) != 5 or len(advice) != 5 or table['circled_labels'] != list('①②③④⑤'):
                            raise ValueError('Numbered advice table row labels omitted')
                        for n, label, cell in zip(ids, labels, advice):
                            if by_id[label]['role'] != 'table_header' or by_id[cell]['role'] != 'table_cell' or by_id[label]['row_index'] != n or by_id[cell]['row_index'] != n:
                                raise ValueError('Advice heading/content belongs to another row')
                        pairs = table['option_row_pairs']
                        options = [c for c in record['components'] if c['role'] == 'option' and c['item_id'] == table['crossrow_question']]
                        if table['crossrow_question'] not in record['item_ids'] or len(pairs) != 4 or any(len(pair) != 2 or any(n not in ids for n in pair) for pair in pairs) or [c['text'] for c in options] != [''.join(table['circled_labels'][n - 1] for n in pair) for pair in pairs]:
                            raise ValueError('Circled option pairs detached from advice rows')
                    else:
                        raise ValueError('Unreviewed reading table mode')
                    for symbol in policy.get('scientific_symbols', []):
                        if symbol['source_subscript'] not in symbol['text'] or by_id[symbol['component_id']]['text'].count(symbol['text']) != 1:
                            raise ValueError('Original scientific subscript omitted or changed')
                    body = '\n'.join(by_id[cid]['text'] for cid in material_ids)
        if row['shape']['family'] == 'context_word_completion':
            units = record['units'];by_id = {c['id']: c for c in record['components']}
            if parts or [u['printed_number'] for u in units] != record['item_ids'] or case['source_policy']['all_responses_limit_words'] != 1 or obs['features']['all_responses_limit_words'] != 1:
                raise ValueError('One-word independent contexts differ')
            used = []
            for u in units:
                n = u['printed_number'];prompt = by_id[u['prompt_component']];cue = by_id[u['cue_component']]
                if prompt['role'] != 'prompt' or prompt['item_id'] != n or cue['item_id'] != n or u['word_limit'] != 1 or re.findall(r'_+(\d+)_+', prompt['text']) != [str(n)]:
                    raise ValueError('Independent word prompt/cue/limit differs')
                expected_role = 'Chinese_meaning' if n in obs['features']['Chinese_meaning_slots'] else 'initial_letter'
                if cue['role'] != expected_role or (expected_role == 'initial_letter' and (cue['text'] != case['source_policy']['initial_letters'][str(n)] or cue['text'] + '__' + str(n) + '__' not in prompt['text'])):
                    raise ValueError('Chinese/initial-letter cue belongs to another unit')
                used += [prompt['id'], cue['id']]
            if len(set(used)) != len(used) or set(used) != {c['id'] for c in record['components'] if c['role'] in ['prompt', 'Chinese_meaning', 'initial_letter']}:
                raise ValueError('Word input omitted/reused')
            body = '\n'.join(by_id[u['prompt_component']]['text'] for u in units)
        elif row['shape']['family'] == 'shared_bank':
            bank = [c for c in record['components'] if c['role'] == 'bank_entry'];policy = case['source_policy'];features = obs['features']
            if len(parts) != 1 or blanks != record['item_ids'] or len(bank) != row['shape']['details']['entries'] or [c['text'] for c in bank] != policy['entries'] or not features['entry_once'] or policy['max_use_per_entry'] != 1 or not policy['correct_form_required'] or policy['all_responses_oneword'] or record['response_policy'] != 'word_or_phrase_correct_form_from_bank':
                raise ValueError('Once-only word/phrase/form bank differs')
            if totals.get('option') or totals.get('prompt') or totals.get('given_hint'):
                raise ValueError('Bank is not per-response choice or grammar hints')
            if features.get('illustrated_food_chain_required') and (not policy.get('necessary_food_chain_visual') or not totals.get('diagram_label')):
                raise ValueError('Necessary food-chain visual/labels omitted')
        elif row['shape']['family'] == 'shared_insertion':
            candidates = [c for c in record['components'] if c['role'] == 'shared_option']
            slots = record['slots'];policy = case['source_policy']
            if blanks != record['item_ids'] or [s['printed_number'] for s in slots] != blanks or len(parts) != 1 or any(totals.get(k) for k in ['option', 'prompt', 'given_hint']):
                raise ValueError('Shared insertion is one complete material with shared candidates')
            expected_count = row['shape']['details']['shared_options']
            if len(candidates) != expected_count or [c['option_label'] for c in candidates] != list('ABCDEFG'[:expected_count]) or any(not c['text'] for c in candidates):
                raise ValueError('Whole shared sentence candidate set differs')
            headings = policy['heading_slot_numbers']
            if [s['printed_number'] for s in slots if s['role'] == 'section_heading'] != headings or record['response_policy'] != 'letter_from_shared_options' or policy['reuse_rule_explicit'] is not None or record['reuse_rule_explicit'] is not None:
                raise ValueError('Heading/sentence roles or unsupported once-only policy differ')
            for slot in slots:
                if slot['role'] not in ['section_heading', 'sentence_gap'] or slot['response_fields'] != 1:
                    raise ValueError('Insertion gap role/response allocation differs')
                n = slot['printed_number']
                isolated = bool(re.search(r'(?m)^\s*(?:[•●]\s*)?_+' + str(n) + r'_+\s*$', body))
                if n in headings and not isolated:
                    raise ValueError('Declared heading slot differs from source layout')
        elif row['shape']['family'] == 'passage_form':
            hints = [c for c in record['components'] if c['role'] == 'given_hint']
            slots = record['slots']
            if blanks != record['item_ids'] or [s['printed_number'] for s in slots] != blanks or totals.get('option') or totals.get('prompt'):
                raise ValueError('Grammar passage/hint/response sequence differs')
            expected_given = case['source_policy']['given_word_numbers']
            features = obs['features']
            catalogue_given = features.get('given_word_numbers', features.get('given_slots'))
            catalogue_ungiven = features.get('no_prompt_numbers', features.get('ungiven_slots'))
            if (catalogue_given is not None and expected_given != catalogue_given) or (catalogue_ungiven is not None and [n for n in blanks if n not in expected_given] != catalogue_ungiven):
                raise ValueError('Grammar cue pattern conflicts with source catalogue')
            given_limit = 1 if features.get('all_responses_limit_words') == 1 else None
            if len(parts) != row['shape']['details']['materials'] or case['source_policy']['ungiven_word_limit'] != 1 or case['source_policy']['given_word_limit_explicit'] != given_limit:
                raise ValueError('Whole grammar material/response policy differs')
            if [c['item_id'] for c in hints] != expected_given:
                raise ValueError('Given word pattern differs')
            for slot in slots:
                n = slot['printed_number'];given = n in expected_given
                if slot['word_limit'] != (given_limit if given else 1) or bool(slot['given_hint']) != given:
                    raise ValueError('Given forms must not inherit the ungiven one-word limit')
                if given:
                    cue = next(c for c in hints if c['id'] == slot['given_hint'])
                    match = re.search(r'_+' + str(n) + r'_+\s*\(([^()]+)\)', body)
                    if cue['item_id'] != n or not match or match.group(1) != cue['text']:
                        raise ValueError('Grammar hint belongs to another blank')
            body = re.sub(r'_+\d+_+\s*\([^()]+\)', ' ', body)
        else:
            for number in record['item_ids']:
                options = [c for c in record['components'] if c['role'] == 'option' and c['item_id'] == number]
                if [c['option_label'] for c in options] != list('ABCD'[:record['options_each']]) or any(not c['text'] for c in options):
                    raise ValueError('Original per-response option set incomplete')
        gid = row['id']
        if gid in bodies:
            raise ValueError('Duplicate transcription is not a new instance')
        norm = normalized(body);bodies[gid] = norm
        records.append({'group_id': gid, 'paper_identity': row['paper_id'], 'transcription': case['transcription'],
                        'material_sha256': digest(body), 'normalized_material_sha256': digest(norm),
                        'component_counts': totals, 'responses': row['shape']['responses'],
                        'source_images': case['source_images'], 'student_text_reviewed_complete': True,
                        'frozen_native_input_state': row['necessary_input_complete'], 'independent_transcription': False,
                        'independent_answer_gold': False, 'commercial_admission': False})
        layouts[gid] = {'source_shape': row['shape'], 'transcription': case['transcription'],
                        'source_images': case['source_images'], 'student_text_reviewed_complete': True,
                        'source_image_scopes': case['source_image_scopes'],
                        'frozen_source_input_state': row['necessary_input_complete'], 'blank_numbers': blanks}
        if author_bindings is not None:
            policy = case.get('source_policy')
            if policy is None or record.get('source_policy') != policy or len(case['source_image_scopes']) != len(all_images):
                raise ValueError('Source score/media/gloss scope omitted or changed')
            layouts[gid].update(source_images=all_images, author_page_bindings=author_bindings, source_policy=policy)
            records[-1].update(source_policy=policy, image_parent_page_binding='author_visual_binding_not_registered_derivation')
        if row['shape']['family'] in ['passage_form', 'shared_insertion']:
            layouts[gid]['slots'] = slots
        if row['shape']['family'] == 'context_word_completion':
            layouts[gid]['units'] = units
        if logical_image:
            layouts[gid].update(source_page_kind='logical_paper_image', logical_paper_pages=source_pages,
                                source_image_pixel_bindings=pixels)
            if 'image_logical_paper_pages' in case:
                layouts[gid]['image_logical_paper_pages'] = image_pages
            if page_sets is not None:
                layouts[gid]['image_logical_page_sets'] = page_sets
            records[-1]['existing_crop_pixels_verified_against_original'] = True
    return records, bodies, layouts


def check(request, layouts):
    gid = request.get('evidence_group_id')
    if gid not in layouts or request.get('layout') != layouts[gid] or request.get('included_source_images') != layouts[gid]['source_images']:
        raise ValueError('Reviewed text/source-image/shape/blank binding differs')
    if any(request.get(k) for k in ['use_as_verified_answer_gold', 'claim_production_supported', 'claim_factual_review_complete', 'claim_student_calibrated', 'claim_semantic_family_screen_complete']):
        raise ValueError('Visual author transcription is not independent gold or production support')
    return {'reviewed_source_text_preparation_matches': True, 'evidence_group_id': gid,
            'student_text_reviewed_complete': True, 'frozen_source_input_state': layouts[gid]['frozen_source_input_state'],
            'independent_answer_gold': False, 'model_called': False, 'production_supported': False}


def audit():
    manifest = json.loads(MANIFEST.read_text())
    records, new, _ = transcribed_views(manifest)
    native_manifest = json.loads(load_ref(manifest['prior_view_manifest']).read_text())
    nrecords, nbodies, _ = native_views(native_manifest)
    prepared_manifest = json.loads(load_ref(native_manifest['prior_view_manifest']).read_text())
    old, earlier = prior_bodies(prepared_manifest)
    precords, pbodies = prepared_views(prepared_manifest)
    if set(old) & set(pbodies) or set(old) & set(nbodies) or set(pbodies) & set(nbodies):
        raise ValueError('Repeated ancestor identity')
    old.update(pbodies);old.update(nbodies)
    prior = json.loads(load_ref(manifest['prior_material_audit']).read_text())
    if len(old) != prior['material_count_total'] or any(digest(old[r['group_id']]) != r['normalized_material_sha256'] for r in prior['records']):
        raise ValueError('Prior native normalization differs')
    if set(old) & set(new):
        raise ValueError('Original instance already screened')
    bodies = dict(old, **new);comparisons = []
    for left, right in combinations(bodies, 2):
        if left in old and right in old:
            continue
        a, b = shingles(bodies[left]), shingles(bodies[right]);exact = bodies[left] == bodies[right]
        jac = len(a & b) / len(a | b) if a | b else 0;con = len(a & b) / min(len(a), len(b)) if a and b else 0
        comparisons.append({'left': left, 'right': right, 'exact_normalized_match': exact,
                            'fivegram_jaccard': jac, 'fivegram_containment': con,
                            'review_candidate': exact or jac >= .5 or con >= .8})
    total = len(bodies) * (len(bodies) - 1) // 2
    if total != prior['pair_count_total'] + len(comparisons):
        raise ValueError('Cross-layer pair coverage differs')
    return {'version': '0.1', 'records_scope': 'two new image-transcribed source profiles; prior210 via frozen references',
            'prior_records_and_comparisons': manifest['prior_material_audit'], 'records': records,
            'material_count_total': len(bodies), 'parent_count_total': len({r['paper_identity'] for r in earlier['records'] + precords + nrecords + records}),
            'pair_count_total': total, 'prior_pairs_reused': prior['pair_count_total'], 'new_pair_count': len(comparisons),
            'comparisons': comparisons, 'exact_repeat_pairs': prior['exact_repeat_pairs'] + sum(c['exact_normalized_match'] for c in comparisons),
            'review_candidates': prior['review_candidates'] + sum(c['review_candidate'] for c in comparisons),
            'frozen_empty_native_records_unchanged': True, 'all_benchmark_deduplication_complete': False,
            'zero_candidates_not_independent_families': True, 'independent_transcription': False, 'model_called': False}


def continuation_ancestors(manifest):
    """Rebuild referenced views without recomparing any old pair."""
    from audit_baseline_sentence_banks import old_views, sentence_views
    previous = json.loads(load_ref(manifest['prior_view_manifest']).read_text())
    kind = manifest.get('prior_view_kind', 'sentence_bank')
    if kind == 'image_transcription':
        old, old_records, _ = continuation_ancestors(previous)
        recent_records, recent, _ = transcribed_views(previous)
    elif kind == 'sentence_bank':
        old, old_records, _ = old_views(previous)
        recent_records, recent, _, _ = sentence_views(previous)
    else:
        raise ValueError('Unsupported prior view kind')
    if set(old) & set(recent):
        raise ValueError('Duplicate prior source')
    old.update(recent);old_records += recent_records
    prior = json.loads(load_ref(manifest['prior_material_audit']).read_text())
    # The latest audit records only its delta; ancestors validate their own hashes.
    if len(old) != prior['material_count_total'] or any(digest(old[r['group_id']]) != r['normalized_material_sha256'] for r in prior['records']):
        raise ValueError('Frozen previous image audit inputs changed')
    return old, old_records, prior


def continuation_audit(manifest):
    """Compare only new source groups; keep prior frozen report references."""
    from audit_baseline_bank_forms import compare
    old, old_records, prior = continuation_ancestors(manifest)
    records, new, _ = transcribed_views(manifest)
    if set(old) & set(new):
        raise ValueError('Repeated source is not a new group')
    comparisons = [{'left': l, 'right': r, **compare(a, b)} for l, a in new.items() for r, b in old.items()]
    comparisons += [{'left': l, 'right': r, **compare(new[l], new[r])} for l, r in combinations(new, 2)]
    total = len(old) + len(new);pairs = total * (total - 1) // 2
    if pairs != prior['pair_count_total'] + len(comparisons):
        raise ValueError('Incremental pair coverage differs')
    scope = manifest.get('audit_records_scope', 'new image-transcribed groups; previous247 via frozen references')
    return {'version': '0.1', 'records_scope': scope,
            'prior_records_and_comparisons': manifest['prior_material_audit'], 'records': records,
            'material_count_total': total, 'parent_count_total': len({r['paper_identity'] for r in old_records + records}),
            'pair_count_total': pairs, 'prior_pairs_reused': prior['pair_count_total'], 'new_pair_count': len(comparisons),
            'comparisons': comparisons, 'exact_repeat_pairs': prior['exact_repeat_pairs'] + sum(c['exact_normalized_match'] for c in comparisons),
            'review_candidates': prior['review_candidates'] + sum(c['review_candidate'] for c in comparisons),
            'frozen_empty_native_records_unchanged': True, 'all_benchmark_deduplication_complete': False,
            'zero_candidates_not_independent_families': True, 'independent_transcription': False, 'model_called': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--request', type=Path)
    parser.add_argument('--continuation-manifest', type=Path)
    args = parser.parse_args()
    if args.request:
        _, _, layouts = transcribed_views(json.loads((args.continuation_manifest or MANIFEST).read_text()))
        print(json.dumps(check(json.loads(args.request.read_text()), layouts)))
    elif args.output:
        from grade_mode_evidence import REPO
        if (REPO / 'build').resolve() not in args.output.resolve().parents:
            parser.error('Source-derived report must stay in ignored build/')
        result = continuation_audit(json.loads(args.continuation_manifest.read_text())) if args.continuation_manifest else audit()
        payload = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
        if args.output.exists() and args.output.read_text() != payload:
            raise ValueError('Do not overwrite a different image-source audit')
        if not args.output.exists():
            args.output.write_text(payload)
        print(json.dumps({k: result[k] for k in ['material_count_total', 'parent_count_total', 'pair_count_total', 'new_pair_count', 'exact_repeat_pairs', 'review_candidates']}))
    else:
        parser.error('Choose --request or --output')
