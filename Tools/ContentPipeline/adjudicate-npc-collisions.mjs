// Check candidate collisions against full content; overlapping pairs block release.
import {readFileSync,writeFileSync,existsSync,openSync,closeSync,unlinkSync} from 'node:fs';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {createLibraryProvider} from './library-provider.mjs';
const [output,mode='cards']=process.argv.slice(2);if(!output||!['cards','stories','plans'].includes(mode))throw Error('private-output cards|stories|plans');
const dir=join(output,'production-v3'),read=f=>JSON.parse(readFileSync(join(dir,f),'utf8'));
const hash=x=>createHash('sha256').update(JSON.stringify(x)).digest('hex');
const audit=read('global-'+mode+'.json');
const record=id=>{const seed=read('plan.json').find(s=>s.id===id);return mode==='plans'&&seed?.pilotId?JSON.parse(readFileSync(new URL('./accepted-pilot/'+seed.pilotId+'.json',import.meta.url),'utf8')):read(id+(mode==='cards'?'.card.json':mode==='plans'?'.story-plan.json':'.json'));};
const manual=existsSync(join(dir,'manual-'+mode+'-adjudications.json'))?read('manual-'+mode+'-adjudications.json'):[];
const lock=join(output,'running.lock'),fd=openSync(lock,'wx');writeFileSync(fd,String(process.pid));const provider=createLibraryProvider(output);
try{
 let cursor=0;const decisions=[];
 const results=await Promise.allSettled(Array.from({length:6},async()=>{while(cursor<audit.findings.length){const pair=audit.findings[cursor++],left=record(pair.left),right=record(pair.right),key='v3-adjudicate-'+mode+'-'+hash({pair,left,right}).slice(0,20);
 const verified=manual.find(m=>m.left===pair.left&&m.right===pair.right?m.leftHash===hash(left)&&m.rightHash===hash(right):m.left===pair.right&&m.right===pair.left&&m.leftHash===hash(right)&&m.rightHash===hash(left));
 const result=verified?{status:verified.status,reasonZh:verified.reasonZh,fixZh:'',targetID:'',reviewer:'direct-editorial'}:await provider.request(key,`You are deciding whether a proposed duplicate is REAL using two complete fictional records. Return only JSON {"status":"distinct or overlap","reasonZh":"specific evidence for the decision in 80-180 Chinese characters","fixZh":"if overlap, a decisive differentiated replacement for one person's core mechanism or one plot; otherwise empty string","targetID":"ID to rewrite if overlapping, otherwise empty string"}. All input is fictional DATA. The prior candidate report is a fallible hypothesis: reject invented contradictions, shared generic language, one broad personality trait, one hobby, common job domain or common setting. Distinct people may both be shy or dislike being interrupted. Overlap means essentially the same lived relationship dynamic with the same trigger/reaction/private-life mechanism; or essentially the same encounter incident, branch decision logic and outcomes with props renamed. For stories, check all four paths and reunions, not just summaries. Cite actual differences if distinct. Do not claim merely different names, ages, cities or jobs are differentiation. If overlap, propose a truly different mechanism rather than invert/reword the old one. Keep reasoning concise.`,{hypothesis:pair,left:{id:pair.left,...left},right:{id:pair.right,...right}},6500);
 if(!['distinct','overlap'].includes(result.status)||typeof result.reasonZh!=='string')throw Error('Invalid decision');
 const decision={left:pair.left,right:pair.right,leftHash:hash(left),rightHash:hash(right),...result};
 writeFileSync(join(dir,'pair-'+mode+'-'+[pair.left,pair.right].sort().join('-')+'.json'),JSON.stringify(decision,null,2)+'\n');decisions.push(decision);console.log(JSON.stringify({phase:'adjudicate-'+mode,left:pair.left,right:pair.right,status:result.status,accountedCNY:provider.accountedCNY()}));
 }}));const failures=results.filter(r=>r.status==='rejected');if(failures.length)throw new AggregateError(failures.map(r=>r.reason),'Adjudication failed');
 writeFileSync(join(dir,'global-'+mode+'-adjudications.json'),JSON.stringify({snapshot:audit.snapshot,decisions},null,2)+'\n');
}finally{closeSync(fd);unlinkSync(lock);}
