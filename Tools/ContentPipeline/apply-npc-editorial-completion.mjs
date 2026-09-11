import{readFileSync,writeFileSync,existsSync,openSync,closeSync,unlinkSync}from'node:fs';import{join}from'node:path';import{createHash}from'node:crypto';
const[out,source]=process.argv.slice(2),p=join(out,'production-v3'),read=n=>JSON.parse(readFileSync(join(p,n))),write=(n,v)=>writeFileSync(join(p,n),JSON.stringify(v,null,2)+'\n'),hash=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
const lock=join(out,'running.lock'),fd=openSync(lock,'wx');writeFileSync(fd,String(process.pid));
try{
 const id='library-134',card=read(id+'.card.json'),plan=read(id+'.story-plan.json'),value={...JSON.parse(readFileSync(source)),card:card.card};
 if(existsSync(join(p,id+'.json'))&&hash(read(id+'.json'))!==hash(value))throw Error('Existing 134 differs');
 if(!existsSync(join(p,id+'.json'))){write(id+'.json',value);write(id+'.draft-source.json',{cardHash:hash(card),planHash:hash(plan)});write(id+'.manual-authorship.json',{sourceHash:hash(value),reason:'Directly authored all four bilingual paths and independent reunion; unresolved provider attempt is preserved, never retried.'});}
 const c=read('library-117.card.json');
 if(c.card.personality.includes('a chipped rim')){
  if(hash(c)!=='3bd4439a31b222c2d3c6244725b9a8c3956a841a4d52d8b2d96cc20ce62e11a8')throw Error('Stale card 117 correction');
  const before=structuredClone(c);c.card.personality=c.card.personality.replace("a chipped rim he's never bothered to fix","a small chip on its outer wall that he has left visible");
  c.card.personaVoice.anchorLines=c.card.personaVoice.anchorLines.map(x=>x==='This chip? Still perfectly safe. Been drinking from it all year.'?'This mark? Only on the outside. I still use this one.':x);
  const story=read('library-117.json'),oldStory=structuredClone(story);story.card=c.card;
  for(const n of story.story.nodes)for(const b of n.beats){b.english=b.english.replace('Perfectly safe.','The rim is smooth.');b.chinese=b.chinese.replace('完全安全。','杯口是光滑的。');}
  write('library-117.card-before-exterior-chip.json',before);write('library-117.story-before-exterior-chip.json',oldStory);write('library-117.card.json',c);write('library-117.json',story);
  const plan117=read('library-117.story-plan.json');plan117.cardHash=hash(c.card);write('library-117.story-plan.json',plan117);write('library-117.draft-source.json',{cardHash:hash(c),planHash:hash(plan117)});
  write('library-117.exterior-chip-correction.json',{beforeCard:hash(before),afterCard:hash(c),beforeStory:hash(oldStory),afterStory:hash(story),reason:'Correct contradictory rim/outer-wall location, remove blanket safety claim; preserve niche and identity. Requires fresh card and story reviews.'});
 }
 console.log('Authored 134 and bounded 117 correction installed; review pending.');
}finally{closeSync(fd);unlinkSync(lock);}
