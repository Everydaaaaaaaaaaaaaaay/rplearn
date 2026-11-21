#!/usr/bin/env python3
"""Compile reviewed bilingual manuscripts plus explicit editorial directions.

Offline only. Retains original editions and stable reward/catalog identities.
Use --check to verify generated runtime files without writing them.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import unicodedata

ROOT = Path(__file__).resolve().parents[2]
DIRECTIONS = ROOT / 'Content/AdultLife/2026-10-31/directions.json'


def read_scenes(text):
    scenes = {}
    current = None
    for line in text.splitlines():
        match = re.match(r'### ([A-Z]{2}\d{2}) · (.+)', line)
        if match:
            current = match[1]
            if current in scenes:
                raise ValueError('duplicate scene ' + current)
            scenes[current] = {'title': match[2], 'lines': [], 'choices': [], 'end': False}
        if not current:
            continue
        scene = scenes[current]
        if line == '出口：结束。':
            scene['end'] = True
        if not line.startswith('|'):
            continue
        cells = [cell.strip() for cell in line.strip('|').split('|')]
        if len(cells) == 3 and cells[0] not in ('说话人', '---'):
            scene['lines'].append(cells)
        elif len(cells) == 4 and cells[0] in ('A', 'B'):
            scene['choices'].append(cells)
    return scenes


def directed_lines(scene, direction):
    lines = [list(row) for row in scene['lines']]
    for replacement in direction.get('replace', []):
        matches = [i for i, row in enumerate(lines) if row[1] == replacement['english']]
        if len(matches) != 1:
            raise ValueError('ambiguous replacement: ' + replacement['english'])
        i = matches[0]
        lines[i][1:] = replacement['with']
    for insertion in direction.get('insertAfter', []):
        matches = [i for i, row in enumerate(lines) if row[1] == insertion['english']]
        if len(matches) != 1:
            raise ValueError('ambiguous insertion: ' + insertion['english'])
        lines[matches[0] + 1:matches[0] + 1] = insertion['lines']
    if direction.get('appendBeforeLast'):
        lines[-1:-1] = direction['appendBeforeLast']
    return direction.get('before', []) + lines


def compile_episode(item):
    source = (ROOT / item['source']).read_bytes()
    if hashlib.sha256(source).hexdigest() != item['sourceSHA256']:
        raise ValueError('Manuscript changed; review and update its pinned hash: ' + item['source'])
    text = source.decode()
    scenes = read_scenes(text)
    start = re.search(r'入口：([A-Z]{2}\d{2})', text)[1]
    if set(scenes) != set(item['scenes']):
        raise ValueError('scene directions must cover exactly the manuscript')
    nodes = []
    for scene_id, scene in scenes.items():
        direction = item['scenes'][scene_id]
        lines = directed_lines(scene, direction)
        for i, (speaker, english, chinese) in enumerate(lines):
            shot = direction['shot']
            for cut in direction.get('cuts', []):
                if i >= cut['from']:
                    shot = cut['shot']
            node = dict(id=f'{scene_id}_{i + 1:02}', act=direction['act'],
                        location=item['acts'][direction['act']], shot=shot,
                        speaker=speaker, text=english, translation=chinese)
            node['speech'] = dict(intention='按本场处境接话，保留停顿和人物自己的想法',
                                  speed=direction['speed'], before=0,
                                  after=0.7 if i == len(lines) - 1 else direction['after'])
            if i < len(lines) - 1:
                node['next'] = f'{scene_id}_{i + 2:02}'
            elif scene['end']:
                node['ending'] = True
                node['experienceID'] = scene_id
            else:
                node['next'] = scene_id + '_choice'
            nodes.append(node)
        if scene['choices']:
            outcomes = direction['outcomes']
            nodes.append(dict(id=scene_id + '_choice', act=direction['act'],
                              location=item['acts'][direction['act']], shot=direction['shot'],
                              speaker='你的选择', text=direction['question'][0],
                              translation=direction['question'][1],
                              choices=[dict(id=c[0].lower(), text=c[1], translation=c[2],
                                            next=c[3] + '_01', flags={scene_id: index == 0},
                                            review=dict(context=scene['title'], outcome=outcomes[index]))
                                       for index, c in enumerate(scene['choices'])]))
    episode = dict(id=item['id'], version=2, title=text.splitlines()[0][2:],
                   start=start + '_01', maxDialogueCharacters=65,
                   acts=item['acts'], shots=item['shots'], nodes=nodes)
    # Include only shots actually used by this edition: no unused old branch CGs.
    used = {node['shot'] for node in nodes}
    episode['shots'] = {key: value for key, value in item['shots'].items() if key in used}
    for node in nodes:
        for english in [node['text']] + [c['text'] for c in node.get('choices', [])]:
            if len(unicodedata.normalize('NFKD', english)) > 65:
                raise ValueError(node['id'] + ': exceeds the speech panel budget')
    return episode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    manifest = json.loads(DIRECTIONS.read_text())
    for item in manifest['episodes']:
        episode = compile_episode(item)
        output = ROOT / 'App/Resources/Stories' / (item['id'] + '.json')
        contents = json.dumps(episode, ensure_ascii=False, indent=2) + '\n'
        if args.check:
            if not output.exists() or output.read_text() != contents:
                raise ValueError('Runtime edition is stale: ' + str(output))
        else:
            output.write_text(contents)
        print(item['id'], len(episode['nodes']), 'nodes')


if __name__ == '__main__':
    main()
