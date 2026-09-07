#!/usr/bin/env python3
"""Export an offline, branch-aware listening page. Auditioning never grants rewards."""
import argparse, base64, html, json
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
CITY={'london':'伦敦','melbourne':'墨尔本','newyork':'纽约','singapore':'新加坡','capetown':'开普敦','auckland':'奥克兰','dublin':'都柏林','edinburgh':'爱丁堡','kingston':'金斯敦','manchester':'曼彻斯特','nairobi':'内罗毕','neworleans':'新奥尔良','sydney':'悉尼','toronto':'多伦多','vancouver':'温哥华'}

def build(destination,output):
    manifest=json.loads((destination/'story-voice-library.json').read_text());stories=[]
    source=ROOT/'App/Resources/Stories'
    catalog=json.loads((source/'departures_catalog.json').read_text())
    for chapter in catalog['chapters']:
        path=source/(chapter['id']+'.json')
        story=json.loads(path.read_text())
        if 'nodes' not in story:continue
        title=('主线' if chapter['kind']=='mainline' else '城市')+' · '+CITY[chapter['city']]+' · '+chapter['title']
        stories.append(dict(id=story['id'],title=title,start=story['start'],nodes={n['id']:n for n in story['nodes']}))
    audio={c['story']+'/'+c['node']:'data:audio/mp4;base64,'+base64.b64encode((destination/c['file']).read_bytes()).decode() for c in manifest['clips']}
    payload=json.dumps(dict(stories=stories,audio=audio),ensure_ascii=False).replace('</','<\\/')
    page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>剧情配音 · 全篇试听</title>
<style>body{margin:0;background:#12211f;color:#f3eee1;font:17px/1.8 system-ui}main{max-width:760px;margin:auto;padding:36px 24px}h1{font-size:28px}select,button{font:inherit;border:1px solid #7b8c80;border-radius:12px;background:#223830;color:inherit;padding:9px 14px}select{max-width:100%}button{cursor:pointer}button:disabled{opacity:.4;cursor:default}article{background:#f4f0e5;color:#20332d;border-radius:22px;padding:28px;margin:28px 0}#speaker{color:#596b60}#text{font-size:24px;line-height:1.6}#translation{color:#607065}audio{width:100%;margin:16px 0}.controls{display:flex;gap:12px;flex-wrap:wrap}#choices{display:grid;gap:10px}small{color:#b0bdb2}#status{min-height:2em}</style>
<main><h1>剧情配音 · 全篇试听</h1><p>选择一篇故事，沿着自己的选择听下去。</p><select id="story" aria-label="选择剧情"></select><article><div id="speaker"></div><p id="text"></p><p id="translation"></p><div id="choices"></div></article><audio id="audio" controls preload="auto"></audio><p id="status" aria-live="polite"></p><div class="controls"><button id="back">上一页</button><button id="next">下一页</button><button id="restart">从头开始</button><label><input id="auto" type="checkbox">自动继续</label></div><p><small>玩家台词、选项及中文旁白保留文字，点击下一页继续。所有选择仅用于试听。</small></p></main>
<script>
const DATA=__DATA__;const $=id=>document.getElementById(id);let story,node,flags={},history=[],epoch=0;
function enter(id,push=true){epoch++;$('audio').pause();if(push&&node)history.push({node:node.id,flags:{...flags}});node=story.nodes[id];let visited=new Set();while(node&&['branch','reward'].includes(node.type)){if(visited.has(node.id))throw Error('剧情路径循环');visited.add(node.id);node=story.nodes[node.type==='branch'?(flags[node.flag]?node.ifTrue:node.ifFalse):node.next];}render();}
function render(){const a=$('audio');a.removeAttribute('src');$('choices').replaceChildren();$('back').disabled=!history.length;const choices=node?.choices||node?.options||[];const end=!node||node.ending||node.type==='end';$('speaker').textContent=node?.speaker||'本章结束';$('text').textContent=node?.text||'这一站，到这里。';$('translation').textContent=node?.translation||'';$('next').disabled=end||choices.length>0;
 for(const c of choices){let b=document.createElement('button');b.textContent=c.text+(c.translation?' · '+c.translation:'');b.onclick=()=>{const prior={node:node.id,flags:{...flags}};Object.assign(flags,c.flags||c.setFlags||{});history.push(prior);enter(c.next,false)};$('choices').append(b)}
 const src=DATA.audio[story.id+'/'+node?.id];a.hidden=!src;if(src){a.src=src;$('status').textContent='可以播放本页。';if($('auto').checked)play()}else{$('status').textContent=choices.length?'请选择接下来的方向。':end?'本章结束。':'这一页保留文字，阅读后继续。';} }
function play(){let token=epoch;$('audio').play().then(()=>{if(epoch===token)$('status').textContent='正在播放…'}).catch(()=>{if(epoch===token)$('status').textContent='点击音频播放键开始试听。'})}
function next(){if($('next').disabled)return;enter(node.branch?(flags[node.branch.flag]?node.branch.yes:node.branch.no):node.next)}
function start(){epoch++;story=DATA.stories[Number($('story').value)];node=null;flags={};history=[];enter(story.start,false)}
for(const [i,s] of DATA.stories.entries()){let o=document.createElement('option');o.value=i;o.textContent=s.title;$('story').append(o)}
$('story').onchange=start;$('next').onclick=next;$('restart').onclick=start;$('back').onclick=()=>{let previous=history.pop();if(previous){flags=previous.flags;enter(previous.node,false)}};$('auto').onchange=()=>{if($('auto').checked&&$('audio').getAttribute('src'))play()};$('audio').onended=()=>{if($('auto').checked)next();else $('status').textContent='本页播放完毕。'};$('audio').onerror=()=>{$('status').textContent='音频读取失败，请重新选择本页。'};start();
</script></html>'''.replace('__DATA__',payload)
    output.parent.mkdir(parents=True,exist_ok=True);output.write_text(page);print(output)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('destination',type=Path);p.add_argument('output',type=Path);a=p.parse_args();build(a.destination,a.output)
