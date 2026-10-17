#!/usr/bin/env python3
"""Build the timeboxed grade/family quality-review page from pinned authors."""
import argparse
import base64
import hashlib
import html
import json
import re
from urllib.parse import quote
import xml.etree.ElementTree as ET
from pathlib import Path
from grade_mode_evidence import BASE, REPO, load_ref
from showcase_rich_reading import material_view
from quality_review_contract import response_markdown

FROZEN_PAGE = {'path': 'build/english-benchmark-research-20261012/showcase-rich-page20261016a-v0.1.html',
               'sha256': 'b79899a6d4ca0fc6cc6262677d1cd592032cb9e81bb268e7b213233020fdc99d'}


def full_markdown_candidate(meta):
    text = load_ref(meta['candidate']).read_text()
    audit = json.loads(load_ref(meta['author_check']).read_text())
    if audit['candidate_sha256'] != meta['candidate']['sha256'] or audit['grade'] != meta['grade']:
        raise ValueError('Full Markdown author identity differs')
    student_start = list(re.finditer(r'^## 学生(?:题面|区)\s*$', text, re.M))
    author_start = list(re.finditer(r'^## 作者[^\n]*$', text, re.M))
    if len(student_start) != 1 or len(author_start) != 1 or student_start[0].end() >= author_start[0].start():
        raise ValueError('Explicit unique student/author boundaries required')
    student = text[student_start[0].end():author_start[0].start()].strip()
    teacher = text[author_start[0].end():].strip()
    typed_tasks = audit.get('review_response_tasks')
    if typed_tasks is not None:
        if student.count('<!-- responses:start -->') != 1 or student.count('<!-- responses:end -->') != 1:
            raise ValueError('Unique canonical response boundary required')
        left, tail = student.split('<!-- responses:start -->')
        printed, right = tail.split('<!-- responses:end -->')
        if printed.strip() != response_markdown(typed_tasks):
            raise ValueError('Printed full response list and interactive contract differ')
        if [q['number'] for q in typed_tasks] != list(range(1, audit['questions']+1)):
            raise ValueError('Incomplete/reordered canonical task list')
        student = left.strip()
        if right.strip():
            raise ValueError('Unbound student input after response list')
    student = re.sub(r'<!-- (?:passage|table):(?:start|end) -->\s*', '', student)
    if '<!--' in student:
        raise ValueError('Unknown input marker')
    assets = [audit[k] for k in ['graph_asset', 'figure_asset'] if audit.get(k)]
    images = []
    audio_assets = audit.get('audio_assets', [])
    audio_tracks = []

    def render_images(value):
        result, cursor = [], 0
        for embed in re.finditer(r'^!\[([^\]]+)\]\(([^)]+)\)\s*$', value, re.M):
            # Bound generated assets may live in the ignored research cache.
            # load_ref still enforces a portable path and the registered SHA.
            path = embed[2] if embed[2].startswith('build/') else (Path(meta['candidate']['path']).parent / embed[2]).as_posix()
            matching = [r for r in assets if r['path'] == path]
            if len(matching) != 1:
                raise ValueError('Unbound required input image')
            asset = matching[0]; raw = load_ref(asset).read_bytes(); svg = ET.fromstring(raw)
            width, height = int(svg.attrib['width']), int(svg.attrib['height'])
            if svg.tag != '{http://www.w3.org/2000/svg}svg' or svg.attrib.get('viewBox') != f'0 0 {width} {height}':
                raise ValueError('Original SVG shape required')
            image = {'src': 'data:image/svg+xml;base64,'+base64.b64encode(raw).decode(), 'alt': embed[1],
                     'asset': {'path': asset['path'], 'sha256': asset['sha256']}, 'width': width, 'height': height}
            images.append(image)
            result.append(material_view(value[cursor:embed.start()]))
            result.append('<figure><img class="passage-image" src="'+image['src']+'" alt="'+html.escape(image['alt'], quote=True)+
                          '" width="'+str(width)+'" height="'+str(height)+'"></figure>')
            cursor = embed.end()
        result.append(material_view(value[cursor:]))
        return ''.join(result)

    def render_input(value):
        if not audio_assets:
            return render_images(value)
        result, cursor = [], 0
        for embed in re.finditer(r'^\[([^\]]+)\]\(([^)]+\.m4a)\)\s*$', value, re.M):
            target = (BASE / Path(meta['candidate']['path']).parent / embed[2]).resolve()
            matches = [a for a in audio_assets if load_ref(a).resolve() == target]
            if len(matches) != 1:
                raise ValueError('Unbound required original audio')
            asset = matches[0]
            relative = Path(asset['path'])
            if relative.is_absolute() or '..' in relative.parts or relative.parts[0] != 'build':
                raise ValueError('Original audio must remain in the local research cache')
            track = {'src': '../../'+quote(relative.as_posix()), 'label': embed[1],
                     'asset': {'path': asset['path'], 'sha256': asset['sha256']},
                     'seconds': asset['seconds'], 'response_numbers': asset['response_numbers'],
                     'repeat_count': asset['repeat_count']}
            audio_tracks.append(track)
            result.append(render_images(value[cursor:embed.start()]))
            result.append('<figure class="listening-track"><figcaption>'+html.escape(embed[1])+
                          '</figcaption><audio class="listening-audio" controls preload="metadata" src="'+
                          html.escape(track['src'], quote=True)+'" aria-label="'+html.escape(embed[1], quote=True)+
                          '">浏览器不能播放此音频，请使用支持AAC的浏览器。</audio></figure>')
            cursor = embed.end()
        result.append(render_images(value[cursor:]))
        return ''.join(result)

    before = after = None
    closing = audit.get('target_format', {}).get('fixed_closing', '')
    if typed_tasks is not None:
        passage_html = render_input(student)
        questions = typed_tasks
        mode = 'quality_review_complete_tasks'
    elif meta['family'] == 'application_writing':
        if student.count('[在此写完整正文]') != 1 or audit['questions'] != 1:
            raise ValueError('One complete writing field required')
        left, right = student.split('[在此写完整正文]')
        before, after = render_input(left), render_input(right)
        if '\n' in closing:
            after = after.replace(html.escape(closing), html.escape(closing).replace('\n', '<br>'))
        questions = [{'number': 1, 'stem': '完整正文', 'options': [], 'parts': [{'label': '正文'}],
                      'rationale': '结合完整示例和任务要点复核；开放作答不自动打分。'}]
        mode = 'writing_review'
        passage_html = before + after
    elif meta['id'] == 'grade9-book-care-bank':
        vector = audit['author_answer_vector']
        if len(vector) != 5 or [int(n) for n in re.findall(r'\((\d+)\)\s*_+', student)] != [1, 2, 3, 4, 5]:
            raise ValueError('Complete five-response bank required')
        passage_html = render_input(student)
        questions = [{'number': n, 'stem': '第'+str(n)+'空', 'options': [], 'knownForms': forms,
                      'rationale': '词库项分配、允许形式和全部回填依据见下方作者说明。'} for n, forms in enumerate(vector, 1)]
        mode = 'reference_form'
    else:
        raise ValueError('Unprepared Markdown task family: '+meta['id'])
    if len(images) != len(assets):
        raise ValueError('Missing or duplicated audited graph input')
    if len(audio_tracks) != len(audio_assets):
        raise ValueError('Missing or duplicated original listening input')
    teacher_html = material_view(teacher)
    if '\n' in closing:
        teacher_html = teacher_html.replace(html.escape(closing), html.escape(closing).replace('\n', '<br>'))
    group = {'id': meta['id'], 'grade': meta['grade'], 'kind': meta['family'], 'typeLabel': '',
            'candidate': meta['candidate'], 'author_check': meta['author_check'], 'anchor_group_ids': meta['source_group_ids'],
            'responseMode': mode, 'passageHtml': passage_html, 'questions': questions,
            'studentBeforeHtml': before, 'studentAfterHtml': after, 'reviewHtml': teacher_html,
            'reviewText': teacher, 'requiredPassageImages': images, 'author_review_not_independent': True}
    if audio_tracks:
        group['requiredAudioAssets'] = audio_tracks
    if meta['family']=='listening_double_matching':
        group['fixedSharedBank'] = True
    return group


def build(matrix_path, output, historical_scope=False):
    matrix = json.loads(matrix_path.read_text())
    if matrix['scope'] != 'grades7_to12_timeboxed_quality_review_inventory' or len(matrix['cells']) != 144:
        raise ValueError('Review matrix scope differs')
    policy_path = BASE / 'FirstRelease/CurrentTaskScope-2026-10-16.json'
    policy = None if historical_scope else json.loads(policy_path.read_text())
    paused = set(policy['paused_families']) if policy else set()
    frozen = load_ref(FROZEN_PAGE).read_text()
    prior = json.loads(re.search(r'<script id="showcase-data" type="application/json">(.*?)</script>', frozen, re.S)[1])
    previous = {g['id']: g for g in prior}; groups, cells = {}, []
    for cell in matrix['cells']:
        if cell['family'] in paused:
            continue
        state, group = cell['delivery_state'], None
        if state in ['existing_complete_candidate_needs_review_UI', 'author_prototype_source_mode_pending']:
            meta = next(c for c in cell['existing_authored_candidates'] if c['id'] == cell['selected_representative_id'])
            load_ref(meta['candidate']); load_ref(meta['author_check'])
            if meta['id'] in previous:
                group = previous[meta['id']]
                if group['candidate'] != meta['candidate'] or group['grade'] != cell['grade']:
                    raise ValueError('Frozen preview and current author differ')
            else:
                group = full_markdown_candidate(meta)
            if group['id'] in groups:
                raise ValueError('One author reused for multiple grade/family cells')
            groups[group['id']] = group
        cells.append({'grade': cell['grade'], 'family': cell['family'], 'label': cell['label'],
                      'observed': cell['observation_state'] == 'observed', 'state': state,
                      'groupId': group['id'] if group else None})
    payload = {'version': '0.1', 'matrix_version': matrix['version'], 'cells': cells, 'groups': groups,
               'grades': list(range(7, 13)), 'preview_cells': len(groups), 'source_positive_cells': sum(c['observed'] for c in cells),
               'current_scope_policy': {'path': str(policy_path.relative_to(BASE)), 'sha256': hashlib.sha256(policy_path.read_bytes()).hexdigest()} if policy else None,
               'paused_subjective_families': sorted(paused),
               'preview_is_not_independent_quality_pass': True,
               'source_form_representative_cells': sum(c['state']=='existing_complete_candidate_needs_review_UI' for c in cells),
               'prototype_source_mode_pending_cells': sum(c['state']=='author_prototype_source_mode_pending' for c in cells)}
    encoded = json.dumps(payload, ensure_ascii=False).replace('<', '\u003c').replace('>', '\u003e').replace('&', '\u0026')
    template = (BASE / 'Tools/quality_review_template.html').read_text()
    page = template.replace('__REVIEW_DATA__', encoded).replace('__REVIEW_SCRIPT__', (BASE / 'Tools/quality_review_interactions.js').read_text())
    output.mkdir(parents=True, exist_ok=True); (output / 'index.html').write_text(page)
    report = {'preview_grade_family_cells': len(groups), 'source_positive_grade_family_cells': payload['source_positive_cells'],
              'unknown_grade_family_cells': sum(not c['observed'] for c in cells), 'complete_authored_tasks': len(groups),
              'paused_subjective_families': sorted(paused),
              'paused_historical_preview_cells': sum(c['family'] in paused and c['observation_state']=='observed' for c in matrix['cells']),
              'response_positions': sum(len(g['questions']) for g in groups.values()),
              'historical_timeboxed_authored_groups': matrix.get('new_timeboxed_authored_groups', 0),
              'source_form_representative_cells': payload['source_form_representative_cells'],
              'prototype_source_mode_pending_cells': payload['prototype_source_mode_pending_cells'],
              'all_current_source_observed_cells_have_preview': len(groups) == payload['source_positive_cells'] and not payload['prototype_source_mode_pending_cells'],
              'deterministic_marking_production_validated': False,
              'independent_student_commercial_or_production_validated': False,
              'index_html_sha256': hashlib.sha256(page.encode()).hexdigest()}
    (output / 'build-report-v0.1.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps(report, ensure_ascii=False))


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--matrix', type=Path, required=True)
    p.add_argument('--output', type=Path, default=REPO / 'build/english-benchmark-quality-review')
    p.add_argument('--historical-scope', action='store_true', help='Reproduce the historical unfiltered delivery only')
    args = p.parse_args(); build(args.matrix.resolve(), args.output.resolve(), args.historical_scope)
