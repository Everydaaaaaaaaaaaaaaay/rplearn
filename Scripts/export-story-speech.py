#!/usr/bin/env python3
"""Export the explicitly enabled XCTest audition to stable human-readable names."""
import argparse
import json
import html
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('result', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='attachments-', dir=args.output) as temporary:
    attachments = Path(temporary)
    subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(args.result),
                    '--output-path', str(attachments)], check=True)
    manifest = json.loads((attachments / 'manifest.json').read_text())
    exported = set()
    for test in manifest:
        for item in test['attachments']:
            name = re.sub(r'_\d+_[A-Fa-f0-9-]{36}(?=\.)', '', item['suggestedHumanReadableName'])
            if not re.fullmatch(r'(?:scene-|original-|rhythm-|expressive-|speech-audition-)[\w-]+\.(?:wav|json)', name):
                continue
            if name in exported:
                raise RuntimeError(f'Duplicate audition attachment {name}; select a single run/device.')
            shutil.copyfile(attachments / item['exportedFileName'], args.output / name)
            exported.add(name)
required = {'scene-original.wav', 'scene-rhythm.wav', 'scene-expressive.wav', 'speech-audition-metrics.json'}
if not required.issubset(exported):
    raise RuntimeError(f'Missing audition outputs: {required - exported}')
print(f'Exported {len(exported)} files to {args.output.resolve()}')

metrics = json.loads((args.output / 'speech-audition-metrics.json').read_text())
labels = {'original': 'A · 原版', 'rhythm': 'B · 语速与停顿', 'expressive': 'C · 节奏 + 情境呼吸'}
page = ['<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>伦敦语音样板</title>',
        '<style>body{font:17px/1.7 system-ui;margin:40px auto;padding:0 22px;max-width:950px;background:#f7f4ee;color:#292725}h1{font-size:30px}section{padding:18px 0;border-bottom:1px solid #d4d0c9}audio{display:block;width:100%;max-width:480px}small{color:#625f58}table{width:100%;border-collapse:collapse}td,th{text-align:left;padding:10px;border-bottom:1px solid #ddd}a{color:#375746}</style>',
        '<h1>给 Oliver 一点喘息的空间</h1><p>同一段台词、同一组音色。先听 A 与 B 比较节奏，再听 B 与 C 比较呼吸标签。C 只有第九句新增呼吸，其余九句直接复用 B 的音频。</p>',
        '<p><small>本地模型真实输出，未逐版调整响度。纯语音片段省略玩家的静音问句与雨声，不含现场合成等待。技术检查不替代听感判断。</small></p>']
for variant, label in labels.items():
    rows = [item for item in metrics if item['variant'] == variant]
    seconds = sum(item['seconds'] + .6 for item in rows)
    page.append(f'<section><h2>{label} · {seconds:.1f} 秒</h2><audio controls preload="none" src="scene-{variant}.wav"></audio></section>')
page.append('<h2>逐句比较</h2><p>重点：第一句的完整句间停顿；第八句后的留白；第九句 Oliver 开口前的呼吸。</p>')
for item in [item for item in metrics if item['variant'] == 'original']:
    node = item['node']
    page.append(f'<section><p>{html.escape(item["text"])}</p><small>{html.escape(node)} · {html.escape(item["voice"])}</small>')
    for variant, label in labels.items():
        page.append(f'<details><summary>{label}</summary><audio controls preload="none" src="{variant}-{node}.wav"></audio></details>')
    page.append('</section>')
page.append('<p>试听时分别判断：自然度、场景贴合、声音是否仍像同一个人，以及呼吸是否突兀、停顿是否拖沓。</p><script>document.addEventListener("play",e=>{if(e.target.tagName==="AUDIO")document.querySelectorAll("audio").forEach(a=>{if(a!==e.target)a.pause()})},true)</script></html>')
(args.output / 'index.html').write_text('\n'.join(page), encoding='utf-8')
