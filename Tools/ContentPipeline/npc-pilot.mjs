// Opt-in offline content experiment. Never connects to the application database.
// node --env-file=/secure/provider.env npc-pilot.mjs briefs.json /private/output
import { readFileSync, writeFileSync, appendFileSync, mkdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const [input, output, repairFile] = process.argv.slice(2);
const repairs = repairFile ? JSON.parse(readFileSync(repairFile, "utf8")) : {};
if (!input || !output || !process.env.OPENROUTER_API_KEY) throw Error('Input, output and server-side OPENROUTER_API_KEY required');
const seeds = JSON.parse(readFileSync(input, 'utf8'));
if (seeds.length !== 10 || new Set(seeds.map(s => s.id)).size !== 10 || seeds.some(s => !/^pilot-(0[1-9]|10)$/.test(s.id))) throw Error('This pilot is limited to ten unique fixed IDs');
mkdirSync(output, { recursive: true });
const ledgerPath = join(output, 'ledger.jsonl');
const ledger = existsSync(ledgerPath) ? readFileSync(ledgerPath, 'utf8').trim().split('\n').filter(Boolean).map(JSON.parse) : [];
const reserved = new Map();
for (const row of ledger) {
  if (row.kind === 'dispatch') reserved.set(row.key, row.upperUSD);
  if (row.kind === 'receipt' && row.costUSD !== null) reserved.set(row.key, row.costUSD);
}
const capUSD = 3 / 7.2;
const spent = () => [...reserved.values()].reduce((a, b) => a + b, 0);
const log = row => { appendFileSync(ledgerPath, JSON.stringify({ at: new Date().toISOString(), ...row }) + '\n'); };
import { validate } from './npc-content.mjs';

const system = `Write one original fictional character and their COMPLETE preauthored branching encounter in JSON.
This is a production-content pilot for an English-learning travel app, not live roleplay. No tool use.
The seed is a creative brief, not a real person's identity. Only age/gender constrain avatar compatibility.
NO image or appearance cues are supplied; never invent nationality/personality/job from appearance.
All ten briefs describe DIFFERENT people; preserve this one's niche, tensions and speech without making a caricature.
Write a rounded English character card matching this exact shape:
{"card":{"name":"seed name","age":0,"gender":"seed gender","regionId":"london","nationality":"fictional nationality chosen independently","occupation":"specific occupation","hobbies":["at least two"],"personality":"60-100 English words, strengths and contradictions","background":"100-150 English words, concrete past and current pursuit, no default tragedy","speechStyle":"distinct rhythm and habits","hometown":"place","languages":["English"],"birthday":"MM-DD","signature":"short line","appearance":"","personaVoice":{"values":["two"],"flaws":["two"],"boundaries":["two"],"conversationalHabits":["two"],"anchorLines":["three natural sample utterances"]}},"summaryZh":"80-140 Chinese characters about what makes them memorable","story":{"titleZh":"Chinese title","actionId":"seed actionId","nodes":[...]}}
Story is a complete binary tree of THREE parts. Nodes IN ORDER: start,a,b,aa,ab,ba,bb.
start has two choices leading to a,b. a has two choices to aa,ab; b has two choices to ba,bb.
The four terminal nodes have choices:[]. Each node is {"id":"...","beats":[{"speaker":"narrator or npc","english":"...","chinese":"..."}],"choices":[{"english":"...","chinese":"...","next":"..."}]}.
EVERY node: 4-6 beats, >=2 spoken NPC beats and >=1 narration. A beat is 1-2 natural sentences, 15-35 English words. Everyday B1 English, faithful natural Chinese translations.
Each played path thus has 12-18 beats, one developing shared experience, two genuine action decisions, a satisfying small ending.
The chosen starting ACTION must visibly occur in start. Explain how strangers begin talking without forced introductions or biographies.
Development follows ONLY its chosen action. Terminal aa/ab depend on a; ba/bb depend on b. Do not leak events from another branch.
Different choices change a concrete action/result, not just polite wording. All four endings must differ meaningfully and remember the path.
Characters retain agency and flaws, but never humiliate learners. Do not force user emotions, romance, possessions, expertise or past meetings.
Do not repeat whole beats. Avoid generic wisdom, biography dumping, instant intimacy and universal agreement.
Narration is observable action only, NEVER spoken quotations. Put ALL spoken words in npc beats. No English terms in Chinese translations unless a proper name requires them.
No exact time, morning/afternoon, season, daylight or cold/hot assumptions outside the supplied scene. Rain is allowed in rain cafe.
After EVERY terminal the UI will independently show Add Friend / Leave. Do not put contact gating, phone numbers or eligibility in content. Do not say already friends.
All story nodes have English and Chinese. Only JSON, no markdown. Keep planning short and spend output on complete content.`;

async function generate(seed) {
  const destination = join(output, seed.id + '.json');
  const previous = existsSync(destination) ? JSON.parse(readFileSync(destination, 'utf8')) : null;
  if (repairFile && !repairs[seed.id]) return;
  if (!repairFile && previous && !validate(previous, seed).length) return;
  let issues = repairs[seed.id] ?? [];
  for (let attempt = 1; attempt <= 2; attempt++) {
    const key = `${seed.id}-${repairFile ? "repair-" : ""}${attempt}`;
    // Never silently repeat an interrupted paid dispatch on resume.
    if (reserved.has(key)) continue;
    const messages = [{ role: 'system', content: system }, { role: 'user', content: JSON.stringify({ seed: { name: seed.name, age: seed.age, gender: seed.gender, regionId: seed.regionId, actionId: seed.actionId, scene: seed.scene, brief: seed.brief }, corrections: [...(repairs[seed.id] ?? []), ...issues], ...(repairFile ? { previous, instruction: "Return only story and summaryZh; the original card is preserved outside the model. Repair story and summary only. Keep all seven nodes and complete endings; resolve every listed issue." } : {}) }) }];
    const maxTokens = 14000;
    // Provider price ceilings are USD per million tokens. UTF-8 bytes conservatively bound input tokens.
    const upperUSD = (Buffer.byteLength(JSON.stringify(messages)) * 0.2 + maxTokens * 0.6) / 1e6 * 1.1;
    if (spent() + upperUSD > capUSD) throw Error('Pilot CNY 3 budget cap reached');
    reserved.set(key, upperUSD);
    log({ kind: 'dispatch', key, upperUSD });
    const body = { model: 'z-ai/glm-5.3-flash', messages, max_tokens: maxTokens, temperature: 0.65, reasoning: { effort: 'minimal' }, response_format: { type: 'json_object' }, provider: { order: ['Parasail'], allow_fallbacks: true, require_parameters: true, max_price: { prompt: 0.2, completion: 0.6 } }, user: 'lingotrip-offline-npc-pilot-20260911' };
    writeFileSync(join(output, key + '.request.json'), JSON.stringify(body, null, 2));
    const start = Date.now();
    try {
      const response = await fetch('https://openrouter.ai/api/v1/chat/completions', { method: 'POST', headers: { authorization: `Bearer ${process.env.OPENROUTER_API_KEY}`, 'content-type': 'application/json', 'x-openrouter-title': 'LingoTrip offline content pilot' }, body: JSON.stringify(body), signal: AbortSignal.timeout(240000) });
      const raw = await response.text();
      writeFileSync(join(output, key + '.response.json'), raw);
      const envelope = JSON.parse(raw);
      const costUSD = typeof envelope.usage?.cost === 'number' ? envelope.usage.cost : null;
      if (costUSD !== null) reserved.set(key, costUSD);
      log({ kind: 'receipt', key, status: response.status, ms: Date.now() - start, costUSD, usage: envelope.usage ?? null, provider: envelope.provider, requestId: envelope.id });
      if (!response.ok) throw Error(`Provider HTTP ${response.status}: ${envelope.error?.message ?? 'unknown'}`);
      const text = envelope.choices?.[0]?.message?.content;
      const value = JSON.parse(text);
      if (repairFile) value.card = previous.card;
      issues = validate(value, seed);
      if (!issues.length) {
        writeFileSync(destination, JSON.stringify(value, null, 2) + '\n');
        console.log(JSON.stringify({ id: seed.id, status: 'generated', ms: Date.now() - start, costCNY: costUSD === null ? null : costUSD * 7.2 }));
        return;
      }
      log({ kind: 'validation', key, issues });
    } catch (error) {
      issues = [String(error), ...issues];
      log({ kind: 'failure', key, ms: Date.now() - start, error: String(error) });
    }
    console.log(JSON.stringify({ id: seed.id, status: 'retry-needed', issues }));
  }
  console.log(JSON.stringify({ id: seed.id, status: 'incomplete' }));
}
let cursor = 0;
await Promise.all([0, 1].map(async () => { while (cursor < seeds.length) await generate(seeds[cursor++]); }));
console.log(JSON.stringify({ status: 'finished', accountedUpperCNY: spent() * 7.2 }));
