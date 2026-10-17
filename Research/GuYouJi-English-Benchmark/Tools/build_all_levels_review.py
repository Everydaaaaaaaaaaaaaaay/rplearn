#!/usr/bin/env python3
"""Extend the pinned middle-school review with complete objective author groups.

Existing authors are reused, never counted as newly authored or new sources.
Unobserved level/task cells stay unknown; subjective mixed groups stay inactive.
"""
import argparse
import hashlib
import json
import re
import tempfile
from pathlib import Path
from build_quality_review import build, full_markdown_candidate
from grade_mode_evidence import BASE, REPO, load_ref
from showcase_rich_reading import material_view
from review_run_plan import resolve_plan


def ref(path):
    return {'path': str(path.relative_to(BASE)) if path.is_relative_to(BASE) else str(path.relative_to(REPO)),
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def inherited(meta, acquisitions, family):
    text = load_ref(meta['candidate']).read_text()
    record = acquisitions[meta['author_check_acquisition_id']]
    audit_path = REPO / record['path']
    if hashlib.sha256(audit_path.read_bytes()).hexdigest() != record['sha256']:
        raise ValueError('Changed historical audit')
    a = json.loads(audit_path.read_text())
    if a['candidate_sha256'] != meta['candidate']['sha256'] or meta.get('open_response_count', 0):
        raise ValueError('Unbound candidate or subjective mixed group')
    student, teacher = text.split('## 学生区', 1)[1].split('## 作者区', 1)
    instruction = next(line.strip() for line in student.splitlines() if line.strip())
    material = a.get('student_passage') or a.get('student_material') or ''
    if a.get('student_turns'):
        material = '\n\n'.join(speaker+': '+turn for speaker, turn in a['student_turns'])
    if a.get('student_table_all_cells'):
        table = a['student_table_all_cells']
        material += '\n\n'+'\n'.join(['| '+' | '.join(table[0])+' |', '| '+' | '.join(['---']*len(table[0]))+' |']+
                                    ['| '+' | '.join(row)+' |' for row in table[1:]])
    shared = a.get('shared_options') or a.get('shared_candidates') or []
    if shared:
        material += '\n\n'+'\n'.join(letter+'. '+value for letter, value in shared)
    vector = a['author_answer_vector']; questions = []
    if a.get('student_items'):
        for item, reason in zip(a['student_items'], a['reason_rows']):
            questions.append({'number': item['number'], 'stem': item['prompt'], 'options': list(item['options'].items()),
                              'answer': item['author_answer'], 'rationale': reason['support']+' '+reason['other_options']})
    else:
        prompts = a.get('student_prompts') or [[str(n), '第'+str(n)+'空'] for n in range(1, len(vector)+1)]
        reasons = a.get('author_reason_rows') or a.get('author_choice_reason_rows') or a.get('author_25_candidate_pairs') or []
        for n, ((_, prompt), answer) in enumerate(zip(prompts, vector), 1):
            options = [(x['label'], x['text']) for x in a.get('student_options', []) if int(x['item_id']) == n]
            if not options:
                options = shared or [('T', '与短文一致'), ('F', '与短文不一致')]
            reason = reasons[n-1] if len(reasons) == len(vector) else '完整逐候选作者核对见下方原稿。'
            questions.append({'number': n, 'stem': re.sub(r'\(\s*\)\s*$', '', prompt).strip(),
                              'options': options, 'answer': answer,
                              'rationale': '；'.join(map(str, reason[1:])) if isinstance(reason, list) else str(reason)})
    if len(questions) != meta['response_count'] or any(not q['options'] for q in questions):
        raise ValueError('Incomplete objective response group')
    return {'id': meta['id'], 'grade': meta['level'], 'kind': family, 'candidate': meta['candidate'],
            'sourceFormNotice': '来源形式为公开模拟题，尚缺普通学校样本复现；不计真实考试认证。' if meta['level']=='primary5' else '',
            'author_check': ref(audit_path), 'anchor_group_ids': [meta['source_group_id']], 'instruction': instruction,
            'responseMode': 'complete_objective_historical_author', 'passageHtml': material_view(material),
            'questions': questions, 'reviewHtml': material_view(teacher), 'reviewText': teacher,
            'requiredPassageImages': [], 'author_review_not_independent': True}


def build_current(output):
    build(BASE/'FirstRelease/timeboxed-review-matrix-v0.9.json', output)
    page = (output/'index.html').read_text()
    data = json.loads(re.search(r'<script id="quality-data" type="application/json">(.*?)</script>', page, re.S)[1])
    plan_path,plan=resolve_plan()
    policy_path = load_ref(plan['current_scope_policy'])
    policy = json.loads(policy_path.read_text())
    aliases = {**{'junior'+str(i): i+6 for i in range(1, 4)}, **{'senior'+str(i): i+9 for i in range(1, 4)}}
    data['grades'] = [aliases.get(row['id'], row['id']) for row in policy['product_levels']]
    data['levelLabels'] = {str(aliases.get(row['id'], row['id'])): row['label'] for row in policy['product_levels']}
    data['current_scope_policy'] = ref(policy_path)
    data['active_run_plan'] = str(plan_path.relative_to(BASE))
    data['scope'] = 'active_product_levels_objective_review_partial_coverage'
    acquisitions = {a['id']: a for a in json.loads((BASE/'Registry/acquisitions.json').read_text())['acquisitions']}
    paths = ['Primary/Grade3/authored-candidate-index-v0.1.json', 'Primary/Grade4/authored-candidate-index-v0.1.json',
             'Primary/Grade5/authored-candidate-index-v0.1.json', 'Primary/Grade6/authored-candidate-index-v0.1.json',
             'CET/authored-candidate-index-v0.1.json']
    added = []; inherited_count = 0
    for filename in paths:
        for meta in json.loads((BASE/filename).read_text())['members']:
            if meta.get('open_response_count', 0) or meta['id'] == 'five-classroom-bank':
                continue  # Keep full mixed group inactive; newer no-once-required bank represents primary4.
            kind = meta['kind']
            family = ('reading_tf' if kind == 'five_true_false' else 'table_reading_choice' if kind.startswith('table_') else
                      'reading_choice' if 'choice' in kind or 'four_options' in kind else
                      'dialogue_matching' if kind in ['five_shared_response_matching', 'five_gaps_five_sentences_or_clause'] else 'shared_bank')
            group = inherited(meta, acquisitions, family); added.append((group, family)); inherited_count += 1
    holds = json.loads(load_ref(plan['current_concrete_group_holds']).read_text()) if plan.get('current_concrete_group_holds') else {'records': []}
    for hold in holds['records']:
        group = data['groups'].pop(hold['id'])
        if group['candidate'] != hold['candidate'] or group['author_check'] != hold['author_check']:
            raise ValueError('Concrete hold must be reviewed again for a changed author version')
        cell = next(c for c in data['cells'] if c['groupId'] == hold['id'])
        cell.update(groupId=None, state=hold['state'], pauseReason=hold['reason'])
    data['concrete_group_holds'] = plan.get('current_concrete_group_holds')
    data['paused_concrete_groups'] = len(holds['records'])
    additions_path = load_ref(plan['current_authored_additions'])
    additions = json.loads(additions_path.read_text())
    source_batch_ref = plan.get('latest_selected_source_batch') or additions.get('this_batch_source_index')
    source_batch = json.loads(load_ref(source_batch_ref).read_text()) if source_batch_ref else {}
    data['selected_source_batch'] = source_batch_ref
    for meta in additions['candidates']:
        group = full_markdown_candidate(meta)
        group['instruction'] = meta.get('instruction') or {'letter_completion':'选择正确的字母组合。', 'shared_bank':'从共享词或短语中选择合适的一项。',
                                'number_word_completion':'看单词，填对应的阿拉伯数字。',
                                'word_picture_choice':'看单词，从同号行的三个图片中选择对应的一项。',
                                'dialogue_matching':'为每个问句选择合适的答句。',
                                'sentence_choice':'选择每题最合适的一项；两个空的题目仍只选择一次。',
                                'reading_choice':'阅读短文，选择每题最合适的一项。',
                                'choice_cloze':'阅读短文，为第1—8空选择最合适的一项。例0已答，不计作答点。'}.get(meta['family'],'按完整题面要求选择最合适的一项。')
        if meta['grade']=='advanced':
            group['sourceFormNotice']='高级档候选模式：参考已核C1样卷完整形式，尚未建立产品高级档与C1等值或目标人群难度标定。'
        if meta['grade']=='primary1':
            group['sourceFormNotice']='来源为一年级旧公开练习的完整数字词题组，原学校与年份未知；本稿数字规范化协议不代表源卷阅卷规则。'
        if meta['grade']=='primary2':
            group['sourceFormNotice']='参考二年级公开转载的完整形式，原学校、考试年份及源键未知；图片词汇有明确适配改编，未建立全国年级或学生难度标定。'
        if meta['grade']=='primary5':
            group['sourceFormNotice']='参考第三方五年级下学期月考练习标签中的连续五道三选题；原校、实际施测与原分值未知，不当学校认证或全国难度标准。'
        if meta['grade'] in ['undergraduate', 'postgraduate'] and meta['family']=='shared_bank':
            group['fixedSharedBank']=True
            group['instruction']='从15个固定词项中为完整10空选择字母；每项最多一次，词形不变。'
            cet_label='四级' if meta['grade']=='undergraduate' else '六级'
            group['sourceFormNotice']='形式复用已核官方2016'+cet_label+'样卷，一篇10空/15词；不是新增来源或年度真卷，也未建立产品难度/CEFR标定。'
        if meta.get('source_form_notice'):
            group['sourceFormNotice']=meta['source_form_notice']
        if meta.get('use_select_controls'):
            group['fixedSharedBank']=True
        added.append((group, meta['family']))
    cells = {(c['grade'], c['family']): c for c in data['cells']}
    labels = {c['family']: c['label'] for c in data['cells']}
    labels.update(letter_completion='字母组合补全', table_reading_choice='表格信息单选', number_word_completion='数字词转数字', word_picture_choice='单词选图片')
    labels.update({m['family']:m['family_label'] for m in additions['candidates'] if m.get('family_label')})
    for group, family in added:
        key = (group['grade'], family)
        if key in cells and cells[key].get('groupId'):
            raise ValueError('Conflicting representative selection')
        data['groups'][group['id']] = group
        cells[key] = {'grade': group['grade'], 'family': family, 'label': labels[family], 'observed': True,
                      'state': 'existing_complete_candidate_needs_review_UI', 'groupId': group['id']}
    # Keep the inherited representative and every complete variant. A later draft
    # must not silently replace the payload or answers of an earlier draft.
    for cell in cells.values():
        cell['groupIds'] = [cell['groupId']] if cell.get('groupId') else []
    variant_index = json.loads(load_ref(plan['current_authority_variants']).read_text()) if plan.get('current_authority_variants') else {'candidates': []}
    for meta in variant_index['candidates']:
        group = full_markdown_candidate(meta)
        group.update(instruction=meta['instruction'], sourceFormNotice=meta['source_form_notice'], title=meta['title'])
        if meta.get('use_select_controls'):
            group['fixedSharedBank'] = True
        if group['id'] in data['groups']:
            raise ValueError('Variant id collides with a frozen author')
        key = (group['grade'], meta['family'])
        labels[meta['family']] = meta['family_label']
        cell = cells.setdefault(key, {'grade': group['grade'], 'family': meta['family'], 'label': meta['family_label'],
                                     'observed': True, 'state': 'existing_complete_candidate_needs_review_UI',
                                     'groupId': None, 'groupIds': []})
        if cell['state'] == 'paused_requires_semantic_adjudication':
            raise ValueError('A variant cannot bypass a paused whole-group contract')
        cell['observed'] = True
        cell['groupIds'].append(group['id'])
        cell['groupId'] = cell['groupId'] or group['id']
        data['groups'][group['id']] = group
    if variant_index['candidates']:
        data['variant_authored_index'] = plan['current_authority_variants']
        labels['passage_form'] = labels.get('passage_form', '语篇语法/词形填空')
        key = ('advanced', 'passage_form')
        cells.setdefault(key, {'grade': 'advanced', 'family': 'passage_form', 'label': labels['passage_form'],
                             'observed': True, 'state': 'source_observed_deterministic_admission_pending',
                             'groupId': None, 'groupIds': [],
                             'pauseReason': '已核完整给词构形源组，但合法词形与规范化尚未审准，暂不出题或自动判分。'})
    for pending in plan.get('pending_authority_cells', []):
        key = (pending['grade'], pending['family'])
        labels[pending['family']] = pending['label']
        cells.setdefault(key, {**pending, 'observed': True, 'groupId': None, 'groupIds': []})
    cet_index_path = BASE/'CET/selected-official-sample-groups-v0.1.json'
    data['existing_CET_source_index'] = ref(cet_index_path)
    for source in json.loads(cet_index_path.read_text())['groups']:
        if source['kind'] == 'word_bank_cloze':
            key = (source['level'], 'shared_bank')
            cells.setdefault(key, {'grade': source['level'], 'family': 'shared_bank', 'label': labels['shared_bank'],
                                   'observed': True, 'state': 'source_observed_author_pending', 'groupId': None,
                                   'source_group_ids': [source['id']]})
    continuation = {'candidates': []}
    if plan.get('current_gap_completion'):
        continuation = json.loads(load_ref(plan['current_gap_completion']).read_text())
        for meta in continuation['candidates']:
            group = full_markdown_candidate(meta)
            group.update(instruction=meta['instruction'], sourceFormNotice=meta['source_form_notice'], title=meta['title'])
            if meta.get('format_summary'):
                group['formatSummary'] = meta['format_summary']
            if meta.get('use_select_controls'):
                group['fixedSharedBank'] = True
            if group['id'] in data['groups']:
                raise ValueError('Continuation cannot replace a frozen author')
            key = (group['grade'], meta['family'])
            cell = cells[key]
            if cell['state'] == 'paused_requires_semantic_adjudication':
                if meta['id'] not in plan.get('held_family_replacement_authors', []):
                    raise ValueError('Continuation cannot bypass a whole-group hold')
                cell['pausedPriorGroupIds'] = [h['id'] for h in holds['records'] if h['grade'] == group['grade'] and h['family'] == meta['family']]
            cell.update(observed=True, state='existing_complete_candidate_needs_review_UI')
            cell.pop('pauseReason', None)
            cell['groupIds'].append(group['id'])
            cell['groupId'] = cell['groupId'] or group['id']
            data['groups'][group['id']] = group
        data['gap_completion_index'] = plan['current_gap_completion']
    if plan.get('current_coverage_audit'):
        data['coverage_audit'] = json.loads(load_ref(plan['current_coverage_audit']).read_text())
    data['cells'] = [cells.get((level, family), {'grade': level, 'family': family, 'label': label, 'observed': False,
                     'state': 'source_evidence_unknown_do_not_invent_grade_adaptation', 'groupId': None})
                     for level in data['grades'] for family, label in labels.items()]
    data['preview_cells'] = len(data['groups'])
    data['source_positive_cells'] = sum(c['observed'] for c in data['cells'])
    data['source_form_representative_cells'] = sum(bool(c.get('groupId')) for c in data['cells'])
    data['multi_variant_cells'] = sum(len(c.get('groupIds', [])) > 1 for c in data['cells'])
    data['three_variant_cells'] = sum(len(c.get('groupIds', [])) >= 3 for c in data['cells'])
    data['extra_authored_index'] = ref(additions_path)
    encoded = json.dumps(data, ensure_ascii=False).replace('<', '\\u003c').replace('>', '\\u003e').replace('&', '\\u0026')
    template = (BASE/'Tools/quality_review_template.html').read_text()
    header = '<th scope="col">题型</th>'+''.join('<th scope="col">'+data['levelLabels'][str(level)]+'</th>' for level in data['grades'])
    template = re.sub(r'<thead><tr><th scope="col">题型</th>.*?</tr></thead>', '<thead><tr>'+header+'</tr></thead>', template)
    page = template.replace('__REVIEW_DATA__', encoded).replace('__REVIEW_SCRIPT__', (BASE/'Tools/quality_review_interactions.js').read_text())
    (output/'index.html').write_text(page)
    report = {'version': '0.1', 'level_count': len(data['grades']), 'levels_with_preview': len({g['grade'] for g in data['groups'].values()}),
              'preview_groups': len(data['groups']), 'response_positions': sum(len(g['questions']) for g in data['groups'].values()),
              'new_authored_groups': len(variant_index['candidates']) if variant_index['candidates'] else additions.get('current_run_new_authored_groups',additions['new_authored_groups']),
              'new_authored_responses': sum(m['questions'] for m in variant_index['candidates']) if variant_index['candidates'] else additions.get('current_run_new_response_positions',additions['new_response_positions']),
              'continuation_new_groups': len(continuation['candidates']),
              'continuation_new_responses': sum(m['questions'] for m in continuation['candidates']),
              'complete_level_type_cells': data['source_form_representative_cells'],
              'multi_variant_cells': data['multi_variant_cells'], 'three_variant_cells': data['three_variant_cells'],
              'historical_nonmiddle_authors_newly_displayed': inherited_count,
              'latest_selected_source_groups': source_batch.get('new_selected_groups', 0),
              'latest_selected_source_parent_identities': source_batch.get('new_parent_identities', 0),
              'authority_selected_source_index': plan.get('current_authority_sources'),
              'middle_source_totals_unchanged': True,
              'paused_complete_groups_with_open_legal_sets': len(holds['records']),
              'source_mode_and_age_calibration_not_established_for_unobserved_cells': True,
              'independent_student_commercial_production_admission': False, 'index_html_sha256': hashlib.sha256(page.encode()).hexdigest()}
    (output/'build-report-v0.1.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps(report))


def main(output):
    output.mkdir(parents=True,exist_ok=True)
    # Validate a temporary render before replacing the user's current preview.
    # This is a disposable working page, never a research-tree snapshot.
    with tempfile.TemporaryDirectory(prefix='.review-stage-',dir=output.parent) as scratch:
        staging=Path(scratch)
        build_current(staging)
        from check_all_levels_review import check
        check(staging/'index.html')
        for name in ['index.html','build-report-v0.1.json']:
            (staging/name).replace(output/name)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=Path, default=REPO/'build/english-benchmark-quality-review')
    main(p.parse_args().output)
