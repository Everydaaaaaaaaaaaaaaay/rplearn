// Assemble only the exact reviewed content. Provider receipts never enter the app.
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {join,dirname} from 'node:path';
import {createHash} from 'node:crypto';
import {validate} from './npc-content.mjs';
const [output,destination,version='2026-09-11-v3']=process.argv.slice(2);
if(!output||!destination)throw Error('build-npc-library.mjs private-output destination [version]');
const dir=join(output,'production-v3'),read=f=>JSON.parse(readFileSync(join(dir,f),'utf8'));
const digest=x=>createHash('sha256').update(JSON.stringify(x)).digest('hex');
const seeds=read('plan.json');
const contents=seeds.map(s=>({id:s.id,...read(s.id+'.json')}));
for(const mode of ['cards','stories']){
 const audit=read('global-'+mode+'.json');
 const source=mode==='cards'?seeds.map(s=>({id:s.id,...read(s.id+'.card.json')})):contents;
 if(audit.snapshot!==digest(source))throw Error('Stale global '+mode+' audit');
 if(audit.findings.length){
  const dispositions=read('global-'+mode+'-adjudications.json');
  if(dispositions.snapshot!==audit.snapshot)throw Error('Stale adjudications');
  for(const p of audit.findings){const decision=dispositions.decisions.find(d=>[d.left,d.right].sort().join('/')===[p.left,p.right].sort().join('/'));
   if(decision?.status!=='distinct'||!decision.reasonZh||decision.reasonZh.length<20)throw Error('Unresolved duplicate '+p.left+'/'+p.right);
  }
 }
}
function uuid(seed){const b=createHash('sha256').update('lingotrip-authored-v3:'+seed).digest().subarray(0,16);b[6]=(b[6]&15)|0x50;b[8]=(b[8]&63)|0x80;const h=b.toString('hex');return [h.slice(0,8),h.slice(8,12),h.slice(12,16),h.slice(16,20),h.slice(20)].join('-');}
function traveler(seed){const body=(BigInt('0x'+createHash('sha256').update(seed).digest('hex').slice(0,14))%10000000000n).toString().padStart(10,'0');let sum=0;for(let i=9;i>=0;i--){const n=Number(body[i])*(i%2?2:1);sum+=n>9?n-9:n;}return body+((10-sum%10)%10);}
const entries=seeds.map(seed=>{
 const value=read(seed.id+'.json'),review=read(seed.id+'.review.json');
 if(review.status!=='reviewed'||review.contentHash!==digest(value)||review.issues?.length)throw Error('Unreviewed story '+seed.id);
 const approvedCard=read(seed.id+'.card.json'),cardReview=read(seed.id+'.card-review.json');
 if(cardReview.status!=='reviewed'||cardReview.contentHash!==digest(approvedCard)||cardReview.issues?.length)throw Error('Unreviewed card '+seed.id);
 const errors=validate(value,seed);if(errors.length)throw Error(seed.id+': '+errors.join(';'));
 if(digest(value.card)!==digest(read(seed.id+'.card.json').card))throw Error('Story/card audit mismatch '+seed.id);
 const card={...structuredClone(value.card),appearance:seed.appearance};delete card.summaryZh;
 // Redundant draft-only annotation is already stated in the reviewed background.
 delete card.personaVoice.privatePortfolio;
 return {id:uuid(seed.avatarId),travelerId:traveler(seed.avatarId),avatarId:seed.avatarId,avatarSHA256:seed.avatarSHA256,card,summaryZh:value.summaryZh,story:value.story,reunion:value.reunion};
});
for(const key of ['id','travelerId','avatarId'])if(new Set(entries.map(e=>e[key])).size!==200)throw Error('Identity collision '+key);
mkdirSync(dirname(destination),{recursive:true});writeFileSync(destination,JSON.stringify({version:1,libraryVersion:version,entries})+'\n');
console.log(JSON.stringify({entries:entries.length,firstMeetingPaths:entries.length*4,reunions:entries.length,bytes:Buffer.byteLength(readFileSync(destination)),sha256:createHash('sha256').update(readFileSync(destination)).digest('hex')}));
