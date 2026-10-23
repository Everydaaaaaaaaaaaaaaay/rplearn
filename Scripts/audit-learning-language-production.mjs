/** Read-only rollout audit. Run on the server with its normal environment files.
 * Does not log users, attempts, answers, credentials or private question text.
 */
import { readFile } from 'node:fs/promises';
import { loadConfig } from '/opt/lingotrip/current/dist/config/env.js';
import { createDatabase } from '/opt/lingotrip/current/dist/db/client.js';
import { contentHash, publicUnit, unitSchema } from '/opt/lingotrip/current/dist/modules/learning/content.js';
import { LearningEngineRepository } from '/opt/lingotrip/current/dist/modules/learning/engine-repository.js';
const mode = process.argv[2];
if (!['preview', 'verify'].includes(mode)) throw new Error('Use preview or verify');
const registryPath = process.argv[3] ?? '/opt/lingotrip/current/config/learning/presentation-revisions.json';
const registry = JSON.parse(await readFile(registryPath, 'utf8'));
const revisions = new Map(registry.entries.map((r) => [r.sourceHash, r]));
function expected(q) {
  const { id, ...body } = q;
  const patch = revisions.get(contentHash(body));
  return patch ? { ...q, prompt: patch.prompt, ...(patch.options ? { options: q.options.map((o) => ({ ...o, text: patch.options.find((p) => p.id === o.id).text })) } : {}) } : q;
}
function appropriate(q, level) {
  if (!/^(junior[123]|senior[123]|undergraduate|postgraduate|advanced)$/.test(level) || !['choice', 'listeningChoice'].includes(q.type)) return true;
  const directions = /^(?:(?:[A-Z]篇 · )?第\d+空(?:（\d+分）)?|第\d+句空|第\d+处(?:：选择一整个段落)?|第\d+题（问题在录音中）)$/.test(q.prompt);
  return (directions || !/\p{Script=Han}/u.test(q.prompt)) && (/\bmean in Chinese\?$/i.test(q.prompt) || q.options.every((o) => o.imageAssetId !== undefined || !/\p{Script=Han}/u.test(o.text)));
}
const db = createDatabase(loadConfig());
const engine = new LearningEngineRepository(db);
const report = { checkedAt: new Date().toISOString(), mode, readOnly: true, registryEntries: revisions.size,
  currentUnits: 0, currentQuestions: 0, correctedCurrentQuestions: 0, activeAttempts: 0, correctedActiveQuestions: 0,
  currentBankQuestions: 0, correctedBankQuestions: 0, unresolved: [], repositoryReadsVerified: 0, liveScriptsVerified: 0 };
function check(unit, active = false) {
  const sourceHash = contentHash(unit);
  const shown = mode === 'verify' ? publicUnit(unit) : undefined;
  for (const q of unit.questions) {
    const projected = expected(q);
    if (projected !== q) report[active ? 'correctedActiveQuestions' : 'correctedCurrentQuestions']++;
    if (!appropriate(projected, unit.level)) report.unresolved.push({ unit: unit.id, question: q.id, type: q.type });
    if (shown) {
      const actual = shown.questions.find((p) => p.id === q.id);
      if (actual.prompt !== projected.prompt || ('options' in projected && JSON.stringify(actual.options) !== JSON.stringify(projected.options))) throw new Error('Public projection differs from reviewed copy');
      if ('answer' in actual || 'acceptedAnswers' in actual) throw new Error('Answer leakage');
    }
  }
  if (contentHash(unit) !== sourceHash) throw new Error('Projection mutated source');
}
try {
  await db.sql.begin('isolation level repeatable read read only', async (sql) => {
    await sql`set local statement_timeout='15s'`;
    const versions = await sql`select unit_id,version,content_hash from app.learning_unit_versions order by unit_id,version`;
    report.frozenVersionsDigest = contentHash(versions);
    const units = await sql`select v.payload from app.learning_units u join app.learning_unit_versions v on v.unit_id=u.id and v.version=u.current_version where u.published order by u.id`;
    for (const row of units) {
      const unit = unitSchema.parse(row.payload); report.currentUnits++; report.currentQuestions += unit.questions.length; check(unit);
    }
    const bank = await sql`select v.payload from app.learning_bank_questions q join app.learning_bank_versions v on v.question_id=q.id and v.version=q.current_version where q.published order by q.id`;
    for (const row of bank) {
      const entry = row.payload; const q = expected(entry.question); report.currentBankQuestions++;
      if (q !== entry.question) report.correctedBankQuestions++;
      if (!appropriate(q, entry.level)) report.unresolved.push({ bankQuestion: entry.id, level: entry.level, sourceHash: contentHash(Object.fromEntries(Object.entries(entry.question).filter(([k]) => k !== 'id'))), prompt: entry.question.prompt, options: entry.question.options });
    }
    const attempts = await sql`select a.id,a.user_id,coalesce(a.snapshot,v.payload) as payload from app.learning_attempts a left join app.learning_unit_versions v on v.unit_id=a.unit_id and v.version=a.unit_version where a.first_completed_at is null order by a.id`;
    report.activeSnapshotsDigest = contentHash(attempts.map((a) => contentHash(a.payload)).sort());
    for (const row of attempts) {
      report.activeAttempts++; check(unitSchema.parse(row.payload), true);
    }
    if (mode === 'verify') for (const row of attempts.slice(0, 20)) {
      const view = await engine.read(row.user_id, (s) => s.attempt(row.id));
      const unit = unitSchema.parse(row.payload);
      for (const q of unit.questions) {
        if (view.unit.questions.find((v) => v.id === q.id)?.prompt !== expected(q).prompt) throw new Error('Repository response mismatch');
        if (!unit.originalGroup && q.type === 'listeningChoice' && expected(q) !== q) {
          const script = await engine.read(row.user_id, (s) => s.listeningScript(row.id, q.id, q.audio.assetId));
          if (script.segments[0]?.pauseAfterMs !== 3000 || script.segments.at(-1)?.text !== `Question: ${expected(q).prompt}`) throw new Error('Live spoken question mismatch');
          report.liveScriptsVerified++;
        }
      }
      report.repositoryReadsVerified++;
    }
  });
  report.passed = report.unresolved.length === 0;
  console.log(JSON.stringify(report));
  if (!report.passed) process.exitCode = 1;
} finally { await db.close(); }
