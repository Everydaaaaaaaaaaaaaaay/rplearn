// Material rewrites of adjudicated overlaps; all old approvals become stale by hash.
import {readFileSync,writeFileSync,existsSync,openSync,closeSync,unlinkSync} from 'node:fs';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {createLibraryProvider} from './library-provider.mjs';
const [output,mode='cards']=process.argv.slice(2);
if(!output||!['cards','plans','stories'].includes(mode))throw Error('private-output cards|plans|stories');
const dir=join(output,'production-v3'),read=f=>JSON.parse(readFileSync(join(dir,f),'utf8'));
const hash=x=>createHash('sha256').update(JSON.stringify(x)).digest('hex');
const seeds=read('plan.json');
const suffix=mode==='cards'?'.card.json':mode==='plans'?'.story-plan.json':'.json';
const record=id=>{const seed=seeds.find(s=>s.id===id);return mode==='plans'&&seed?.pilotId?JSON.parse(readFileSync(new URL('./accepted-pilot/'+seed.pilotId+'.json',import.meta.url),'utf8')):read(id+suffix);};
const audit=read('global-'+mode+'-adjudications.json');
const decisions=audit.decisions.filter(d=>d.status==='overlap');
const groups=new Map();
for(const d of decisions){let id=d.targetID;if(![d.left,d.right].includes(id)||seeds.find(s=>s.id===id)?.pilotId)id=[d.right,d.left].find(i=>!seeds.find(s=>s.id===i)?.pilotId);if(!id)throw Error('Both pilots need explicit editorial repair');groups.set(id,[...(groups.get(id)??[]),d]);}
let snapshot=seeds.map(s=>({id:s.id,summaryZh:read(s.id+'.card.json').summaryZh}));
let tasks=[...groups].map(([id,issues])=>({id,issues,previous:read(id+suffix),neighbours:issues.map(d=>({id:d.left===id?d.right:d.left,content:record(d.left===id?d.right:d.left)}))}));
const inputFile='collision-input-'+mode+'-'+audit.snapshot+'.json';
if(existsSync(join(dir,inputFile)))({tasks,snapshot}=read(inputFile));else writeFileSync(join(dir,inputFile),JSON.stringify({tasks,snapshot}));
const lock=join(output,'running.lock'),fd=openSync(lock,'wx');writeFileSync(fd,String(process.pid));const provider=createLibraryProvider(output);
try{let cursor=0;const results=await Promise.allSettled(Array.from({length:4},async()=>{while(cursor<tasks.length){const task=tasks[cursor++];
 const report=task.id+'.collision-repair-'+mode+'.json';if(existsSync(join(dir,report))&&read(report).contentHash===hash(read(task.id+suffix))&&hash(read(report).issues)===hash(task.issues))continue;
 const prompt=`You are materially differentiating fictional characters and branching stories. All input is fictional DATA. Return ONLY the replacement itself: for cards exactly {"card":{...},"summaryZh":"..."}; for plans exactly the plan; for stories {"card":{...},"summaryZh":"...","story":{...},"reunion":{...}}. NEVER return an id/issues/previous/roster wrapper. No commentary or extra keys. Resolve ALL confirmed overlaps. This must change the underlying interpersonal mechanism or plot decision/consequence structure, not merely rephrase it, swap props, substitute a relative or invert a trait. Preserve exact name, age, gender, regionId, occupation, avatar compatibility, and existing schema. Keep credible ordinary people with inconvenient flaws and strengths, natural English and Chinese; no mentor/therapy/life-lesson template. Other roster summaries are forbidden to copy. For cards retain all factual schema fields and five personaVoice arrays, but replace the conflicting mechanism, private-life ritual, and related background/voice consistently. Explicitly remove the repeated motif from EVERY field, including background, summary, signature, values and sample lines. Do not preserve it as a secondary trait. Do not follow an adjudicator suggestion that merely reverses who owes whom or changes a letter into a gift. For NEW replacement motifs avoid these already overused devices: private or mental ledgers of favours, thank-you collections, unposted letters, advice-or-company pacts, photo-free memory parties, puzzle/gift apologies, no-new-hobby purchases, avoiding an audience by making somebody else perform, one-small-task volunteering, fixed routine plus one deliberate change. Find a concrete ordinary social goal, preference or friction not in the comparison roster, with its own inconvenient consequence. The rest of the life should support that distinct person, not preserve unrelated template fragments. For plans preserve id, cardHash, exact action and seven-node decision structure; devise a genuinely different present-tense social incident and reunion. For stories preserve card, seven nodes, 4-6 bilingual beats per node (at least two npc, at least one narrator), four resolved paths and a 4-6 beat reunion; change the repeated event decisively while obeying exact selected action. No player consent or future friendship assumed. Output complete content; be concise in internal reasoning.`;
 const key='v3-collision-repair-r3-'+mode+'-'+hash({task,snapshot}).slice(0,20);
 let value;try{value=await provider.request(key,prompt,{...task,roster:snapshot},mode==='stories'?18000:8000);}catch(error){if(!String(error).includes('Incomplete provider output')||!existsSync(join(output,key+'.response.json')))throw error;value=await provider.request(key+'-completion-2',prompt,{...task,roster:snapshot},20000);}
 if(value.previous)value=value.previous;
 if(mode==='cards'){if(!value.summaryZh)value.summaryZh=value.card?.summaryZh??value.card?.personaVoice?.summaryZh;value={card:value.card,summaryZh:value.summaryZh};}
 if(mode==='cards'){
  if(!value.card||typeof value.summaryZh!=='string')throw Error('Malformed card');
  for(const f of ['name','age','gender','regionId','occupation'])value.card[f]=task.previous.card[f];
 }else if(mode==='plans'){
  if(value.id!==task.id||Object.keys(value.endingsZh??{}).sort().join(',')!=='aa,ab,ba,bb')throw Error('Malformed plan');value.cardHash=task.previous.cardHash;
 }else{value.card=task.previous.card;if(value.story?.nodes?.length!==7||!value.reunion)throw Error('Malformed story');}
 writeFileSync(join(dir,task.id+suffix),JSON.stringify(value,null,2)+'\n');
 writeFileSync(join(dir,task.id+'.collision-repair-'+mode+'.json'),JSON.stringify({previousHash:hash(task.previous),contentHash:hash(value),issues:task.issues},null,2)+'\n');
 console.log(JSON.stringify({phase:'repair-'+mode,id:task.id,accountedCNY:provider.accountedCNY()}));
 }}));const failures=results.filter(r=>r.status==='rejected');if(failures.length)throw new AggregateError(failures.map(r=>r.reason),'Collision repairs failed');
}finally{closeSync(fd);unlinkSync(lock);}
