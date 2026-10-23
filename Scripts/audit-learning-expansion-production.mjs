/** Read-only aggregate baseline. No user data or credentials are output. */
import { loadConfig } from '/opt/lingotrip/current/dist/config/env.js';
import { createDatabase } from '/opt/lingotrip/current/dist/db/client.js';
import { learningPolicy } from '/opt/lingotrip/current/dist/modules/learning/policy.js';
import { gaokaoUnitIds } from '/opt/lingotrip/current/dist/modules/learning/gaokao-policy.js';
const db=createDatabase(loadConfig());
try {
 const report=await db.sql.begin('read only',async sql=>{
  await sql`set local statement_timeout='15s'`;
  const complete=await sql`
   with eligible as (
    select u.id,u.level_key,v.payload from app.learning_units u join app.learning_unit_versions v on v.unit_id=u.id and v.version=u.current_version
    where u.published and v.payload ? 'originalGroup' and (u.level_key not in ('senior1','senior2','senior3') or u.id=any(${gaokaoUnitIds()}))
   ) select level_key,count(distinct id)::int as groups,count(distinct case when level_key in ('senior1','senior2','senior3') then q->>'id' else id||'/'||(q->>'id') end)::int as questions
   from eligible cross join lateral jsonb_array_elements(payload->'questions') q group by level_key order by level_key`;
  const bank=await sql`select v.payload->>'level' as level,count(distinct q.id)::int as questions from app.learning_bank_questions q join app.learning_bank_versions v on v.question_id=q.id and v.version=q.current_version where q.published and v.payload->>'level' not in ('kindergarten','senior1','senior2','senior3') and v.payload->'question'->>'type'<>'dictation' group by 1 order by 1`;
  const oldUnits=await sql`select u.id,v.content_hash,u.published from app.learning_units u join app.learning_unit_versions v on v.unit_id=u.id and v.version=u.current_version where u.id not like 'expansion.20261024.%' order by u.id`;
  return {checkedAt:new Date().toISOString(),readOnly:true,characterThreshold:learningPolicy.characterThreshold,complete,bank,oldUnits};
 });
 console.log(JSON.stringify(report));
}finally{await db.close();}
