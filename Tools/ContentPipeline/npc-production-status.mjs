// Read-only completion report; never promotes drafts or refreshes an approval hash.
import {readFileSync,existsSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {validate} from './npc-content.mjs';
const [output,destination]=process.argv.slice(2);
if(!output)throw Error('private-output [report.json]');
const dir=join(output,'production-v3'),read=n=>existsSync(join(dir,n))?JSON.parse(readFileSync(join(dir,n))):null;
const hash=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
const seeds=read('plan.json');if(!Array.isArray(seeds)||seeds.length!==200)throw Error('Expected 200 seeds');
const missing=[],unreviewedCards=[],unreviewedStories=[],invalid=[],coverage=new Map();
let drafts=0,approvedCards=0,approvedStories=0,paths=0,reunions=0;
for(const s of seeds){
 const slot=s.regionId+'/'+s.actionId;coverage.set(slot,(coverage.get(slot)??0)+1);
 const card=read(s.id+'.card.json'),cr=read(s.id+'.card-review.json');
 if(card&&cr?.status==='reviewed'&&cr.contentHash===hash(card)&&!cr.issues?.length)approvedCards++;else unreviewedCards.push(s.id);
 const story=read(s.id+'.json'),sr=read(s.id+'.review.json');
 if(!story){missing.push(s.id);continue;}drafts++;
 const errors=validate(story,s),r=story.reunion;
 if(!r?.titleZh||!Array.isArray(r.beats)||r.beats.length<4||r.beats.length>6||r.beats[0]?.speaker!=='narrator'||r.beats.filter(b=>b.speaker==='npc').length<2)errors.push('Incomplete reunion');
 if(hash(story.card)!==hash(card?.card))errors.push('Story/card mismatch');
 if(errors.length)invalid.push({id:s.id,errors});else{paths+=4;reunions++;}
 if(sr?.status==='reviewed'&&sr.contentHash===hash(story)&&!sr.issues?.length&&!errors.length)approvedStories++;
 else unreviewedStories.push({id:s.id,status:sr?.status??'draft',issues:sr?.issues??[]});
}
const global={};
for(const mode of ['cards','stories']){
 const audit=read('global-'+mode+'.json');
 const contents=seeds.map(s=>({id:s.id,...read(s.id+(mode==='cards'?'.card.json':'.json'))}));
 const current=audit?.snapshot===hash(contents),adjudications=read('global-'+mode+'-adjudications.json');
 const unresolved=(audit?.findings??[]).filter(p=>!adjudications?.decisions?.some(d=>adjudications.snapshot===audit.snapshot&&d.status==='distinct'&&d.reasonZh?.length>=20&&[d.left,d.right].sort().join('/')===[p.left,p.right].sort().join('/')));
 global[mode]={current,findings:audit?.findings?.length??null,unresolved:unresolved.length};
}
const report={expected:200,drafts,approvedCards,approvedStories,structurallyValidPaths:paths,structurallyValidReunions:reunions,missing,unreviewedCards,unreviewedStories,invalid,coverage:{slots:coverage.size,min:Math.min(...coverage.values()),max:Math.max(...coverage.values()),conditionalUniformFloor:0.4/Math.max(...coverage.values())},global};
report.releaseReady=drafts===200&&approvedCards===200&&approvedStories===200&&invalid.length===0&&coverage.size===135&&Object.values(global).every(g=>g.current&&g.unresolved===0);
if(destination)writeFileSync(destination,JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({...report,unreviewedStories:unreviewedStories.map(r=>({id:r.id,status:r.status,issues:r.issues.length}))}));
