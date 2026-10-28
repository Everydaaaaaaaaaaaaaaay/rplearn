"""Serialize explicitly authored target/drawing meanings; never invent answer keys."""
from pathlib import Path
import hashlib
import json
from datetime import datetime

ROOT = Path(__file__).resolve().parents[6]
DIRECTORY = Path(__file__).parent
SOURCES = DIRECTORY.parent / 'sources'
# The order below is the visible A–D drawing order, independently checked after raster rendering.
definitions = [
    ('school', '文具图卡：铅笔、尺子、橡皮与书', 'School Tools', [
        ('a pencil', '带石墨笔尖、木杆和顶端橡皮的铅笔'), ('a ruler', '有等距刻度的直尺'), ('an eraser', '独立的双色块状橡皮'), ('a book', '摊开后有左右书页的书')]),
    ('pets', '动物图卡：猫、狗、鱼与鸟', 'Four Animals', [
        ('a cat', '有尖耳、胡须和猫鼻的猫脸'), ('a dog', '有垂耳和突出鼻口部的狗脸'), ('a fish', '有鳍、尾巴并横向游动的鱼'), ('a bird', '有喙、翅膀和两只脚的鸟')]),
    ('fruit', '水果图卡：苹果、香蕉、梨与橙子', 'Fruit Cards', [
        ('an apple', '顶端凹入、带果梗的红苹果'), ('a banana', '细长弯曲、两头有果梗的香蕉'), ('a pear', '上窄下宽的绿色梨'), ('an orange', '圆形且表面有小斑点的橙子')]),
    ('body', '身体图卡：眼睛、耳朵、手与鼻子', 'Body Parts', [
        ('an eye', '中间有瞳孔和虹膜的眼睛'), ('an ear', '带耳廓和内部弯曲轮廓的耳朵'), ('a hand', '有五根手指和手掌纹的手'), ('a nose', '有鼻梁和两个鼻孔的鼻子')]),
    ('play', '游戏用品图卡：球、风筝、跳绳与滑板', 'Things for Play', [
        ('a ball', '有黑白拼块的圆球'), ('a kite', '有十字骨架和尾巴的菱形风筝'), ('a jump rope', '两端有握柄的弯曲跳绳'), ('a skateboard', '下方装轮子的长形滑板')]),
    ('room', '房间图卡：椅子、桌子、门与窗', 'In a Room', [
        ('a chair', '有靠背、座面和椅腿的椅子'), ('a table', '有宽桌面和四条桌腿的桌子'), ('a door', '有门框和把手的门'), ('a window', '有交叉窗框和玻璃反光的窗户')]),
    ('bedside', '卧室图卡：床、枕头、台灯与钟', 'Beside the Bed', [
        ('a bed', '有两端床架和条纹床垫的床，未画出枕头'), ('a pillow', '带缝边、四周柔软凹曲的独立枕头'), ('a lamp', '有灯罩、灯杆和底座的台灯'), ('a clock', '有圆形表盘和指针的钟')]),
    ('shapes', '形状图卡：圆形、三角形、正方形与长方形', 'Shape Cards', [
        ('a circle', '没有角的圆形'), ('a triangle', '有三条边和三个角的三角形'), ('a square', '四条边一样长的正方形'), ('a long rectangle', '明显宽于高度、不是正方形的长方形')]),
]
assets = {a['name']: a for a in json.loads((DIRECTORY / 'primary1-visual-002.assets.json').read_text())}
boundary = '明确逐词创作的原创四图配词任务，只借用已核来源的四图四回应形式；作者逐图检查可辨识性、唯一答案和其他三图的排除理由。基础词汇会在新视觉辨识任务中复现，不将复现当成新教学词汇；不声称独立教师、儿童识图或学生难度标定。'
source = dict(createdAt=datetime.now().astimezone().isoformat(), reviewBoundary=boundary, imageAssets=[], units=[])
reviews = []
for number, (name, title, english_title, words) in enumerate(definitions):
    asset = assets[name]
    notes = '在768×512原图与缩略联系表中检查四图和字母。无英文词汇或答案标记；同一张图卡只作一组四回应，不通过改名、重排或数量变化重复计组。'
    if name == 'body':
        notes += '初稿的脚形与手掌相似，未入题库；改为可明确识别的鼻子后重新看图审核。'
    if name == 'bedside':
        notes += '床图去除枕头，避免a pillow同时可匹配床图和独立枕头图。'
    if name == 'shapes':
        notes += '长方形题面明确long rectangle，避免把正方形也按广义矩形理解。'
    source['imageAssets'].append({**{k: asset[k] for k in ['id','sha256','byteSize','width','height','contentType']}, 'description': title + '；A至D依次为' + ', '.join(w[0] for w in words), 'source': 'Owned original SVG drawing: Backend/config/learning/expansions/2026-10-28/media-sources/' + asset['source'], 'reviewedBy': 'Codex author image and key review', 'reviewedAt': datetime.now().astimezone().date().isoformat(), 'reviewNotes': notes})
    identity = 'primary1.' + name + '-picture-cards-002'
    questions, audits = [], []
    # Explicit target order varies; each answer still points to its visible original card.
    for answer in [2, 0, 3, 1]:
        word, meaning = words[answer]
        rationale = '；'.join(f'{chr(65+i)}图为{description}' for i, (_, description) in enumerate(words)) + f'。题面{word}唯一对应{chr(65+answer)}，另外三图不具备该词所指的对象或特征。'
        questions.append(dict(prompt=word, options=['Picture A','Picture B','Picture C','Picture D'], answer=answer, explanation=rationale))
        audits.append(dict(prompt=word, answerLetter=chr(65+answer), evidence=meaning, distractorAudit=rationale))
    source['units'].append(dict(id=identity, sourceUnitId='original.primary1-four-picture-matches', level='primary1', family='word_picture_matching', title=title, minutes=4, instruction='Look at the four picture cards. Match each word or phrase to one picture. Use each letter once.', materials=[dict(id='cards', title=english_title, text='Look at cards A, B, C and D. Choose the picture that matches each word or phrase.', materialImages=[dict(assetId=asset['id'], label='Picture cards A to D')], questions=questions)]))
    reviews.append(dict(id=identity, status='approved', findings=[notes, 'Compared with the old picture/count/colour/dimension catalog: these are full category-discrimination sheets, not number/name substitutions. Some basic vocabulary repeats intentionally; no new-vocabulary or independent visual-sample count claimed.'], questionAudits=audits))
raw = (json.dumps(source, ensure_ascii=False, indent=2) + '\n').encode()
target = SOURCES / 'primary1-visual-002.json'
if target.exists():
    raise ValueError('Authoring source already exists; preserve its bytes')
target.write_bytes(raw)
review = dict(sourceSHA256=hashlib.sha256(raw).hexdigest(), reviewKind='author-self-review', reviewer='Codex same author; no independent teacher or child-panel calibration', reviewedAt=datetime.now().astimezone().date().isoformat(), units=reviews)
target.with_suffix('.review.json').write_text(json.dumps(review,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(dict(groups=len(reviews),responses=32,sourceSHA256=review['sourceSHA256'])))
