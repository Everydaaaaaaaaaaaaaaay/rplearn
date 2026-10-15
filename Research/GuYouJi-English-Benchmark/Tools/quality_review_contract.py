"""Canonical printed responses keep authored Markdown and interactive fields equal."""


def response_markdown(tasks):
    result = []
    for q in tasks:
        result += [str(q['number'])+'. '+q['stem']]
        if q.get('options'):
            result += ['   '+letter+'. '+text for letter, text in q['options']]
        elif any(p.get('opening') for p in q.get('parts', [])):
            for part in q['parts']:
                result += ['   '+part['opening'], '   [在此续写本段]']
        elif q.get('referenceAnswers'):
            result += ['   ____________________________________________________']
        result += ['']
    return '\n'.join(result).strip()
