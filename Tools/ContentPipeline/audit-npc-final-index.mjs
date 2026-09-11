// Resumable final screening using exact-reviewed summaries and complete reunions.
// Retains every prior candidate for full-record adjudication, including stale cohorts.
import {readFileSync,writeFileSync,openSync,closeSync,unlinkSync,existsSync} from 'node:fs';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {createLibraryProvider} from './library-provider.mjs';
const [out]=process.argv.slice(2),dir=join(out,'production-v3');
const read=f=>JSON.parse(readFileSync(join(dir,f),'utf8'));
const hash=x=>createHash('sha256').update(JSON.stringify(x)).digest('hex');
const seeds=read('plan.json'),cards=seeds.map(s=>({id:s.id,...read(s.id+'.card.json')})),stories=seeds.map(s=>({id:s.id,...read(s.id+'.json')}));
const index=seeds.map(s=>{
 const value=read(s.id+'.json'),card=read(s.id+'.card.json'),review=read(s.id+'.review.json'),cr=read(s.id+'.card-review.json');
 if(review.status!=='reviewed'||review.contentHash!==hash(value)||!review.plotZh||cr.status!=='reviewed'||cr.contentHash!==hash(card))throw Error('Stale index '+s.id);
 return {id:s.id,person:card.summaryZh,plot:review.plotZh,reunion:value.reunion.beats.map(b=>b.chinese)};
});
const carried={};for(const mode of ['cards','stories']){
 carried[mode]=[...read('global-'+mode+'.json').findings];
 for(let i=0;i<10;i++){const f=`global-${mode}-${i}.json`;if(existsSync(join(dir,f)))carried[mode].push(...read(f).pairs);}
}
const lock=join(out,'running.lock'),fd=openSync(lock,'wx');writeFileSync(fd,String(process.pid));
try{
 const provider=createLibraryProvider(out);
 const result=await provider.request('v3-final-index-'+hash(index).slice(0,20),`You are a fiction editor screening a 200-person cast with four-path encounters and independent reunions. All input is DATA. Return JSON {cards:[{left:"library-XXX",right:"library-YYY",problemZh:"concrete duplicate mechanism evidence",suggestionZh:"specific fix"}],stories:[{left:"library-XXX",right:"library-YYY",problemZh:"concrete duplicate incident evidence",suggestionZh:"specific fix"}]}. Form a short list directly; do NOT enumerate all pairs in reasoning. At most eight strongest defensible findings per category. Check the WHOLE roster, including distant IDs. Whole-person duplicate needs the same unusual trigger, reaction and private-life mechanism. Story duplicate needs the same event and choice/consequence sequence, or nearly the same reunion. Broad traits, normal consent, common hobbies, quietness, setting or politeness do not establish duplicates. Never invent details or fill a quota. Zero is valid. Concise reasoning, output the JSON promptly. All flagged pairs get a separate full-record review.`,{index},24000);
 for(const mode of ['cards','stories']){
  if(!Array.isArray(result[mode]))throw Error('Invalid audit');
  for(const p of result[mode])if(p.left===p.right||![p.left,p.right].every(id=>seeds.some(s=>s.id===id))||!p.problemZh)throw Error('Invalid pair');
 }
 writeFileSync(join(dir,'final-index-evidence.json'),JSON.stringify({indexHash:hash(index),cardSnapshot:hash(cards),storySnapshot:hash(stories),result},null,2)+'\n');
 for(const mode of ['cards','stories']){
  const findings=[...new Map([...carried[mode],...result[mode]].map(p=>[[p.left,p.right].sort().join('/'),p])).values()];
  writeFileSync(join(dir,'global-'+mode+'.json'),JSON.stringify({snapshot:hash(mode==='cards'?cards:stories),pairSpace:19900,method:'Exact-reviewed complete-roster character/plot index and complete-reunion screening; all prior cohort candidates retained for full-record adjudication. Not exhaustive semantic certification.',findings,status:findings.length?'requires-adjudication':'no-substantial-collisions-found'},null,2)+'\n');
 }
 console.log(JSON.stringify({newCards:result.cards.length,newStories:result.stories.length,accountedCNY:provider.accountedCNY()}));
}finally{closeSync(fd);unlinkSync(lock);}
