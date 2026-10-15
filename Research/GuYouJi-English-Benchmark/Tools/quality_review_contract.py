"""Canonical printed responses keep authored Markdown and interactive fields equal."""


def response_markdown(tasks):
    result = []
    for q in tasks:
        result += [str(q['number'])+'. '+q['stem']]
        if q.get('options'):
            result += ['   '+letter+'. '+text for letter, text in q['options']]
        elif q.get('referenceAnswers'):
            result += ['   ____________________________________________________']
        result += ['']
    return '\n'.join(result).strip()
