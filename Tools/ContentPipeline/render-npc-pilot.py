"""Render a self-contained, offline review gallery from the ten content sources."""
import base64
import json
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[2]
source = root / "Content/NPCPilot/2026-09-11"
destination = Path(sys.argv[1])
people = []
for seed in json.loads((source / "briefs.json").read_text()):
    entry = json.loads((source / (seed["id"] + ".json")).read_text())
    image = base64.b64encode((root / seed["avatarPath"]).read_bytes()).decode()
    people.append({"seed": seed, "content": entry, "image": "data:image/png;base64," + image})
data = json.dumps(people, ensure_ascii=False).replace("<", "\\u003c")
page = """<!doctype html><html lang="zh-CN"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>十个人，十次相遇</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#f5f2eb;color:#262a2a;font-family:system-ui,-apple-system,sans-serif;line-height:1.7}
main{max-width:1120px;margin:auto;padding:36px 24px}h1{font-size:38px;line-height:1.3;letter-spacing:-1px}h2{line-height:1.4}
.muted{color:#626763}button{font:inherit;cursor:pointer;color:inherit;border:1px solid #c8cdc5;background:#fffdf7;border-radius:10px;padding:10px 16px;min-height:44px}button:hover{background:#e7eee4}button:focus-visible{outline:3px solid #497158;outline-offset:3px}
#cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(185px,1fr));gap:12px;margin:24px 0}.person{text-align:left;padding:16px}.person[aria-pressed=true]{border:2px solid #345e48;background:#e8eee5}
.person img{width:76px;height:76px;object-fit:cover;border-radius:50%;display:block;margin-bottom:12px}.person strong{display:block}.person small{display:block;color:#626763}
#reader{background:#fffdf8;border:1px solid #d9ddd3;border-radius:18px;padding:28px;max-width:850px;margin:30px auto}.heading{display:flex;gap:20px;align-items:center}.heading img{width:84px;height:84px;border-radius:50%}
.beat{margin:22px 0;padding-left:16px;border-left:2px solid #dce4d9}.beat.npc{border-color:#6a9477}.en{font-size:18px;line-height:1.8}.zh{color:#626763;font-size:15px;margin-top:6px}
.speaker{font-size:12px;font-weight:600;color:#54735d}.choices{display:grid;gap:12px;margin-top:26px}.choices button{text-align:left;background:#edf2e9}.choices .zh{display:block}
.toolbar{display:flex;gap:10px;flex-wrap:wrap;margin:24px 0}details{margin:18px 0}summary{cursor:pointer;padding:8px 0}#path{font-size:13px;color:#54735d}.end{padding:20px;border-radius:12px;background:#edf2e9}.end button{margin:8px 8px 0 0}
@media(max-width:600px){main{padding:20px 14px}#reader{padding:20px}h1{font-size:30px}.person img{width:60px;height:60px}}
</style><main><p class="muted">LINGOTRIP · 角色库内容试读</p><h1>十个人，十次相遇。</h1>
<p>每人一篇故事、两次选择、四个结尾。这里可完整试读所有分支；样本尚未导入游戏。</p>
<div id="cards"></div><section id="reader" aria-live="polite"></section></main>
<script>const people=DATA;let selected=0,path=['start'];
const el=(tag,text,cls)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e};
function button(text,fn){const b=el('button',text);b.onclick=fn;return b}
function renderCards(){const cards=document.getElementById('cards');cards.replaceChildren();people.forEach((p,i)=>{const b=button('',()=>{selected=i;path=['start'];renderCards();render();document.getElementById('reader').scrollIntoView({block:'start'})});b.className='person';b.setAttribute('aria-pressed',String(i===selected));const img=el('img');img.src=p.image;img.alt=p.content.card.name+'的头像';b.append(img,el('strong',p.content.card.name),el('small',p.seed.age+' 岁 · '+p.content.story.titleZh));cards.append(b)})}
function render(){const p=people[selected],c=p.content.card,story=p.content.story,node=story.nodes.find(n=>n.id===path.at(-1));const r=document.getElementById('reader');r.replaceChildren();
 const head=el('div',undefined,'heading'),img=el('img');img.src=p.image;img.alt=c.name;const names=el('div');names.append(el('h2',c.name),el('div',c.occupation,'muted'));head.append(img,names);r.append(head,el('p',p.content.summaryZh));
 const card=el('details');card.append(el('summary','看看完整人物设定'));for(const [label,value] of [['性格',c.personality],['经历',c.background],['爱好',c.hobbies.join(' · ')],['说话方式',c.speechStyle],['看重什么',c.personaVoice.values.join(' · ')],['缺点',c.personaVoice.flaws.join(' · ')],['边界',c.personaVoice.boundaries.join(' · ')]]){card.append(el('strong',label),el('p',value))}r.append(card);
 const toolbar=el('div',undefined,'toolbar');toolbar.append(button('从头试读',()=>{path=['start'];render()}));if(path.length>1)toolbar.append(button('返回上个选择',()=>{path.pop();render()}));r.append(toolbar,el('h2',story.titleZh),el('div','第 '+path.length+' / 3 幕 · 路径 '+path.join(' → '),'muted'));
 for(const beat of node.beats){const b=el('div',undefined,'beat '+beat.speaker);b.append(el('div',beat.speaker==='npc'?c.name:'此刻','speaker'),el('div',beat.english,'en'),el('div',beat.chinese,'zh'));r.append(b)}
 if(node.choices.length){const box=el('div',undefined,'choices');box.append(el('strong','你想怎么做？'));node.choices.forEach(choice=>{const b=button('',()=>{path.push(choice.next);render();r.scrollIntoView({block:'start'})});b.append(el('span',choice.english),el('span',choice.chinese,'zh'));box.append(b)});r.append(box)}else{const box=el('div',undefined,'end');box.append(el('strong','相遇告一段落，是否继续联系由你决定。'));for(const label of ['加为好友','留作一次相遇'])box.append(button(label+'（试读）',()=>{box.append(el('p','已选择“'+label+'”。这只是内容预览，不修改游戏里的好友。'))}));r.append(box)}
}renderCards();render();</script></html>""".replace("DATA", data)
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_text(page)
print(destination)
