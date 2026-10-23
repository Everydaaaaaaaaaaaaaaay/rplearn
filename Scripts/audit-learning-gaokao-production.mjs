/** Bounded, read-only audit. Outputs only aggregate counts/digests, no credentials or user data. */
import { readFile } from 'node:fs/promises';
import { loadConfig } from '/opt/lingotrip/current/dist/config/env.js';
import { createDatabase } from '/opt/lingotrip/current/dist/db/client.js';
import { contentHash, publicUnit } from '/opt/lingotrip/current/dist/modules/learning/content.js';
import { LearningEngineRepository } from '/opt/lingotrip/current/dist/modules/learning/engine-repository.js';
const mode = process.argv[2];
if (!['preview','verify'].includes(mode)) throw Error('Use preview or verify');
const db=createDatabase(loadConfig());
const report={checkedAt:new Date().toISOString(),mode,readOnly:true};
try {
 await db.sql.begin('isolation level repeatable read read only',async sql=>{
  await sql`set local statement_timeout='15s'`;
  const legacy = await sql`select u.id,v.version,v.content_hash,jsonb_array_length(v.payload->'questions') as questions from app.learning_units u join app.learning_unit_versions v on v.unit_id=u.id and v.version=u.current_version where u.level_key in ('senior1','senior2','senior3') and u.id not like 'gaokao.%' order by u.id`;
  report.legacyPublishedVersionsDigest=contentHash(legacy);
  report.excludedLegacyUnits=legacy.length;
  report.excludedLegacyResponses=legacy.reduce((n,r)=>n+r.questions,0);
  const attempts=await sql`select a.id,a.user_id,a.character_id,a.level_key,c.role_key,a.snapshot,v.content_hash from app.learning_attempts a join app.learning_characters c on c.user_id=a.user_id and c.character_id=a.character_id left join app.learning_unit_versions v on v.unit_id=a.unit_id and v.version=a.unit_version where a.level_key in ('senior1','senior2','senior3') and a.first_completed_at is null and (a.unit_id is null or a.unit_id not like 'gaokao.%') order by a.id`;
  report.legacyActiveContentDigest=contentHash(attempts.map(a=>({id:a.id,snapshot:a.snapshot,contentHash:a.content_hash})));
  report.storedLegacyUnfinished=attempts.length;
  const users=[...new Set(attempts.map(a=>a.user_id))];
  const rewards=await sql`select attempt_id,question_id,points from app.learning_rewards where user_id=any(${users}) order by attempt_id,question_id`;
  const progress=await sql`select user_id,level_key,points from app.learning_level_progress where user_id=any(${users}) order by user_id,level_key`;
  report.affectedRewardsDigest=contentHash(rewards);report.affectedProgressDigest=contentHash(progress);
  if(mode==='verify') {
   const {gaokaoCatalog,isAdmittedGaokaoUnit}=await import('/opt/lingotrip/current/dist/modules/learning/gaokao-policy.js');
   const {LearningBankSession}=await import('/opt/lingotrip/current/dist/modules/learning/bank-repository.js');
   const catalog=gaokaoCatalog();
   const rows=await sql`select u.level_key,v.payload from app.learning_units u join app.learning_unit_versions v on v.unit_id=u.id and v.version=u.current_version where u.published and u.id like 'gaokao.%' order by u.id`;
   if(rows.length!==12 || rows.some(r=>!isAdmittedGaokaoUnit(r.payload))) throw Error('Deployed admission mismatch');
   report.admittedUnits=rows.length;
   report.uniqueSourceQuestions=new Set(rows.flatMap(r=>r.payload.questions.map(q=>q.id))).size;
   report.practiceResponsesByLevel={};
   const engine=new LearningEngineRepository(db);
   report.listingAndAvailabilityChecks=0;report.legacyAdvertisedActive=0;
   const user=users[0]??'00000000-0000-4000-8000-000000000001';
   for(const level of ['senior1','senior2','senior3']) {
    const units=rows.filter(r=>r.level_key===level).map(r=>r.payload);
    report.practiceResponsesByLevel[level]=units.map(u=>u.questions.length).sort((a,b)=>a-b);
    for(const u of units){const p=publicUnit(u);if(p.questions.some(q=>!q.material||'answer'in q||'acceptedAnswers'in q))throw Error('Public input or answer leakage');}
    const list=await engine.read(user,s=>s.originals(level));
    if(list.units.length!==4)throw Error('Listing contains nonadmitted content');
    if((await new LearningBankSession(sql,user).choices(level,'oliver')).length)throw Error('Legacy bank fallback');
    report.listingAndAvailabilityChecks++;
   }
   for(const a of attempts){
    const state=await engine.read(a.user_id,s=>s.character(a.character_id));
    if(state.activeAttemptId===a.id)report.legacyAdvertisedActive++;
    const available=await engine.read(a.user_id,s=>s.availability(a.role_key,a.level_key,a.character_id,true));
    if(available.availableUnits<0||available.availableUnits>4)throw Error('Invalid availability');
   }
   if(report.legacyAdvertisedActive)throw Error('Legacy active drill advertised');
   const imageIds=[...new Set(catalog.practices.flatMap(p=>p.unit.questions.flatMap(q=>(q.materialImages??[]).map(i=>i.assetId))))];
   const images=await sql`select id from app.learning_image_assets where id=any(${imageIds})`;
   if(images.length!==imageIds.length)throw Error('Missing necessary chart metadata');
   report.necessaryCharts=images.length;
   const before=JSON.parse(await readFile(process.argv[3],'utf8'));
   for(const key of ['legacyPublishedVersionsDigest','legacyActiveContentDigest','affectedRewardsDigest','affectedProgressDigest'])if(before[key]!==report[key])throw Error(`Preservation audit mismatch: ${key}`);
   report.historyAndProgressPreserved=true;
  }
 });
 report.passed=true;console.log(JSON.stringify(report));
}finally{await db.close();}
