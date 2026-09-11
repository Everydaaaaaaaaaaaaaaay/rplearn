// Deterministic screening, not a semantic uniqueness certificate.
import {readFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
const [output,mode='cards']=process.argv.slice(2);
const dir=join(output,'production-v3'),read=f=>JSON.parse(readFileSync(join(dir,f),'utf8'));
const seeds=read('plan.json');
const records=seeds.map(s=>({id:s.id,content:read(s.id+(mode==='cards'?'.card.json':'.json'))}));
const words=text=>(text.toLowerCase().match(/[a-z]+(?:'[a-z]+)?/g)??[]);
function passage(r){return mode==='cards'?[r.card.personality,r.card.background,r.card.speechStyle,...Object.values(r.card.personaVoice).flat()].join(' '):[...r.story.nodes.flatMap(n=>n.beats.map(b=>b.english)),...r.reunion.beats.map(b=>b.english)].join(' ');}
const texts=records.map(r=>words(passage(r.content))),sets=texts.map(t=>new Set(t.filter(w=>w.length>3)));
const pairs=[];
for(let i=0;i<records.length;i++)for(let j=i+1;j<records.length;j++){
 const shared=[...sets[i]].filter(w=>sets[j].has(w)).length;
 pairs.push({left:records[i].id,right:records[j].id,score:shared/(sets[i].size+sets[j].size-shared)});
}
const phrases=new Map();texts.forEach((t,i)=>{const own=new Set();for(let p=0;p+8<=t.length;p++)own.add(t.slice(p,p+8).join(' '));for(const phrase of own){const ids=phrases.get(phrase)??[];ids.push(records[i].id);phrases.set(phrase,ids);}});
const sharedPassages=[...phrases].filter(([,ids])=>ids.length>1).map(([phrase,ids])=>({phrase,ids}));
const report={snapshot:createHash('sha256').update(JSON.stringify(records)).digest('hex'),mode,comparedPairs:pairs.length,method:'English token Jaccard and exact eight-word shingles; candidates require semantic adjudication',nearestPairs:pairs.sort((a,b)=>b.score-a.score).slice(0,100),sharedPassages};
writeFileSync(join(dir,'lexical-'+mode+'.json'),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({mode,pairs:pairs.length,sharedPassages:sharedPassages.length,top:pairs.slice(0,5)}));
