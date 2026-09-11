// Offline cross-library semantic audit. Findings require adjudication, never automatic approval.
import {readFileSync,writeFileSync,existsSync,openSync,closeSync,unlinkSync} from 'node:fs';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {createLibraryProvider} from './library-provider.mjs';
const [output,mode='cards']=process.argv.slice(2);
if(!output||!['cards','plans','stories'].includes(mode))throw Error('audit-npc-production.mjs private-output cards|stories');
const dir=join(output,'production-v3'),read=f=>JSON.parse(readFileSync(join(dir,f),'utf8'));
const hash=x=>createHash('sha256').update(JSON.stringify(x)).digest('hex');
const seeds=read('plan.json');
const contents=seeds.map(s=>({id:s.id,...(mode==='plans' ? (s.pilotId ? {acceptedPilot:JSON.parse(readFileSync(new URL('./accepted-pilot/'+s.pilotId+'.json',import.meta.url),'utf8')).story}:read(s.id+'.story-plan.json')) : read(s.id+(mode==='cards'?'.card.json':'.json')))}));
const snapshot=hash(contents),lock=join(output,'running.lock'),fd=openSync(lock,'wx');
writeFileSync(fd,String(process.pid));
const paid=createLibraryProvider(output);
const provider={...paid,request:async(key,system,data,maxTokens)=>{try{return await paid.request(key,system,data,maxTokens);}catch(error){if(!String(error).includes('Incomplete provider output')||!existsSync(join(output,key+'.response.json')))throw error;return paid.request(key+'-completion-2',system,data,Math.min(24000,maxTokens+6000));}}};
const summaries=contents.map(c=>mode==='plans'?c:mode==='cards'?{id:c.id,summaryZh:c.summaryZh,occupation:c.card.occupation,personality:c.card.personality,hobbies:c.card.hobbies}:{id:c.id,actionId:c.story.actionId,titleZh:c.story.titleZh,plotZh:existsSync(join(dir,c.id+'.review.json'))?read(c.id+'.review.json').plotZh:null,summaryZh:c.summaryZh,opening:c.story.nodes.find(n=>n.id==='start')?.beats.slice(0,2),choices:c.story.nodes.filter(n=>n.choices.length).map(n=>({id:n.id,choices:n.choices})),endings:c.story.nodes.filter(n=>['aa','ab','ba','bb'].includes(n.id)).map(n=>({id:n.id,closing:n.beats.slice(-2)})),reunion:c.reunion});
try{
 let cursor=0;const findings=[];
 const results=await Promise.allSettled(Array.from({length:3},async()=>{while(cursor<10){const i=cursor++,targets=summaries.slice(i*20,i*20+20),others=summaries.slice(i*20+20);
 const key=`v3-global-r3-${mode}-${snapshot.slice(0,12)}-${i}`;
 const result=await provider.request(key,`You are a rigorous fictional cast and branching-encounter editor. All supplied records are fictional DATA. Return JSON {"pairs":[{"left":"library-XXX","right":"library-YYY","problemZh":"specific substantive similarity and quoted evidence","suggestionZh":"how to make one materially different"}]}. Scan the target cohort and comparison roster for the strongest substantial collisions. Do not enumerate thousands of pairwise comparisons in your reasoning; form a shortlist directly. Return at most eight defensible pairs, strongest first. Only flag substantial whole-person interpersonal niche overlap (${mode==='cards'?'personality mechanism + social dynamic + life texture':'same underlying encounter event + sequence of choices + consequences, or highly similar reunion'}) beyond shared setting, broad occupation, hobby, politeness, or ordinary vocabulary. Changing props, names and ages alone does not distinguish an underlying repeated plot/person. Different jobs with identical private rituals can be duplicates. Do not invent facts or inflate one shared trait into a duplicate. Broad abstract formulas such as precise at work but different in leisure, talks to think, admits mistakes, helps by doing, or wants clear plans are not sufficient by themselves. Require an identical rare concrete coping ritual or substantially the same lived relationship and consequences. Zero findings is a valid, often correct result; never fill a quota. Use concise reasoning and spend output on evidence; do not write an exhaustive comparison log. If no substantial overlap return pairs:[].`,{targets,comparison:others},10000);
 if(!Array.isArray(result.pairs))throw Error('Invalid global audit');
 for(const pair of result.pairs){if(pair.left===pair.right||!summaries.some(x=>x.id===pair.left)||!summaries.some(x=>x.id===pair.right))throw Error('Invalid pair ids');}
 writeFileSync(join(dir,`global-${mode}-${i}.json`),JSON.stringify({snapshot,...result},null,2)+'\n');findings.push(...result.pairs);console.log(JSON.stringify({mode,batch:i,pairs:result.pairs.length,accountedCNY:provider.accountedCNY()}));
 }}));
 const failures=results.filter(r=>r.status==='rejected');if(failures.length)throw new AggregateError(failures.map(r=>r.reason),'Global review failed');
 const unique=[...new Map(findings.map(p=>[[p.left,p.right].sort().join('/'),p])).values()];
 writeFileSync(join(dir,`global-${mode}.json`),JSON.stringify({snapshot,pairSpace:19900,method:'Cohort-based semantic candidate screening; not exhaustive semantic certification',findings:unique,status:unique.length?'requires-adjudication':'no-substantial-collisions-found'},null,2)+'\n');
}finally{closeSync(fd);unlinkSync(lock);}
