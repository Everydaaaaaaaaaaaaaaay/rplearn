"""Canonical printed responses keep authored Markdown and interactive fields equal."""


def response_markdown(tasks):
    result = []
    for q in tasks:
        result += [str(q['number'])+'. '+q['stem']]
        if q.get('options'):
            for letter,text in q['options']:
                if q.get('optionImageAssets'):
                    from quality_review_images import option_alt
                    asset=q['optionImageAssets'][letter]
                    if not asset['path'].startswith('build/'):raise ValueError('Portable bound owned-image path required')
                    text='!['+option_alt(q['number'],letter)+'](../../../../'+asset['path']+')'
                result += ['   '+letter+'. '+text]
        elif any(p.get('opening') for p in q.get('parts', [])):
            for part in q['parts']:
                result += ['   '+part['opening'], '   [在此续写本段]']
        elif q.get('referenceAnswers'):
            result += ['   ____________________________________________________']
        result += ['']
    return '\n'.join(result).strip()
