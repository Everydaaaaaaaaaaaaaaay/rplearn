#!/usr/bin/env python3
"""Arrange real App captures; retain original PNG bytes and hashes."""
import argparse
import hashlib
import html
import json
from pathlib import Path
import re
import shutil
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'build/unified-visual-implementation'
SHOTS = OUT / 'screenshots'
parser = argparse.ArgumentParser()
parser.add_argument('--attachments', action='append', default=[])
args = parser.parse_args()
SHOTS.mkdir(parents=True, exist_ok=True)
CAPTURE_NAMES = {'会员订阅页': 'subscription-light', '会员方案选择（示例价格）': 'subscription-plan-preview'}
for directory in args.attachments:
    source = Path(directory)
    for group in json.loads((source / 'manifest.json').read_text()):
        for item in group['attachments']:
            original = source / item['exportedFileName']
            if original.suffix.lower() == '.png':
                title = item['suggestedHumanReadableName'].split('_0_')[0]
                name = CAPTURE_NAMES.get(title) or re.sub(r'[^a-z0-9-]+', '-', title.lower()).strip('-') or original.stem
                shutil.copy2(original, SHOTS / (name + '.png'))
GROUPS = [
    ('新版活动', [('places-list-standard', '城市地点'), ('places-opening', '外出阅读'), ('places-resume', '暂停后继续')]),
    ('沟通与旅伴', [('unified-messages', '信息'), ('unified-contacts', '联系人'), ('unified-person', '旅伴资料')]),
    ('功能与故事', [('unified-me', '我的'), ('unified-settings', '设置'), ('unified-stories', '剧情目录')]),
    ('阅读与学习', [('london-03-choice', '剧情选择'), ('chat-light', '聊天'), ('role-learning', '角色学习')]),
    ('最大辅助字号', [('places-solitude-large', '独处结尾'), ('unified-me-large', '我的'), ('unified-settings-large', '设置')]),
    ('深色模式', [('messages-dark', '信息'), ('settings-dark', '设置'), ('chat-dark', '聊天')]),
    ('地图与会员', [('unified-map', '原生地图'), ('subscription-light', '会员订阅'), ('unified-subscription-dark', '深色会员页')]),
    ('深色功能页', [('unified-favorites-dark', '收藏夹搜索'), ('unified-signin-dark', '邮箱登录')]),
]
font = ImageFont.truetype('/System/Library/Fonts/Hiragino Sans GB.ttc', 22)
sections = []
for index, (title, pages) in enumerate(GROUPS, 1):
    pages = [(key, label) for key, label in pages if (SHOTS / (key + '.png')).exists()]
    if not pages:
        continue
    board = Image.new('RGB', (len(pages) * 426 + 24, 964), '#e5e5df')
    draw = ImageDraw.Draw(board)
    cards = []
    for col, (key, label) in enumerate(pages):
        with Image.open(SHOTS / (key + '.png')) as original:
            assert original.size == (1206, 2622), (key, original.size)
            board.paste(original.convert('RGB').resize((402, 874), Image.Resampling.LANCZOS), (24 + col * 426, 58))
        draw.text((24 + col * 426, 16), label, font=font, fill='#25352e')
        cards.append(f'<figure><a href="screenshots/{key}.png"><img loading="lazy" src="screenshots/{key}.png" alt="{html.escape(label)}"></a><figcaption>{html.escape(label)} · 点击查看原图</figcaption></figure>')
    board.save(OUT / f'board-{index}.png')
    sections.append(f'<h2>{title}</h2><section>{"".join(cards)}</section>')
records = [{'file': p.name, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(SHOTS.glob('*.png'))]
(OUT / 'captures.json').write_text(json.dumps(records, ensure_ascii=False, indent=2) + '\n')
(OUT / 'index.html').write_text('''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>咕游记 · 已实装界面</title><style>body{margin:0;background:#e5e5df;color:#25352e;font:16px -apple-system,sans-serif}main{max-width:1340px;margin:auto;padding:24px}h1{font-size:28px}h2{font-size:20px;margin-top:38px}section{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:24px}figure{margin:0}img{width:100%;display:block}figcaption{padding:12px 0}p{line-height:1.7}a{color:#42685d}@media(max-width:760px){section{grid-template-columns:1fr}}</style><main><h1>咕游记 · 已实装界面</h1><p>正式 App 代码的原生模拟器截图，没有生图或修图。使用 Debug 隔离预览；未发布新活动内容或赴约业务。点击每页查看 1206×2622 原图。</p>''' + ''.join(sections) + '<p><a href="captures.json">原图 SHA256</a></p></main></html>')
print(OUT / 'index.html')
