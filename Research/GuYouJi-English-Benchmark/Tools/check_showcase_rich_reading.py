#!/usr/bin/env python3
"""Check complete authored reading inputs and unchanged frozen34 payload."""
import argparse
import base64
import copy
import hashlib
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path
from build_school_showcase import BASE, load_ref
from grade_mode_evidence import load_ref as cache_ref
from showcase_extended_tasks import extract_extended
from showcase_rich_reading import extract_rich_reading


def payload(path):
    return json.loads(re.search(r'<script id="showcase-data" type="application/json">(.*?)</script>', path.read_text(), re.S)[1])


def check(page):
    previous = cache_ref({'path': 'build/english-benchmark-research-20261012/showcase-visual-page20261015ah-v0.1.html',
                          'sha256': '64e55b1cec7e54d3f1cdbb11e0d6453c22050b9f3d2500237df1ae87d6c1aaa7'})
    old, current = payload(previous), payload(page)
    if old != current[:34] or len(current) != 37 or sum(len(g['questions']) for g in current) != 243:
        raise ValueError('Frozen34 payload or complete-group totals differ')
    cases = [{'case': 'frozen34 payload identical;37groups243responses', 'passed': True}]
    selection = json.loads((BASE / 'FirstRelease/showcase-selection-v0.7.json').read_text())
    index = json.loads(load_ref(selection['extension_index']).read_text())
    overview = json.loads(load_ref(selection['source_overview']).read_text())
    for choice in selection['items'][-3:]:
        row = next(r for r in index['candidates'] if r['id'] == choice['id'])
        actual = extract_extended(row, choice, load_ref, overview)
        shown = next(g for g in current if g['id'] == row['id'])
        if json.loads(json.dumps(actual)) != shown:
            raise ValueError('Displayed complete reading differs')
        text = load_ref(row['candidate']).read_text()
        student = re.split(r'^## 作者(?:区|全组解答)\s*$', re.split(r'^## 学生(?:区|题面)\s*$', text, flags=re.M)[1], flags=re.M)[0].strip()
        review = re.split(r'^## 作者(?:区|全组解答)\s*$', text, flags=re.M)[1].strip()
        audit = json.loads(load_ref(row['author_check']).read_text())
        expected = student[:student.index(choice['first_question'])].strip()
        expected = re.sub(r'<!-- (?:passage|table):(?:start|end) -->\s*', '', expected)
        assert shown['passage'] == expected and '<!--' not in shown['passageHtml']
        assert len(shown['questions']) == 3
        assert all(len(q['options']) == audit['options_each'] for q in shown['questions'])
        assert [q['answer'] for q in shown['questions']] == audit['author_answer_vector']
        cases.append({'case': row['id']+' complete original student slice/options/vector', 'passed': True})
        if 'table_rows' in audit:
            assert shown['passageHtml'].count('<td>') == 18 and shown['passageHtml'].count('<th>') == 3
            assert all(x in shown['passageHtml'] for x in ['Minutes for one item', 'Items repaired', 'July–August', '8–10', 'Mei', 'At the end of each period'])
        else:
            image = shown['requiredPassageImages'][0]
            raw = base64.b64decode(image['src'].split(',', 1)[1], validate=True)
            assert hashlib.sha256(raw).hexdigest() == audit['graph_asset']['sha256']
            assert raw == load_ref(audit['graph_asset']).read_bytes()
            assert shown['passageHtml'].count('class="passage-image"') == 1
            assert image['src'] in shown['passageHtml'] and image['src'] in shown['passageMarkdown']
            svg = ET.fromstring(raw)
            desc = svg.findtext('{http://www.w3.org/2000/svg}desc')
            if row['grade'] == 12:
                assert shown['passageHtml'].count('<h3>') == 6
                assert all(v+'%' in desc for v in audit['graph_shares'])
                assert '54.5' not in desc and '72.1' not in desc and '54.5' not in shown['passage']
            else:
                assert shown['passageHtml'].count('<li value=') == 6
                assert all(str(v)+'%' in desc for v in audit['graph_percentages'])
                assert '102' not in shown['passage']+desc and '12人' not in shown['passage']+desc
                assert audit['graph_percent_sum'] == 255
        cases.append({'case': row['id']+' table/graph/card/list/accessible-input completeness', 'passed': True})
        variants = []
        def add(label, student_change=None, audit_change=None, choice_change=None):
            a, c = copy.deepcopy(audit), copy.deepcopy(choice)
            if audit_change:
                audit_change(a)
            if choice_change:
                choice_change(c)
            variants.append((label, student_change(student) if student_change else student, a, c))
        add('unknown question boundary', choice_change=lambda c:c.update(first_question='1. An invented question?'))
        add('last response absent', student_change=lambda s:re.sub(r'^3\. .*', '', s, flags=re.M | re.S))
        missing_option = {8: 'C. Listening to stories.', 9: 'C. 18.', 12: 'D. 72.1%.'}[row['grade']]
        add('missing option', student_change=lambda s:s.replace(missing_option, ''))
        add('key differs from rationale', audit_change=lambda a:a['author_answer_vector'].__setitem__(0,'A'))
        add('truncated rationale vector', audit_change=lambda a:a['author_answer_vector'].pop())
        if row['grade']==9:
            add('last table row absent', student_change=lambda s:re.sub(r'^\| November–December.*\n', '', s, flags=re.M))
            add('table column absent', student_change=lambda s:s.replace('| Period | Minutes for one item | Items repaired |','| Period | Items repaired |'))
            add('unbalanced passage marker', student_change=lambda s:s.replace('<!-- passage:end -->','',1))
        else:
            add('graph removed', student_change=lambda s:re.sub(r'^!\[.*\]\(.*\)\s*$', '', s, flags=re.M))
            add('wrong graph path', student_change=lambda s:s.replace('.svg)', '-missing.svg)'))
            add('graph digest differs', audit_change=lambda a:a['graph_asset'].update(sha256='0'*64))
            add('duplicate graph', student_change=lambda s:s.replace('![',re.search(r'^!\[.*\]\(.*\)$',s,re.M)[0]+'\n\n![',1))
            if row['grade']==8:
                add('activity list confused with question boundary', choice_change=lambda c:c.update(first_question='1. Listening to stories'))
                add('activity6 absent', student_change=lambda s:s.replace('6. Acting out short scenes',''))
            else:
                add('fifth proposal heading absent', student_change=lambda s:s.replace('#### Outside areas · Movement sensors','Outside areas · Movement sensors'))
        for label, s, a, c in variants:
            try:
                extract_rich_reading(s, review, a, c, row['candidate'], load_ref)
            except ValueError as error:
                cases.append({'case': row['id']+' reject '+label, 'passed': True, 'reason': str(error)})
            else:
                raise ValueError('Invalid complete reading admitted: '+label)
    return {'cases': cases, 'controls': len(cases), 'positive': 7, 'rejection': len(cases)-7,
            'groups':37, 'response_positions':243, 'new_original_groups':0, 'new_source_groups':0,
            'new_standalone_SVG_files':0, 'student_independent_commercial_or_production_validation':False}


if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--page',type=Path,required=True)
    p.add_argument('--report',type=Path,required=True)
    args=p.parse_args()
    result=check(args.page)
    args.report.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k!='cases'},ensure_ascii=False))
