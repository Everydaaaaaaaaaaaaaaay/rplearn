#!/usr/bin/env python3
"""Build an offline six-grade complete multi-type authored preview.

No source-paper payload or model call. Check digest, full question/option sets and
answer-table agreement before writing ignored output. This does not calibrate items.
"""
import argparse
import hashlib
import html
import json
import re
from pathlib import Path
from showcase_extended_tasks import extract_extended

BASE = Path(__file__).resolve().parents[1]
REPO = BASE.parents[1]


def load_ref(ref):
    path = (BASE / ref['path']).resolve()
    if BASE not in path.parents or not path.is_file():
        raise ValueError('Missing/outside benchmark reference: ' + str(path))
    if hashlib.sha256(path.read_bytes()).hexdigest() != ref['sha256']:
        raise ValueError('Digest mismatch: ' + str(path))
    return path


def inline(text):
    return re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', html.escape(text))


def extract(row, label, focus):
    text = load_ref(row['candidate']).read_text()
    audit = json.loads(load_ref(row['author_check']).read_text())
    spec = load_ref(row['specification_at_authoring'])
    if audit['candidate_sha256'] != row['candidate']['sha256']:
        raise ValueError('Candidate/audit mismatch')
    if audit['specification_sha256'] != row['specification_at_authoring']['sha256']:
        raise ValueError('Specification/audit mismatch')
    if audit['grade'] != row['grade'] or audit['questions'] != row['questions']:
        raise ValueError('Grade/count mismatch')
    kind = row['core_kind']
    first_question = re.search(r'^1\. ', text, re.M)
    if not first_question and not (kind == 'cloze' and '| 空 | A |' in text):
        raise ValueError('No first question or complete cloze option table')
    if '<!-- passage:start -->' in text:
        passage = text.split('<!-- passage:start -->', 1)[1].split('<!-- passage:end -->', 1)[0].strip()
    else:
        # The frozen grade7 file predates explicit markers; its exact boundary is
        # fixed here rather than guessing from arbitrary prose/headings.
        if row['id'] != 'grade7-library-v0.1':
            raise ValueError('Explicit passage boundary required')
        passage = text[text.index('Last month,'):first_question.start()].strip()
    if kind == 'cloze' and '| 空 | A |' in text:
        questions_text, review = text[text.index('| 空 | A |'):].split('\n## ', 1)
    else:
        questions_text, review = text[first_question.start():].split('\n## ', 1)
    questions = []
    if kind == 'cloze' and '| 空 | A |' in text:
        for line in questions_text.splitlines():
            cells = [x.strip() for x in line.strip('|').split('|')]
            if not cells[0].isdigit():
                continue
            questions.append({'number': int(cells[0]), 'stem': '第' + cells[0] + '空',
                              'options': list(zip('ABCD', cells[1:]))})
    for match in ([] if questions else re.finditer(r'^(\d+)\. (.*?)(?=^\d+\. |\Z)', questions_text, re.M | re.S)):
        number, body = int(match[1]), match[2].strip()
        options = (re.findall(r'(?:^|\s)([A-D])\.\s*(.*?)(?=\s+[A-D]\.|$)', body, re.S)
                   if kind == 'cloze' else re.findall(r'^\s*([A-D])\. (.+)$', body, re.M))
        stem = ('第' + str(number) + '空' if kind == 'cloze' else
                re.split(r'^\s*A\. ', body, maxsplit=1, flags=re.M)[0].strip())
        if len(options) != audit['options_each'] or [o[0] for o in options] != list('ABCD')[:len(options)]:
            raise ValueError('Incomplete options')
        questions.append({'number': number, 'stem': stem, 'options': options})
    if any(len(q['options']) != audit['options_each'] or [o[0] for o in q['options']] != list('ABCD')[:audit['options_each']] for q in questions):
        raise ValueError('Incomplete option table')
    if kind == 'cloze':
        blank_ids = [int(n) for n in re.findall(r'\((\d+)\)\s*_+', passage)]
        if blank_ids != list(range(1, row['questions'] + 1)):
            raise ValueError('Cloze material must contain every blank in order')
    if [q['number'] for q in questions] != list(range(1, row['questions'] + 1)):
        raise ValueError('Incomplete/reordered questions')
    table = []
    for line in review.splitlines():
        if not line.startswith('|'):
            continue
        cells = [c.strip() for c in line.strip('|').split('|')]
        if not re.match(r'^\d+(?:\s+[A-D])?$', cells[0]):
            continue
        table.append(cells)
    if len(table) != len(questions) or len(audit['author_answer_vector']) != len(questions):
        raise ValueError('Incomplete rationale table')
    for q, cells, answer in zip(questions, table, audit['author_answer_vector']):
        number = int(cells[0].split()[0])
        table_answer = cells[0].split()[1] if len(cells[0].split()) == 2 else (cells[1] if cells[1] in 'ABCD' else None)
        if number != q['number'] or (table_answer is not None and table_answer != answer):
            raise ValueError('Rationale/answer mismatch')
        q['answer'] = answer
        q['rationale'] = '；'.join(cells[2:] if table_answer and cells[1] == answer else cells[1:])
    # Some early tables print the answer only above the table.
    printed = re.search(r'答案：([^\n]+)', text)
    if printed and re.findall(r'[A-D]', printed[1]) != audit['author_answer_vector']:
        raise ValueError('Printed answer vector mismatch')
    return {
        'grade': row['grade'], 'label': label, 'focus': focus, 'kind': kind,
        'typeLabel': '完形填空' if kind == 'cloze' else '阅读理解',
        'id': row['id'], 'candidate': row['candidate'], 'author_check': row['author_check'],
        'specification_at_authoring': row['specification_at_authoring'],
        'anchor_group_ids': row['anchor_group_ids'],
        'passage': passage,
        'passageHtml': ''.join('<p>' + inline(p) + '</p>' for p in passage.split('\n\n')),
        'questions': questions, 'reviewText': review,
        'specification_filename': spec.name,
    }


def extract_language(row, choice):
    text = load_ref(row['candidate']).read_text()
    audit = json.loads(load_ref(row['author_check']).read_text())
    spec = load_ref(row['specification_at_authoring'])
    if (audit['candidate_sha256'] != row['candidate']['sha256'] or
            audit['specification_sha256'] != row['specification_at_authoring']['sha256'] or
            audit['grade'] != row['grade'] or audit['questions'] != row['questions']):
        raise ValueError('Language candidate/audit identity differs')
    review = text.split('\n## ', 2)[-1] if '<!-- passage' in text else text.split('\n## ', 1)[1]
    tables = [[c.strip() for c in line.strip('|').split('|')] for line in review.splitlines() if line.startswith('|')]
    tables = [cells for cells in tables if cells[0].isdigit()]
    vector = audit['author_answer_vector']
    if len(tables) != row['questions'] or len(vector) != row['questions']:
        raise ValueError('Incomplete language rationale table')
    questions = []
    bank = audit.get('word_bank', [])
    passage = ''
    passage_html = ''
    if audit.get('options_each') == 4:
        student = text[:text.index('\n## ')]
        for found in re.finditer(r'^(\d+)\. (.*?)(?=^\d+\. |\Z)', student, re.M | re.S):
            number, body = int(found[1]), found[2]
            options = re.findall(r'(?:^|\s)([A-D])\.\s*(.*?)(?=\s+[A-D]\.|$)', body, re.S)
            if [letter for letter, _ in options] != list('ABCD'):
                raise ValueError('Incomplete language choice options')
            stem = re.split(r'(?:^|\s)A\.\s', body, maxsplit=1)[0].strip()
            questions.append({'number': number, 'stem': stem, 'options': options, 'answer': vector[number - 1]})
        mode = 'choice'
        passage_html = '<p>本组由12道独立句子或完整问答组成，逐题阅读与作答。</p>'
    else:
        blocks = re.findall(r'<!-- passage(?::([A-Z]))?:start -->(.*?)<!-- passage(?::[A-Z])?:end -->', text, re.S)
        if not blocks:
            raise ValueError('Explicit language material boundary required')
        for part, material in blocks:
            material = material.strip()
            passage += ('\n\n' if passage else '') + (part + '\n' if part else '') + material
            passage_html += ('<h3>' + part + '</h3>' if part else '') + ''.join('<p>' + inline(p) + '</p>' for p in material.split('\n\n'))
        if [int(n) for n in re.findall(r'\((\d+)\)\s*_+', passage)] != list(range(1, row['questions'] + 1)):
            raise ValueError('Missing or reordered language blanks')
        if bank:
            if len(bank) != 10 or not all(word in text.split('<!-- passage:start -->')[0] for word in bank):
                raise ValueError('Incomplete displayed shared bank')
            passage_html = '<div class="bank"><strong>词库</strong><p>' + inline(' · '.join(bank)) + '</p></div>' + passage_html
        for number, forms in enumerate(vector, 1):
            if not isinstance(forms, list) or not forms or not all(isinstance(form, str) and form in review for form in forms):
                raise ValueError('Allowed form not present in author explanation')
            limit = audit.get('all_responses_limit_words')
            if number in audit.get('ungiven_oneword_slots', []):
                limit = 1
            if row['grade'] == 10 and not re.search(r'\(' + str(number) + r'\)\s*_+\s*\(', passage):
                limit = 1
            if limit and any(len(form.split()) > limit for form in forms):
                raise ValueError('Author reference violates the declared response limit')
            questions.append({'number': number, 'stem': '第' + str(number) + '空', 'options': [], 'knownForms': forms,
                              'maxWords': limit})
        mode = 'reference_form'
    if [q['number'] for q in questions] != list(range(1, row['questions'] + 1)):
        raise ValueError('Incomplete language response positions')
    for q, cells in zip(questions, tables):
        if q['number'] != int(cells[0]):
            raise ValueError('Language rationale order differs')
        answer_column = 2 if bank else 1
        if mode == 'choice' and cells[1] != q['answer']:
            raise ValueError('Language choice key differs')
        if mode == 'reference_form' and not any(form.strip() in q['knownForms'] for form in cells[answer_column].split('/')):
            raise ValueError('Printed primary form differs from author vector')
        q['rationale'] = '；'.join(cells[answer_column + 1:])
    return {'grade': row['grade'], 'label': choice['label'], 'focus': choice['focus'], 'kind': 'language',
            'typeLabel': choice['type_label'], 'instruction': choice['instruction'], 'responseMode': mode,
            'id': row['id'], 'candidate': row['candidate'], 'author_check': row['author_check'],
            'specification_at_authoring': row['specification_at_authoring'], 'anchor_group_ids': row['anchor_group_ids'],
            'passage': passage, 'passageHtml': passage_html, 'sharedBank': bank,
            'questions': questions, 'reviewText': review, 'specification_filename': spec.name}


TEMPLATE = r'''<!doctype html>
<html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>LingoTrip · 初高中出题效果</title>
<style>
:root{color-scheme:light;--ink:#203233;--muted:#637777;--line:#dbe3df;--green:#285e50;--paper:#fffefa}
*{box-sizing:border-box}body{margin:0;background:#f2f5ef;color:var(--ink);font:16px/1.6 system-ui,-apple-system,sans-serif}
header{max-width:1120px;margin:auto;padding:32px 24px 20px}.brand{font-size:13px;color:var(--green);font-weight:700;letter-spacing:.1em}h1{font-size:28px;line-height:1.3;margin:8px 0}header p{margin:8px 0;color:var(--muted)}
nav{display:flex;gap:8px;flex-wrap:wrap;margin:22px 0 0}button{font:inherit;cursor:pointer}nav button{border:1px solid var(--line);border-radius:22px;padding:7px 22px;background:var(--paper);color:var(--ink)}nav button[aria-pressed=true]{background:var(--green);border-color:var(--green);color:white}
main{max-width:1120px;margin:0 auto;padding:0 24px 36px}.task{background:var(--paper);border:1px solid var(--line);border-radius:18px;overflow:hidden}.requirement{display:flex;align-items:center;gap:12px;padding:20px 26px;border-bottom:1px solid var(--line)}.avatar{width:44px;height:44px;flex:none;border-radius:50%;background:#e4eee2;display:grid;place-items:center}.avatar svg{width:36px;height:36px}.requirement h2{margin:0;font-size:20px}.requirement p{margin:0;font-size:14px;color:var(--muted)}
.columns{display:grid;grid-template-columns:1fr 1fr}.passage{padding:10px 28px 20px;font:18px/1.85 Georgia,'Times New Roman',serif}.passage p{margin:16px 0}.questions{padding:22px 26px;border-left:1px solid var(--line)}fieldset{border:0;margin:0 0 24px;padding:0;min-width:0}legend{font-size:16px;font-weight:650;margin-bottom:10px;line-height:1.5}label{display:flex;align-items:flex-start;gap:10px;padding:9px 12px;border:1px solid var(--line);border-radius:10px;margin:7px 0;cursor:pointer;line-height:1.5}label:has(input:checked){background:#eef5ed;border-color:var(--green)}input{margin-top:5px;accent-color:var(--green)}label.correct{background:#edf5e9;border-color:#528243}label.wrong{background:#fff1ec;border-color:#bb7661}.explanation{padding:12px 15px;background:#f1f4ed;border-radius:10px;margin-top:10px;font-size:14px}.explanation p{margin:0 0 5px}.actions{display:flex;gap:10px;flex-wrap:wrap}.actions button{border:1px solid var(--line);background:white;border-radius:10px;padding:9px 16px;color:var(--ink)}.actions .primary{background:var(--green);border-color:var(--green);color:white}#result{font-size:15px;margin:12px 0}details{margin-top:20px;font-size:14px;color:var(--muted)}summary{cursor:pointer;color:var(--ink)}.review{background:#fffefa;border:1px solid var(--line);padding:15px 20px;border-radius:12px}.review p{margin:8px 0}.review a{color:var(--green)}code{overflow-wrap:anywhere;font-size:12px}.footnote{font-size:13px;color:var(--muted);margin-top:15px}button:focus-visible,input:focus-visible,summary:focus-visible{outline:3px solid #e5ae50;outline-offset:3px}[hidden]{display:none!important}
@media(max-width:760px){header{padding:22px 16px 16px}main{padding:0 12px 25px}h1{font-size:24px}.columns{grid-template-columns:1fr}.questions{border-left:0;border-top:1px solid var(--line);padding:20px}.passage{padding:8px 22px 18px}.requirement{padding:16px 20px}nav button{padding:6px 17px}.passage{font-size:17px}}
label.wrong:has(input:checked){background:#fff1ec;border-color:#bb7661}
.text-response{display:block}.answer-field{width:100%;margin:0;padding:9px 12px;font:inherit;border:1px solid var(--line);border-radius:7px;background:white;color:var(--ink)}.matched{background:#edf5e9;border-color:#528243}.unmatched{background:#fff8e7;border-color:#bda56a}.bank{font:15px/1.6 system-ui,sans-serif;border:1px solid var(--line);background:#f0f5ed;border-radius:10px;padding:12px 16px;margin:15px 0}.bank p{margin:6px 0 0}
</style>
<header><div class="brand">LINGOTRIP / LEARNING</div><h1>初高中出题效果</h1><p>六个年级，阅读、完形和语言运用各一组。先作答，再看参考与解析。</p><nav aria-label="选择年级" id="grades"></nav><nav aria-label="选择题型" id="types"></nav></header>
<main><section class="task"><div class="requirement"><span class="avatar" aria-hidden="true"><svg viewBox="0 0 40 40"><path fill="#3d6b59" d="M8 38c1-11 23-11 24 0"/><circle cx="20" cy="18" r="11" fill="#efc7a2"/><path fill="#524b42" d="M9 18C6 2 32 2 31 18l-7-8-3 6-8-1z"/><circle cx="16" cy="20" r="1"/><circle cx="24" cy="20" r="1"/><path d="M17 25q3 2 6 0" fill="none" stroke="#785b4b" stroke-width="1.2"/></svg></span><div><h2 id="grade-title"></h2><p id="instruction"></p></div></div><div class="columns"><article class="passage" id="passage" lang="en" aria-label="阅读材料"></article><div class="questions"><form id="quiz"></form><div class="actions"><button class="primary" id="submit" type="button">提交并查看解析</button><button id="reveal" type="button">直接看答案</button><button id="reset" type="button">重新作答</button></div><p id="result" role="status" aria-live="polite"></p></div></div></section>
<details class="review"><summary>查看本组命题依据</summary><div id="provenance"></div><p>这些是依据真卷结构与年级规格编写、经作者解题检查的样题。实际生产模型效果、独立教研与目标学生难度和用时仍待验证。</p><p>本次只看初一至高三。其他阶段及备考方向不纳入本次交付。</p></details>
<p class="footnote">题目情境为原创虚构；展示不预设限时。答案仅保存在当前页面，刷新即清除。</p></main>
<script id="showcase-data" type="application/json">__DATA__</script>
<script>
__INTERACTIONS__
</script></html>'''


def build(output):
    selection = json.loads((BASE / 'FirstRelease/showcase-selection-v0.4.json').read_text())
    core = json.loads(load_ref(selection['core_index']).read_text())
    extension = json.loads(load_ref(selection['extension_index']).read_text())
    overview = json.loads(load_ref(selection['source_overview']).read_text())
    data = []
    for choice in selection['items']:
        index = extension if choice.get('index') == 'extension' else core
        row = next(c for c in index['candidates'] if c['id'] == choice['id'])
        if choice.get('index') == 'extension':
            data.append(extract_extended(row, choice, load_ref, overview))
        else:
            data.append(extract_language(row, choice) if choice.get('kind') == 'language' else extract(row, choice['label'], choice['focus']))
    if sorted(set(g['grade'] for g in data)) != list(range(7, 13)):
        raise ValueError('Showcase must cover exactly grades7–12')
    for grade in range(7, 13):
        if sorted(g['kind'] for g in data if g['grade'] == grade and g['kind'] in ['reading', 'cloze', 'language']) != ['cloze', 'language', 'reading']:
            raise ValueError('Each grade must have one complete reading, cloze and language group')
    if len({g['id'] for g in data}) != len(data) or len({(g['grade'], g['kind']) for g in data}) != len(data):
        raise ValueError('Repeated showcase identity or ambiguous grade/type route')
    payload = json.dumps(data, ensure_ascii=False).replace('<', '\\u003c').replace('>', '\\u003e').replace('&', '\\u0026')
    output.mkdir(parents=True, exist_ok=True)
    page = TEMPLATE.replace('__DATA__', payload)
    interactions = (BASE / 'Tools/school_showcase_interactions.js').read_text()
    page = page.replace('__INTERACTIONS__', interactions)
    page = page.replace('六个年级，阅读、完形和语言运用各一组。先作答，再看参考与解析。',
                        '六个年级，完整阅读、完形、语言运用及选定配对、衔接、开放作答和写作。先作答，再看参考与要求。')
    page = page.replace('</header>', '<p class="footnote">入口只显示本页该年级的已审阅样题；未展示不表示该年级没有这种题型。</p></header>')
    page = page.replace('</style>', '.open-response label{display:block}.open-response textarea{display:block;resize:vertical;line-height:1.6}.fixed-opening{font:16px/1.65 Georgia,serif}.full-author-review{border-top:1px solid var(--line);padding-top:16px}.author-review{font:14px/1.65 system-ui,sans-serif;overflow-wrap:anywhere}.table-scroll{overflow-x:auto}.table-scroll table{border-collapse:collapse;width:100%;font:14px/1.6 system-ui,sans-serif}.table-scroll th,.table-scroll td{border:1px solid var(--line);padding:8px;text-align:left;min-width:110px}</style>')
    (output / 'index.html').write_text(page)
    # A human-readable companion keeps the full payload reviewable without JS.
    md = ['# 初高中多题型效果稿0.4', '', '六年级完整核心三类及选定共享候选、开放回答和写作；为已有作者稿的展示子集，不是生产入口模型实测。', '',
          '先读题，答案和解析放在折叠区。其他题型及标准见资料库FirstRelease统一入口。', '']
    for g in data:
        md += ['## ' + g['label'] + ' · ' + g['typeLabel'], '', g.get('instruction', '阅读短文，从各题/空选项中选出最佳答案。'), '']
        if g.get('sharedBank'):
            md += ['词库：' + ' · '.join(g['sharedBank']), '']
        md += [g['passage'], '']
        for q in g['questions']:
            md += [str(q['number']) + '. ' + q['stem'], '']
            md += [k + '. ' + v + '  ' for k, v in q['options']]
            md += ['']
        md += ['<details>', '<summary>答案、解析与命题依据</summary>', '']
        for q in g['questions']:
            answer = ' / '.join(q['knownForms']) if 'knownForms' in q else q.get('answer', '开放作答：按完整参考与暂定评分要求复核')
            md += [str(q['number']) + '. **' + answer + '**：' + q['rationale'], '']
        if g.get('reviewHtml'):
            md += [g['reviewText'], '']
        source_note = ('形式/评分参考（未配对）：' + g['sourceFormReference']['catalogue']['path'] +
                       '，源任务' + str(g['sourceFormReference']['task_number'])) if g.get('sourceFormReference') else '来源锚组：' + ' / '.join(g['anchor_group_ids'])
        md += [g['focus'], '', source_note, '',
               '作者题面：' + g['candidate']['path'], '',
               '创作规格：' + g['specification_at_authoring']['path'], '', '</details>', '']
    (output / 'SchoolSamples-v0.4.md').write_text('\n'.join(md))
    report = {'grades': sorted(set(g['grade'] for g in data)), 'groups': len(data),
              'questions': sum(len(g['questions']) for g in data),
              'reference_form_slots': sum(len(g['questions']) for g in data if g.get('responseMode') == 'reference_form'),
              'shared_bank_entries': sum(len(g.get('sharedBank', [])) for g in data),
              'shared_choice_entries': sum(len(g.get('sharedChoices', [])) for g in data),
              'open_response_tasks': sum(len(g['questions']) for g in data if g.get('responseMode') in ['open_review', 'writing_review']),
              'open_input_fields': sum(len(q['parts']) for g in data if g.get('responseMode') in ['open_review', 'writing_review'] for q in g['questions']),
              'automatic_semantic_scoring': False,
              'options': sum(len(q['options']) for g in data for q in g['questions']),
              'production_model_evaluation': False,
              'files': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in output.iterdir() if p.is_file() and p.name in ['index.html', 'SchoolSamples-v0.4.md']}}
    (output / 'build-report-v0.4.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(report, ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=REPO / 'build/english-benchmark-showcase')
    build(parser.parse_args().output.resolve())
