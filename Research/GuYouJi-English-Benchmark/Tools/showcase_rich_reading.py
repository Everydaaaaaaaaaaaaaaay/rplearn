"""Preserve complete authored table/graph reading input, separate from questions."""
import base64
import html
import re
import xml.etree.ElementTree as ET
from pathlib import Path
from showcase_extended_tasks import markdown_view


def material_view(text, unordered_lists=False):
    """Keep numbered input lists distinct from the numbered response form."""
    if unordered_lists:
        result, cursor = [], 0
        for block in re.finditer(r'(?:^- [^\n]+(?:\n|$))+', text, re.M):
            result.append(material_view(text[cursor:block.start()]))
            entries=re.findall(r'^- (.+)$',block[0],re.M)
            result.append('<ul class="reading-requirements">'+''.join('<li>'+html.escape(value)+'</li>'for value in entries)+'</ul>')
            cursor=block.end()
        result.append(material_view(text[cursor:]))
        return ''.join(result)
    result, cursor = [], 0
    for block in re.finditer(r'(?:^\d+\. [^\n]+(?:\n|$))+', text, re.M):
        result.append(markdown_view(text[cursor:block.start()]))
        entries = re.findall(r'^(\d+)\. (.+)$', block[0], re.M)
        result.append('<ol class="reading-activities">' + ''.join(
            '<li value="' + n + '">' + html.escape(value) + '</li>' for n, value in entries) + '</ol>')
        cursor = block.end()
    result.append(markdown_view(text[cursor:]))
    return ''.join(result)


def extract_rich_reading(student, review, audit, choice, candidate, load_ref):
    # The activity list also starts with "1.". Only this reviewed full prompt
    # identifies the question boundary; a first-number heuristic loses the graph.
    first = list(re.finditer(r'^' + re.escape(choice['first_question']) + r'\s*$', student, re.M))
    if len(first) != 1 or not choice['first_question'].startswith('1. '):
        raise ValueError('Unique reviewed reading-question boundary required')
    material = student[:first[0].start()].strip()
    for tag in ['passage', 'table']:
        starts = material.count('<!-- ' + tag + ':start -->')
        ends = material.count('<!-- ' + tag + ':end -->')
        if starts != ends:
            raise ValueError('Unbalanced reading input markers')
    material = re.sub(r'<!-- (?:passage|table):(?:start|end) -->\s*', '', material)
    if '<!--' in material or not material.strip():
        raise ValueError('Unknown/empty reading input')
    count, size = audit['questions'], audit['options_each']
    vector = audit.get('author_answer_vector', audit.get('complete_author_vector'))
    if size not in [3, 4] or not isinstance(vector, list) or len(vector) != count:
        raise ValueError('Incomplete reading vector/option specification')
    questions = []
    for m in re.finditer(r'^(\d+)\. (.*?)(?=^\d+\. |\Z)', student[first[0].start():], re.M | re.S):
        body = m[2].strip()
        options = re.findall(r'(?:^|\s)([A-D])\.\s*(.*?)(?=\s+[A-D]\.|$)', body, re.S)
        if [k for k, _ in options] != list('ABCD')[:size] or any(not v.strip() for _, v in options):
            raise ValueError('Incomplete/reordered reading candidates')
        stem = re.split(r'^\s*A\.\s', body, maxsplit=1, flags=re.M)[0].strip()
        if not stem or stem == body:
            raise ValueError('Missing question/option boundary')
        questions.append({'number': int(m[1]), 'stem': stem, 'options': options})
    if [q['number'] for q in questions] != list(range(1, count + 1)):
        raise ValueError('Incomplete/reordered reading response list')
    rows = []
    for line in review.splitlines():
        cells = [v.strip() for v in line.strip('|').split('|')]
        if line.startswith('|') and re.match(r'^\d+(?:\s+[A-D](?:\s|，|$)|$)', cells[0]):
            rows.append(cells)
    if len(rows) != count:
        raise ValueError('Incomplete reading rationale table')
    for q, cells, answer in zip(questions, rows, vector):
        identity = re.fullmatch(r'(\d+)(?:\s+([A-D])(?:\s.*|，.*)?)?', cells[0])
        key = identity[2] if identity and identity[2] else cells[1]
        rationale = cells[1:] if identity and identity[2] else cells[2:]
        if not identity or int(identity[1]) != q['number'] or key != answer or answer not in dict(q['options']):
            raise ValueError('Reading key/rationale identity differs')
        if not rationale or any(not v for v in rationale):
            raise ValueError('Missing reading answer evidence')
        q.update(answer=answer, rationale='；'.join(rationale))
        q['stemHtml'] = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', html.escape(q['stem']))
    table_lines = [line for line in material.splitlines() if line.startswith('|') and not re.fullmatch(r'[|\s:\-]+', line)]
    if 'table_rows' in audit:
        cells = [[v.strip() for v in line.strip('|').split('|')] for line in table_lines]
        if len(cells) != audit['table_rows'] + 1 or any(len(r) != audit['table_columns'] for r in cells):
            raise ValueError('Complete reading table required')
    embeds = list(re.finditer(r'^!\[([^\]]+)\]\(([^)]+)\)\s*$', material, re.M))
    required, rendered, cursor, markdown = [], [], 0, material
    if bool(embeds) != bool(audit.get('graph_asset')) or len(embeds) > 1:
        raise ValueError('Required graph and printed embed differ')
    if audit.get('solution_cards') and len(re.findall(r'^#### ', material, re.M)) != audit['solution_cards']:
        raise ValueError('Complete proposal-card set required')
    if audit.get('target_format', {}).get('complete_numbered_list_axis_and_labels'):
        activity_numbers = [int(n) for n in re.findall(r'^(\d+)\. ', material, re.M)]
        if activity_numbers != list(range(1, audit['target_format']['categories'] + 1)):
            raise ValueError('Complete numbered activity list required')
    for embed in embeds:
        asset = audit['graph_asset']
        if (Path(candidate['path']).parent / embed[2]).as_posix() != asset['path']:
            raise ValueError('Graph embed and audited asset differ')
        raw = load_ref(asset).read_bytes()
        svg = ET.fromstring(raw)
        ns = '{http://www.w3.org/2000/svg}'
        if svg.tag != ns + 'svg' or not svg.findtext(ns + 'title') or not svg.findtext(ns + 'desc'):
            raise ValueError('Complete SVG and accessible description required')
        width, height = int(svg.attrib['width']), int(svg.attrib['height'])
        if width <= 0 or height <= 0 or svg.attrib.get('viewBox') != f'0 0 {width} {height}':
            raise ValueError('Original graph aspect ratio required')
        image = {'src': 'data:image/svg+xml;base64,' + base64.b64encode(raw).decode(),
                 'alt': embed[1], 'asset': {'path': asset['path'], 'sha256': asset['sha256']},
                 'width': width, 'height': height}
        required.append(image)
        rendered.append(material_view(material[cursor:embed.start()]))
        rendered.append('<figure class="reading-graph"><img class="passage-image" src="' + image['src'] +
                        '" alt="' + html.escape(image['alt'], quote=True) + '" width="' + str(width) +
                        '" height="' + str(height) + '"></figure>')
        markdown = markdown.replace(embed[0].strip(), '![' + image['alt'] + '](' + image['src'] + ')')
        cursor = embed.end()
    rendered.append(material_view(material[cursor:]))
    extras = {'passageHtml': ''.join(rendered), 'passageMarkdown': markdown,
              'requiredPassageImages': required, 'visualInputRequired': bool(required or table_lines)}
    return material, questions, extras
