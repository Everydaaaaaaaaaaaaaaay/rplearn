"""Complete existing authored tasks for offline review; no semantic auto-scoring."""
import hashlib
import html
import json
import re
from pathlib import Path

BASE = Path(__file__).resolve().parents[1]


def ref(path):
    return {'path': str(path.relative_to(BASE)), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def markdown_view(text):
    """Escape source text and support only the authored headings/lists/tables used here."""
    def inline(value):
        value = html.escape(value)
        # Permit plain word underlines while keeping attributes and HTML escaped.
        value = re.sub(r'&lt;u&gt;([A-Za-z][A-Za-z -]*)&lt;/u&gt;', r'<u>\1</u>', value)
        value = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', value)
        return re.sub(r'`([^`]+)`', r'<code>\1</code>', value)
    result, paragraph, table = [], [], []
    def flush():
        if paragraph:
            result.append('<p>' + inline('\n'.join(paragraph)) + '</p>')
            paragraph.clear()
        if table:
            result.append('<div class="table-scroll"><table>')
            for i, line in enumerate(table):
                cells = [cell.strip() for cell in line.strip('|').split('|')]
                if all(re.fullmatch(r'[:\-\s]+', cell) for cell in cells):
                    continue
                tag = 'th' if i == 0 else 'td'
                result.append('<tr>' + ''.join('<' + tag + '>' + inline(c) + '</' + tag + '>' for c in cells) + '</tr>')
            result.append('</table></div>')
            table.clear()
    for line in text.splitlines():
        if line.startswith('|'):
            if paragraph:
                flush()
            table.append(line)
        elif not line.strip():
            flush()
        elif line.startswith('#'):
            flush()
            heading = re.match(r'^(#{1,6})\s+(.+)$', line)
            if not heading:
                raise ValueError('Malformed heading')
            result.append('<h3>' + inline(heading[2]) + '</h3>')
        else:
            if table:
                flush()
            paragraph.append(line)
    flush()
    return ''.join(result)


def extract_variable_cloze(student, review, audit, count):
    """Keep the complete printed cloze; reject truncation and key/table drift."""
    first = re.search(r'^1\. ', student, re.M)
    if not first:
        raise ValueError('Missing cloze choices')
    if '<!-- passage:start -->' in student:
        if student.count('<!-- passage:start -->') != 1 or student.count('<!-- passage:end -->') != 1:
            raise ValueError('Ambiguous cloze material boundaries')
        start = student.index('<!-- passage:start -->') + len('<!-- passage:start -->')
        end = student.index('<!-- passage:end -->')
        if not start < end < first.start() or student[end + len('<!-- passage:end -->'):first.start()].strip():
            raise ValueError('Cloze material/choice boundary order differs')
        material = student[start:end].strip()
    else:
        heading = re.search(r'^### .+$', student, re.M)
        if not heading or heading.start() > first.start():
            raise ValueError('Explicit cloze heading boundary required')
        material = student[heading.start():first.start()].strip()
    slots = [int(a or b) for a, b in re.findall(r'\((\d+)\)\s*_+|_+(\d+)_+', material)]
    expected = list(range(1, count + 1))
    if slots != expected:
        raise ValueError('Missing/reordered/extra cloze material slots')
    size = audit['options_each']
    if size not in [3, 4]:
        raise ValueError('Unsupported per-question candidate count')
    vector = audit.get('author_answer_vector', audit.get('complete_author_vector'))
    if not isinstance(vector, list) or len(vector) != count:
        raise ValueError('Incomplete cloze author vector')
    questions = []
    for m in re.finditer(r'^(\d+)\. (.*?)(?=^\d+\. |\Z)', student[first.start():], re.M | re.S):
        number, body = int(m[1]), m[2].strip()
        options = re.findall(r'(?:^|\s)([A-D])\.\s*(.*?)(?=\s+[A-D]\.|$)', body, re.S)
        if [k for k, _ in options] != list('ABCD')[:size] or any(not v.strip() for _, v in options):
            raise ValueError('Incomplete per-question cloze candidates')
        questions.append({'number': number, 'stem': '第' + str(number) + '空', 'options': options})
    if [q['number'] for q in questions] != expected:
        raise ValueError('Incomplete cloze response list')
    rows = []
    for line in review.splitlines():
        cells = [v.strip() for v in line.strip('|').split('|')]
        if line.startswith('|') and re.match(r'^\d+ [A-D](?:\s|$)', cells[0]):
            rows.append(cells)
    if len(rows) != count:
        raise ValueError('Incomplete cloze rationale rows')
    for q, answer, cells in zip(questions, vector, rows):
        identity = cells[0].split(maxsplit=2)
        if int(identity[0]) != q['number'] or identity[1] != answer or answer not in dict(q['options']):
            raise ValueError('Cloze key/rationale/choice differs')
        if len(cells) < 3 or not cells[1] or not cells[2]:
            raise ValueError('Missing cloze evidence or distractor explanation')
        q.update(answer=answer, rationale='；'.join(cells[1:]))
    return material, questions


def extract_extended(row, choice, load_ref, overview):
    text = load_ref(row['candidate']).read_text()
    audit = json.loads(load_ref(row['author_check']).read_text())
    if audit['candidate_sha256'] != row['candidate']['sha256'] or audit['grade'] != row['grade'] or audit['questions'] != row['questions']:
        raise ValueError('Extension candidate/audit identity differs')
    specification = audit.get('specification') or {'path': audit['specification_path'], 'sha256': audit['specification_sha256']}
    load_ref(specification)
    source_form_reference = None
    if 'source_group_id' in row:
        anchor = row['source_group_id']
        source = next(g for g in overview['groups'] if g['id'] == anchor)
        if source['grade'] != row['grade']:
            raise ValueError('Extension anchor belongs to another grade')
    else:
        catalogue = json.loads(load_ref(row['source_catalogue']).read_text())
        task = row['source_unpaired_task_number']
        if (row['grade'] != 10 or task not in [66, 67] or audit['source_task_number'] != task or
                catalogue['source_paper_acquisition_id'] != audit['source_paper_acquisition_id'] or
                catalogue['productive_task_components']['task_count'] != 2):
            raise ValueError('Unpaired source writing identity differs')
        source_form_reference = {'catalogue': row['source_catalogue'], 'task_number': task,
                                 'paper_acquisition_id': catalogue['source_paper_acquisition_id'],
                                 'paired_objective_answer_group': False}
        anchor = None
    student_heading = re.search(r'^## 学生(?:区|题面)\s*$', text, re.M)
    author_heading = re.search(r'^## 作者(?:区|全组解答)\s*$', text, re.M)
    if not student_heading or not author_heading or author_heading.start() <= student_heading.end():
        raise ValueError('Explicit student/author boundaries required')
    student = text[student_heading.end():author_heading.start()].strip()
    presentation_notes = [note for note in ['答题要求旁可放角色头像，无角色开场故事。'] if note in student]
    displayed_student = student
    for note in presentation_notes:
        displayed_student = displayed_student.replace(note, '')
    review = text[author_heading.end():].strip()
    questions, mode = [], choice['response_mode']
    rich_input = {}
    first_prompt = re.search(r'^1\. ', student, re.M)
    bank = []
    if mode == 'reading_choice':
        from showcase_rich_reading import extract_rich_reading
        if choice['kind'] != 'reading':
            raise ValueError('Reading input used by another task kind')
        material, questions, rich_input = extract_rich_reading(student, review, audit, choice, row['candidate'], load_ref)
        rule = None
    elif mode == 'per_question_choice':
        if choice['kind'] != 'cloze':
            raise ValueError('Only reviewed variable cloze mode supported')
        material, questions = extract_variable_cloze(student, review, audit, row['questions'])
        rule = None
    elif mode == 'shared_choice':
        vector = audit['author_answer_vector']
        if len(vector) != row['questions']:
            raise ValueError('Incomplete extension answer vector')
        if choice['kind'] == 'matching':
            bank = re.findall(r'^### ([A-D]) · (.+)$', student, re.M)
            if not first_prompt or [letter for letter, _ in bank] != list('ABCD') or audit['activity_cards'] != 4:
                raise ValueError('Missing activity cards')
            prompts = [(int(m[1]), m[2].strip()) for m in re.finditer(r'^(\d+)\. (.+)$', student, re.M)]
            material = student[:first_prompt.start()].strip()
        else:
            bank = re.findall(r'^([A-G])\. (.+)$', student, re.M)
            if len(bank) not in [5, 7] or [letter for letter, _ in bank] != list('ABCDEFG')[:len(bank)]:
                raise ValueError('Incomplete shared sentence candidates')
            slots = [int(n) for pair in re.findall(r'\*\*\[(\d+)\]\*\*|__(\d+)__', student) for n in pair if n]
            if slots != list(range(1, row['questions'] + 1)):
                raise ValueError('Missing or reordered insertion slots')
            prompts = [(i, '第' + str(i) + '空') for i in slots]
            material = student
        if [n for n, _ in prompts] != list(range(1, row['questions'] + 1)) or len(set(vector)) != len(vector):
            raise ValueError('Incomplete prompts or violation of author once rule')
        if '最多使用一次' not in student and '最多用一次' not in student:
            raise ValueError('Explicit authored reuse rule required')
        for number, prompt in prompts:
            if vector[number - 1] not in dict(bank):
                raise ValueError('Key outside candidate bank')
            questions.append({'number': number, 'stem': prompt,
                              'options': [(key, '选项 ' + key) for key, _ in bank],
                              'answer': vector[number - 1], 'rationale': '全组候选排除与衔接依据见下方完整作者审阅。'})
        rule = {'atMostOnce': True, 'sharedCandidateCount': len(bank), 'authoredRuleNotAssumedSourceRule': True}
    elif mode == 'open_review':
        if not first_prompt:
            raise ValueError('Missing complete open prompts')
        material = student[:first_prompt.start()].strip()
        prompts = [(int(m[1]), m[2].strip()) for m in re.finditer(r'^(\d+)\. (.+)$', student, re.M)]
        if [n for n, _ in prompts] != list(range(1, row['questions'] + 1)):
            raise ValueError('Open response count differs')
        for number, prompt in prompts:
            questions.append({'number': number, 'stem': prompt, 'options': [],
                              'parts': [{'label': '第' + str(number) + '题回答'}],
                              'rationale': '请按完整作者参考、可接受变体与暂定评分要求复核；本页不自动给分。'})
        rule = None
    elif mode == 'writing_review':
        if row['questions'] != 1 or audit.get('task_count', 1) != 1:
            raise ValueError('Writing remains one complete response task')
        material = displayed_student
        if choice.get('paragraphs') == 2:
            openings = audit['given_paragraph_starters']
            if len(openings) != 2 or audit['paragraph_count'] != 2 or not all(o in student for o in openings):
                raise ValueError('Missing two fixed paragraph openings')
            parts = [{'label': '第一段新增续写', 'opening': openings[0]}, {'label': '第二段新增续写', 'opening': openings[1]}]
            material = material.replace('[Continue the first paragraph here.]', '').replace('[Continue the second paragraph here.]', '')
        else:
            if 'Dear Alex,' not in student or 'Best regards,' not in student or 'Li Hua' not in student:
                raise ValueError('Missing fixed email greeting/signoff')
            parts = [{'label': '邮件正文'}]
            material = material.replace('[Write your email here.]', '')
        questions = [{'number': 1, 'stem': choice['response_label'], 'options': [], 'parts': parts,
                      'rationale': '一个完整写作任务；结合下方未评分作者示例与整体评分协议复核，本页不自动判档或打分。'}]
        rule = None
    else:
        raise ValueError('Unknown extended response mode')
    if not review or audit.get('independent_review') is not False or audit.get('production_admission') is not False:
        raise ValueError('Full author review and limits required')
    return {'id': row['id'], 'grade': row['grade'], 'label': choice['label'], 'kind': choice['kind'],
            'typeLabel': choice['type_label'], 'focus': choice['focus'], 'instruction': choice['instruction'],
            'responseMode': mode, 'candidate': row['candidate'], 'author_check': row['author_check'],
            'specification_at_authoring': specification, 'anchor_group_ids': [anchor] if anchor else [],
            'passage': material, 'passageHtml': markdown_view(material), 'questions': questions,
            'sharedChoices': bank, 'sharedRule': rule, 'wordTarget': choice.get('word_target'),
            'reviewText': review, 'reviewHtml': markdown_view(review), 'specification_filename': Path(specification['path']).name,
            'studentSliceSHA256': hashlib.sha256(student.encode()).hexdigest(),
            'presentationNotesExcludedFromStudentUI': presentation_notes,
            'sourceFormReference': source_form_reference,
            'independent_scoring': False, 'automatic_semantic_scoring': False, **rich_input}
