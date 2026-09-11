// Install a directly authored missing draft. Approval remains a separate operation.
import{readFileSync,writeFileSync,existsSync,openSync,closeSync,unlinkSync}from'node:fs';
import{join,basename}from'node:path';import{createHash}from'node:crypto';import{validate}from'./npc-content.mjs';
const[out,id,source]=process.argv.slice(2);if(!out||!/^library-\d{3}$/.test(id??'')||!source)throw Error('private-output library-XXX source.json');
const p=join(out,'production-v3'),read=n=>JSON.parse(readFileSync(join(p,n))),hash=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
const lock=join(out,'running.lock'),fd=openSync(lock,'wx');writeFileSync(fd,String(process.pid));
try{
 const seed=read('plan.json').find(s=>s.id===id);if(!seed||seed.pilotId)throw Error('Not a non-pilot identity');
 const card=read(id+'.card.json'),approval=read(id+'.card-review.json');if(approval.status!=='reviewed'||approval.contentHash!==hash(card))throw Error('Card is not approved');
 const sourceValue=JSON.parse(readFileSync(source));if(sourceValue.card)throw Error('Source cannot override fixed identity');
 const value={...sourceValue,card:card.card},errors=validate(value,seed),r=value.reunion;
 if(!r?.titleZh||!Array.isArray(r.beats)||r.beats.length<4||r.beats.length>6||r.beats[0]?.speaker!=='narrator'||r.beats.filter(b=>b.speaker==='npc').length<2)errors.push('Invalid reunion');
 if(errors.length)throw Error(errors.join(';'));
 const dest=join(p,id+'.json');if(existsSync(dest)){if(hash(read(id+'.json'))!==hash(value))throw Error('Existing draft differs; explicit repair required');console.log('Already installed '+id);}else{
  writeFileSync(dest,JSON.stringify(value,null,2)+'\n');
  writeFileSync(join(p,id+'.draft-source.json'),JSON.stringify({cardHash:hash(card),planHash:hash(read(id+'.story-plan.json'))},null,2)+'\n');
  writeFileSync(join(p,id+'.manual-authorship.json'),JSON.stringify({source:basename(source),sourceHash:hash(sourceValue),contentHash:hash(value),status:'awaiting-review',providerAttempts:'Preserved without replay'},null,2)+'\n');
  console.log('Installed unreviewed draft '+id);
 }
}finally{closeSync(fd);unlinkSync(lock);}
