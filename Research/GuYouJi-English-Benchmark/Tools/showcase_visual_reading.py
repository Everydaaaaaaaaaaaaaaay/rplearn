"""Bind the reviewed authored calendar and all four SVG choices to student input."""
import base64
import calendar
import html
import re
import xml.etree.ElementTree as ET
from showcase_extended_tasks import markdown_view


def prepare_visual_reading(group, audit, choice, load_ref):
    layout = choice['visual_layout']
    if group['grade'] != 7 or len(group['questions']) != 3:
        raise ValueError('Reviewed visual reading identity differs')
    if layout == 'calendar':
        year, month = audit['calendar_verified_year'], audit['calendar_verified_month']
        if '## ' + calendar.month_name[month] + ' ' + str(year) not in group['passage']:
            raise ValueError('Calendar title/year differs from reviewed input')
        rows = [[v.strip() for v in line.strip('|').split('|')] for line in group['passage'].splitlines()
                if line.startswith('|') and not re.fullmatch(r'[|\s:\-]+', line)]
        if not rows or rows[0] != ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'] or any(len(r) != 7 for r in rows):
            raise ValueError('Full seven-column calendar required')
        dates = [[int(v) if v else 0 for v in row] for row in rows[1:]]
        if dates != calendar.Calendar(firstweekday=6).monthdayscalendar(year, month):
            raise ValueError('Calendar cells moved, missing or changed')
        sundays = [r[0] for r in dates if r[0]]
        if sundays[2] != audit['third_sunday'] or sundays[2] - 2 != audit['registration_previous_friday']:
            raise ValueError('Event/registration dates differ')
        group['passageHtml'] = '<div class="calendar-reading">' + markdown_view(group['passage']) + '</div>'
        group['requiredCalendar'] = {'year': year, 'month': month, 'dates': dates,
                                     'current_clock_used': False}
    elif layout == 'image_choices':
        assets = audit['required_image_assets']
        if len(assets) != 4 or [(r['question_number'], r['option_label']) for r in assets] != [(3, k) for k in 'ABCD']:
            raise ValueError('All four ordered image choices required')
        question = group['questions'][2]
        if question['number'] != 3 or [k for k, _ in question['options']] != list('ABCD'):
            raise ValueError('Image response position differs')
        images = {}
        for (letter, text), asset in zip(question['options'], assets):
            embed = re.fullmatch(r'!\[([^\]]+)\]\(([^)]+)\)', text.strip())
            if not embed or embed[2] != asset['markdown_embed_path'] or not embed[1].startswith(letter + ': '):
                raise ValueError('Image embed/alternative description/letter differs')
            raw = load_ref(asset).read_bytes()
            svg = ET.fromstring(raw)
            if svg.tag != '{http://www.w3.org/2000/svg}svg' or svg.attrib.get('viewBox') != '0 0 300 180':
                raise ValueError('Reviewed SVG input shape differs')
            images[letter] = {'src': 'data:image/svg+xml;base64,' + base64.b64encode(raw).decode(),
                              'alt': embed[1], 'asset': {'path': asset['path'], 'sha256': asset['sha256']}}
        question['optionImages'] = images
        question['options'] = [(k, '') for k in 'ABCD']
        group['requiredImageAssets'] = [r['asset'] for r in images.values()]
    else:
        raise ValueError('Unknown reviewed visual layout')
    for question in group['questions']:
        question['stemHtml'] = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', html.escape(question['stem']))
    group['typeLabel'] = choice['type_label']
    group['instruction'] = choice['instruction']
    group['reviewHtml'] = markdown_view(group['reviewText'])
    group['visualInputRequired'] = True
    return group
