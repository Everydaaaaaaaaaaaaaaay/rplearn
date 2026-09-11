// Mechanical metadata edit: preserve reviewed narrative and record an explicit approval lineage.
import{readFileSync,writeFileSync}from'node:fs';import{join}from'node:path';import{createHash}from'node:crypto';
const[output]=process.argv.slice(2);if(!output)throw Error('private-output');
const dir=join(output,'production-v3'),read=f=>JSON.parse(readFileSync(join(dir,f))),hash=x=>createHash('sha256').update(JSON.stringify(x)).digest('hex');
const seeds=read('plan.json'),changes=[];
for(const s of seeds){if(s.pilotId)continue;const value=read(s.id+'.card.json'),review=read(s.id+'.card-review.json');if(review.status!=='reviewed'||review.contentHash!==hash(value))throw Error('Unreviewed '+s.id);
 const day=createHash('sha256').update('lingotrip-birthday-v3:'+s.avatarId).digest().readUInt32BE(0)%365;
 const date=new Date(Date.UTC(2001,0,1+day)).toISOString().slice(5,10);if(value.card.birthday===date)continue;
 const next=structuredClone(value);next.card.birthday=date;
 const before=structuredClone(value),after=structuredClone(next);delete before.card.birthday;delete after.card.birthday;
 if(hash(before)!==hash(after))throw Error('Narrative changed');
 changes.push({id:s.id,previousHash:hash(value),contentHash:hash(next),before:value.card.birthday,after:date,next,review});
}
// Narrative birthday references were separately inspected: generic celebrations only, no date-dependent biography.
for(const c of changes){const{next,review,...record}=c;writeFileSync(join(dir,c.id+'.card.json'),JSON.stringify(next,null,2)+'\n');writeFileSync(join(dir,c.id+'.card-review.json'),JSON.stringify({...review,contentHash:c.contentHash,mechanicalRevisions:[...(review.mechanicalRevisions??[]),{...record,method:'Deterministic birthday-only edit; every other narrative and identity field byte-identical to the reviewed object.'}]},null,2)+'\n');}
const counts={};for(const s of seeds){const b=read(s.id+'.card.json').card.birthday;counts[b]=(counts[b]??0)+1;}
const report={method:'SHA256 of stable avatar ID mapped to 365 real calendar dates; ten accepted pilot birthdays preserved. No age, gender, narrative or avatar changes.',changes:changes.map(({next,review,...c})=>c),distinctDates:Object.keys(counts).length,maximumSharedBirthday:Math.max(...Object.values(counts))};
writeFileSync(join(dir,'birthday-metadata-review.json'),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({changed:changes.length,distinctDates:report.distinctDates,maximumSharedBirthday:report.maximumSharedBirthday}));
