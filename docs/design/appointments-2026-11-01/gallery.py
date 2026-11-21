#!/usr/bin/env python3
"""Arrange unchanged native App screenshots; no image synthesis or retouching."""
import argparse
import hashlib
import html
import json
from pathlib import Path
import re
import shutil
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'build/appointments-2026-11-01'
SHOTS = OUT / 'screenshots'
SHOTS.mkdir(parents=True, exist_ok=True)
parser = argparse.ArgumentParser()
parser.add_argument('--attachments', action='append', required=True)
args = parser.parse_args()
for directory in args.attachments:
    source = Path(directory)
    for group in json.loads((source / 'manifest.json').read_text()):
        test = group['testIdentifier']
        prefix = 'large' if 'Maximum' in test else 'retry' if 'FailedContinuation' in test else 'standard'
        for item in group['attachments']:
            original = source / item['exportedFileName']
            title = item['suggestedHumanReadableName'].split('_0_')[0]
            if original.suffix.lower() != '.png' or not title.startswith('appointment-'):
                continue
            name = prefix + '-' + re.sub(r'[^a-z0-9-]+', '-', title.lower()).strip('-')
            shutil.copy2(original, SHOTS / (name + '.png'))
groups = [
    ('原有界面上的赴约', [('standard-appointment-01-confirmed-local-time','约定与当地时间'),('standard-appointment-02-original-paper-reader','沿用原剧情阅读'),('standard-appointment-06-independent-summary','独立总结')]),
    ('实际路径', [('standard-appointment-03-bilingual-native-input','中英文自定义输入'),('standard-appointment-04-actual-bilingual-history','实际选择与后果'),('standard-appointment-05-paused-resume','暂停与继续')]),
    ('最大辅助字号', [('large-appointment-max-text-choice-scroll','可滚动选择'),('large-appointment-max-text-keyboard-send-reachable','键盘与发送'),('large-appointment-max-text-summary-memory-controls','总结与管理入口')]),
    ('失败恢复', [('retry-appointment-retry-original-input-retained','原回应保留'),('retry-appointment-retry-one-accepted-choice','重试后只记录一次')]),
]
font = ImageFont.truetype('/System/Library/Fonts/Hiragino Sans GB.ttc',22)
sections = []
for i, (title, pages) in enumerate(groups, 1):
    pages = [(key, label) for key, label in pages if (SHOTS / (key + '.png')).exists()]
    if not pages: continue
    board = Image.new('RGB',(len(pages)*426+24,964),'#e7e6e0')
    draw = ImageDraw.Draw(board)
    cards = []
    for col, (key, label) in enumerate(pages):
        with Image.open(SHOTS / (key+'.png')) as original:
            assert original.size == (1206,2622),(key,original.size)
            board.paste(original.convert('RGB').resize((402,874),Image.Resampling.LANCZOS),(24+426*col,58))
        draw.text((24+426*col,16),label,font=font,fill='#26352e')
        cards.append(f'<figure><a href="screenshots/{key}.png"><img src="screenshots/{key}.png" loading="lazy" alt="{html.escape(label)}"></a><figcaption>{html.escape(label)}</figcaption></figure>')
    board.save(OUT/f'board-{i}.png')
    sections.append(f'<h2>{title}</h2><section>{"".join(cards)}</section>')
records=[{'file':p.name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(SHOTS.glob('*.png'))]
(OUT/'captures.json').write_text(json.dumps(records,ensure_ascii=False,indent=2)+'\n')
(OUT/'index.html').write_text('''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>咕游记 · 赴约实装</title><style>body{margin:0;background:#e7e6e0;color:#26352e;font:16px -apple-system,sans-serif}main{max-width:1340px;margin:auto;padding:24px}h1{font-size:27px}h2{font-size:20px;margin-top:36px}p{line-height:1.8}section{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:24px}figure{margin:0}img{width:100%;display:block}figcaption{padding:12px 0}a{color:#42685d}@media(max-width:760px){section{grid-template-columns:1fr}}</style><main><h1>咕游记 · 赴约实装</h1><p>原有界面已恢复，赴约沿用原剧情阅读样式。这些图片是正式 SwiftUI 界面配合明确隔离的本地演示传输生成的原生截图，没有生图或修图。分数、对白与约定为测试示例，不代表真实用户数据或线上 AI 评价。点击查看未修改的 1206×2622 原图。</p>'''+''.join(sections)+'<p><a href="captures.json">截图 SHA256</a></p></main></html>')
print(OUT/'index.html')
