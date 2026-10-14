#!/usr/bin/env python3
"""Reconcile current source/author members and totals; never judge English or rights.

Only the specified current bundle is checked. Frozen historical inconsistencies remain
available as evidence rather than being rewritten or treated as current admission.
"""
import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path

BASE = Path(__file__).resolve().parents[1]
REPO = BASE.parents[1]


def validate(bundle_path):
    checked = []
    try:
        def load_ref(ref):
            relative = Path(ref['path'])
            if relative.is_absolute() or '..' in relative.parts:
                raise ValueError('nonportable or escaping reference')
            allowed = REPO / 'build' if relative.parts and relative.parts[0] == 'build' else BASE
            path = REPO / relative if allowed == REPO / 'build' else BASE / relative
            if allowed.resolve() not in path.resolve().parents or not path.is_file():
                raise ValueError('missing or outside benchmark reference: ' + str(relative))
            if hashlib.sha256(path.read_bytes()).hexdigest() != ref['sha256']:
                raise ValueError('reference digest differs: ' + str(relative))
            checked.append(str(relative))
            return path

        def refs(value):
            if isinstance(value, dict):
                if 'path' in value and 'sha256' in value:
                    load_ref(value)
                for child in value.values():
                    refs(child)
            elif isinstance(value, list):
                for child in value:
                    refs(child)

        bundle = json.loads(Path(bundle_path).read_text())
        refs(bundle)
        expected = []
        grade_layers = {}
        for key, lane, header in [
            ('core_index', 'core', 'core'),
            ('supplement_index', 'open_language_supplement', 'supplement'),
            ('authored_extension_index', 'authored_extension', 'extension'),
        ]:
            index = json.loads(load_ref(bundle[key]).read_text())
            refs(index)
            members = index['candidates']
            if not isinstance(members, list) or not members:
                raise ValueError('empty or invalid current author index: ' + key)
            counts = Counter()
            points = Counter()
            for row in members:
                author = json.loads(load_ref(row['author_check']).read_text())
                refs(author)
                grade = row.get('grade', author.get('grade'))
                n = row.get('questions', author.get('questions'))
                if type(grade) is not int or type(n) is not int or n <= 0:
                    raise ValueError('grade/count must be positive integers')
                if grade != author['grade'] or n != author['questions']:
                    raise ValueError('member grade/count differs from author evidence')
                candidate = load_ref(row['candidate'])
                if row['candidate']['path'] != author['candidate_path'] or row['candidate']['sha256'] != author['candidate_sha256']:
                    raise ValueError('author/current candidate relation differs')
                counts[grade] += 1
                points[grade] += n
                expected.append((row['id'], lane, grade, row.get('author_kind', author.get('kind')),
                                 n, row['candidate'], row['author_check']))
            actual_points = sum(points.values())
            if key == 'authored_extension_index':
                if type(index.get('family_count')) is not int or index['family_count'] != len(members):
                    raise ValueError('extension family_count differs from actual members')
                if type(index.get('response_count')) is not int or index['response_count'] != actual_points:
                    raise ValueError('extension response_count differs from actual members')
            if bundle[header + '_authored_materials'] != len(members) or bundle[header + '_authored_responses'] != actual_points:
                raise ValueError('bundle layer totals differ: ' + key)
            grade_layers[header] = (counts, points)
        ids = [r[0] for r in expected]
        if len(ids) != len(set(ids)):
            raise ValueError('duplicate current author family identities')
        if bundle['total_current_material_families'] != len(expected) or bundle['total_current_authored_responses'] != sum(r[4] for r in expected):
            raise ValueError('bundle totals differ from actual current members')

        mode = json.loads(load_ref(bundle['response_family_overview']).read_text())
        refs(mode)
        actual = [(r['candidate_family_id'], r['lane'], r['grade'], r['declared_author_kind'],
                   r['response_points'], r['candidate'], r['author_check']) for r in mode['candidates']]
        if actual != expected or mode['material_families'] != len(actual) or mode['response_points'] != sum(r[4] for r in actual):
            raise ValueError('response members or total differ from current indexes')
        families = Counter(r['response_family'] for r in mode['candidates'])
        responses = Counter()
        for row in mode['candidates']:
            responses[row['response_family']] += row['response_points']
        if len(mode['response_family_totals']) != len(families) or any(
            row['material_families'] != families[row['response_family']] or
            row['response_points'] != responses[row['response_family']]
            for row in mode['response_family_totals']
        ):
            raise ValueError('response family totals differ from actual members')
        if mode['index_refs'] != [bundle[k] for k in ['core_index','supplement_index','authored_extension_index']]:
            raise ValueError('response overview bound to other indexes')
        for grade in bundle['grades']:
            g = grade['grade']
            for header, (counts, points) in grade_layers.items():
                grade_header = 'expansion' if header == 'extension' else header
                if grade[grade_header + '_materials'] != counts[g] or grade[grade_header + '_authored_responses'] != points[g]:
                    raise ValueError('grade layer totals differ')

        source = json.loads(load_ref(bundle['source_overview']).read_text())
        refs(source)
        if (bundle['source_group_instances'], bundle['source_response_references'], bundle['parent_paper_identities']) != (
            source['group_instance_count'], source['source_response_count'], source['parent_paper_identity_count']
        ):
            raise ValueError('source totals differ from selected source overview')
        return {'current_member_and_total_bindings_valid': True, 'errors': [],
                'families': len(expected), 'response_points': sum(r[4] for r in expected),
                'response_family_count': len(families), 'reference_checks_including_repeats': len(checked),
                'model_called': False, 'independent_English_student_or_rights_validation': False}
    except (KeyError, TypeError, ValueError, OSError, IndexError) as error:
        return {'current_member_and_total_bindings_valid': False,
                'errors': [str(error) or type(error).__name__], 'reference_checks_including_repeats': len(checked),
                'model_called': False, 'independent_English_student_or_rights_validation': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--index', type=Path, required=True)
    args = parser.parse_args()
    result = validate(args.index)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    raise SystemExit(0 if result['current_member_and_total_bindings_valid'] else 1)
