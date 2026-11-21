#!/usr/bin/env python3
"""Arrange unchanged native captures; write a local full-resolution gallery and hashes."""
import hashlib
import html
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = ROOT / 'build/unified-native-design'
SHOTS = OUT / 'screenshots'
GROUPS = [
    ('叙事与赴约', [('story', '剧情阅读'), ('meetup', '赴约故事'), ('appointment', '约定详情')]),
    ('经历与关系', [('summary', '约定总结'), ('memories', '共同记忆'), ('person', '角色详情')]),
    ('沟通', [('messages', '信息'), ('chat', '聊天'), ('contacts', '联系人')]),
    ('探索入口', [('home', '活动首页'), ('activities', '城市活动'), ('stories', '剧情目录')]),
    ('个人与学习', [('me', '我的'), ('learning', '学习'), ('settings', '设置')]),
    ('地图与适配', [('map', '原生地图'), ('settings-dark', '深色设置'), ('meetup-large', '大字赴约')]),
]
FONT = ImageFont.truetype('/System/Library/Fonts/Hiragino Sans GB.ttc', 22)
for i, (_, pages) in enumerate(GROUPS, 1):
    board = Image.new('RGB', (1302, 964), '#e5e5df')
    draw = ImageDraw.Draw(board)
    for j, (name, label) in enumerate(pages):
        original = Image.open(SHOTS / (name + '.png')).convert('RGB')
        assert original.size == (1206, 2622), (name, original.size)
        # Uniform 1/3 scale only. No device frame, crop, filters, or retouching.
        board.paste(original.resize((402, 874), Image.Resampling.LANCZOS), (24 + j * 426, 58))
        draw.text((24 + j * 426, 16), label, font=FONT, fill='#25352e')
    board.save(OUT / f'board-{i}.png')

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

shots = []
for p in sorted(SHOTS.glob('*.png')):
    with Image.open(p) as im:
        shots.append({'path': str(p.relative_to(ROOT)), 'size': list(im.size), 'sha256': sha(p)})
manifest = {
    'date': '2026-10-31',
    'device': 'iPhone 18 Pro', 'simulatorUDID': '659893A7-0822-43F4-8DA1-4A92E9C78814',
    'runtime': 'iOS 27.0', 'sdk': 'iPhoneSimulator 27.1',
    'points': [402, 874], 'scale': 3, 'dynamicType': 'large; -large captures use xxxLarge',
    'renderer': 'native UIKit/SwiftUI/MapKit, simulator screenshot',
    'postprocessing': 'none on screenshots; boards only uniformly scale and arrange',
    'inputs': json.loads((OUT / 'render-inputs.json').read_text()),
    'captures': shots,
}
(OUT / 'verification.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
sections = []
for title, pages in GROUPS:
    cards = ''.join(f'<figure><a href="screenshots/{name}.png"><img loading="lazy" src="screenshots/{name}.png" alt="{html.escape(label)}"></a><figcaption>{html.escape(label)} · <a href="screenshots/{name}.png">1206 × 2622 原图</a></figcaption></figure>' for name, label in pages)
    sections.append(f'<section><h2>{title}</h2><div class="grid">{cards}</div></section>')
extras = ''.join(f'<a href="screenshots/{p.name}">{p.stem}</a> ' for p in sorted(SHOTS.glob('*-*.png')))
(OUT / 'index.html').write_text('''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>咕游记 · 原生界面实施基准</title><style>body{margin:0;background:#e5e5df;color:#25352e;font:16px -apple-system,BlinkMacSystemFont,sans-serif}main{max-width:1340px;margin:auto;padding:32px 24px}h1{font-size:28px}h2{font-size:20px;margin-top:40px}.grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:24px}figure{margin:0}img{width:100%;height:auto;display:block}figcaption{padding:12px 0;font-size:14px}a{color:#42685d}p{line-height:1.7}@media(max-width:760px){.grid{grid-template-columns:1fr}}</style><main><h1>咕游记 · 原生界面实施基准 v1</h1><p>直接运行 SwiftUI 源码取得的模拟器截图。没有使用生图、重绘或修图。点击单页打开原始像素。页面使用本地示例数据，业务功能尚未接入正式 App。</p>''' + ''.join(sections) + '<h2>补充状态</h2><p>' + extras + '</p><p><a href="verification.json">截图及素材 SHA256 记录</a></p></main></html>')
print(OUT / 'index.html')
