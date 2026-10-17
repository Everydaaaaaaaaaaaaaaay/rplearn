"""SHA-bound owned option images; encoded only in ignored display output."""
import base64
import copy
import xml.etree.ElementTree as ET
from grade_mode_evidence import load_ref


def option_alt(number,letter):return '第'+str(number)+'题'+letter+'图'


def attach_option_images(group):
    assets=[]
    for q in group['questions']:
        refs=q.get('optionImageAssets')
        if not refs:continue
        letters=[k for k,_ in q['options']]
        if list(refs)!=letters or len({r['sha256'] for r in refs.values()})!=len(letters):
            raise ValueError('Missing, reordered or identical image candidates')
        images={}
        for letter in letters:
            ref=refs[letter];raw=load_ref(ref).read_bytes();svg=ET.fromstring(raw)
            width,height=int(svg.attrib['width']),int(svg.attrib['height'])
            if svg.tag!='{http://www.w3.org/2000/svg}svg' or width<=0 or height<=0 or svg.attrib.get('viewBox')!=f'0 0 {width} {height}':
                raise ValueError('Full owned SVG dimensions required')
            if any(n.tag.split('}')[-1]in {'script','image','foreignObject'} or any(k.lower().startswith('on') or k.split('}')[-1]=='href' for k in n.attrib)for n in svg.iter()):
                raise ValueError('External or active image input is not admitted')
            image=dict(src='data:image/svg+xml;base64,'+base64.b64encode(raw).decode(),alt=option_alt(q['number'],letter),asset=ref,width=width,height=height)
            images[letter]=image;assets.append(ref)
        q['optionImages']=images
    if assets:group['requiredImageAssets']=assets
    return group


def without_derived_images(questions):
    return [{k:v for k,v in q.items()if k!='optionImages'} for q in questions]


def check_option_images(group):
    expected=copy.deepcopy(group);expected['questions']=without_derived_images(expected['questions']);expected.pop('requiredImageAssets',None)
    attach_option_images(expected)
    assert group['questions']==expected['questions']
    assert group.get('requiredImageAssets',[])==expected.get('requiredImageAssets',[])
    return len(expected.get('requiredImageAssets',[]))
