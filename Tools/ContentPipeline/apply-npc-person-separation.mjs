// Apply exact-content editorial revisions; all existing approvals become stale naturally.
import {readFileSync,writeFileSync,openSync,closeSync,unlinkSync} from 'node:fs';
import {join} from 'node:path';import {createHash} from 'node:crypto';import {validate} from './npc-content.mjs';
const [out,source]=process.argv.slice(2),dir=join(out,'production-v3');
const read=f=>JSON.parse(readFileSync(join(dir,f))),hash=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
const write=(f,v)=>writeFileSync(join(dir,f),JSON.stringify(v,null,2)+'\n');
const rows=JSON.parse(readFileSync(source)),seeds=read('plan.json');
const lock=join(out,'running.lock'),fd=openSync(lock,'wx');writeFileSync(fd,String(process.pid));
try{
 for(const r of rows){
  if(hash(read(r.id+'.card.json'))!==hash(r.expectedCard)||hash(read(r.id+'.json'))!==hash(r.expectedContent)||hash(read(r.id+'.story-plan.json'))!==hash(r.expectedPlan))throw Error('Stale revision '+r.id);
  for(const k of ['name','age','gender','regionId','occupation','birthday','appearance'])if(r.card.card[k]!==r.expectedCard.card[k])throw Error('Identity changed '+r.id+'/'+k);
  if(hash(r.content.card)!==hash(r.card.card))throw Error('Card/story mismatch');
  const errors=validate(r.content,seeds.find(s=>s.id===r.id));if(errors.length)throw Error(r.id+':'+errors.join(';'));
 }
 for(const r of rows){
  const plan={...r.plan,cardHash:hash(r.card.card)};
  write(r.id+'.person-separation-evidence.json',r);
  write(r.id+'.card.json',r.card);write(r.id+'.json',r.content);write(r.id+'.story-plan.json',plan);
  write(r.id+'.explicit-redesign.json',{directionZh:r.reasonZh});
  write(r.id+'.draft-source.json',{cardHash:hash(r.card),planHash:hash(plan)});
  console.log(JSON.stringify({id:r.id,status:'revised-needs-review'}));
 }
}finally{closeSync(fd);unlinkSync(lock);}
