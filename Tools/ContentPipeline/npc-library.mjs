// Opt-in paid offline generation. No database or production publication access.
import { existsSync, mkdirSync, readFileSync, writeFileSync, openSync, closeSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { createLibraryProvider } from './library-provider.mjs';
import { npcStoryPrompt } from './npc-story-prompt.mjs';
import { validate } from './npc-content.mjs';

const [slotsPath, output, phase = 'plan'] = process.argv.slice(2);
if (!slotsPath || !output || !['plan', 'generate'].includes(phase)) throw Error('Usage: npc-library.mjs slots.json private-output plan|generate');
const slots = JSON.parse(readFileSync(slotsPath, 'utf8'));
if (slots.length !== 200 || new Set(slots.map(x => x.id)).size !== 200 || new Set(slots.map(x => x.avatarId)).size !== 200) throw Error('Expected 200 unique fixed avatar slots');
for (const s of slots) {
  if (!/^library-\d{3}$/.test(s.id) || s.age < s.ageMin || s.age > s.ageMax) throw Error('Invalid slot');
}
mkdirSync(output, { recursive: true });
const lock = join(output, 'running.lock');
const descriptor = openSync(lock, 'wx');
writeFileSync(descriptor, String(process.pid));
const provider = createLibraryProvider(output);
const write = (file, value) => writeFileSync(join(output, file), JSON.stringify(value, null, 2) + '\n');
const read = file => JSON.parse(readFileSync(join(output, file), 'utf8'));
const fingerprint = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
const inputHash = fingerprint(slots);
if (existsSync(join(output, 'slots.json')) && fingerprint(read('slots.json')) !== inputHash) throw Error('Cannot change bindings within a library version');
write('slots.json', slots);

const planPrompt = `Plan distinct fictional people for a preauthored English-learning travel app. Return JSON {"people":[{"id":"assigned id","name":"full name","brief":"180-260 Chinese characters"}]}.
Match each assigned id exactly. Age and gender are creative constraints from approved avatar metadata, not real identities. Do not infer ethnicity, nationality, profession or personality from appearance; no image is provided.
Read ALL existing briefs to avoid repeating a niche. Every brief needs a specific plausible occupation/life stage, two unexpected but coherent interests, a personal value, a real flaw/contradiction, a concrete formative experience, a current pursuit and distinct conversational habits. Respect age; do not default every older person to retirement or every young person to a student.
Describe a SMALL actionable encounter premise rooted in the assigned scene/action, with two genuine decisions and four plausible outcomes. No biography dumping, rescue cliches, teacher/mentor monoculture, forced intimacy, moral lessons, impossible props, invented user belongings or offscreen information. Every person should be enjoyable to talk with for a different reason. Include assertive, mischievous, disorganized, exuberant, competitive and practical people as well as quiet thoughtful people. No stereotypes. Names and nationality may be independently varied but never encode inferred ethnicity.
The 200-character roster is globally diverse, not 15 cities filled with versions of the same few archetypes. Avoid any existing combination of job, interests, tension and speech. Do not merely rename the same person. Return ONLY requested slots.`;

try {
  if (phase === 'plan') {
    const briefs = slots.filter(s => s.pilotId).map(s => ({ ...s }));
    const remaining = slots.filter(s => !s.pilotId);
    for (let offset = 0; offset < remaining.length; offset += 10) {
      const batch = remaining.slice(offset, offset + 10);
      const file = `plan-${String(offset / 10 + 1).padStart(2, '0')}.json`;
      let people;
      if (existsSync(join(output, file))) people = read(file);
      else {
        const result = await provider.request(file.replace('.json', ''), planPrompt, {
          existing: briefs.map(({ name, brief }) => ({ name, brief })),
          slots: batch.map(({ id, age, gender, regionId, actionId, scene }) => ({ id, age, gender, regionId, actionId, scene })),
        }, 10000);
        people = result.people;
      }
      if (!Array.isArray(people) || people.length !== batch.length || new Set(people.map(p => p.id)).size !== batch.length) throw Error('Incomplete planning batch');
      for (const s of batch) {
        const p = people.find(p => p.id === s.id);
        if (!p || typeof p.name !== 'string' || typeof p.brief !== 'string' || p.brief.length < 100 || briefs.some(b => b.name.toLowerCase() === p.name.toLowerCase())) throw Error('Invalid or duplicate planned identity: ' + s.id);
        briefs.push({ ...s, name: p.name, brief: p.brief });
      }
      write(file, people);
      write('briefs.json', slots.map(s => briefs.find(b => b.id === s.id)).filter(Boolean));
      console.log(JSON.stringify({ phase, planned: briefs.length, accountedCNY: provider.accountedCNY() }));
    }
  } else {
    const briefs = read('briefs.json');
    if (briefs.length !== 200) throw Error('Complete and inspect global planning before generation');
    let cursor = 0;
    let failed = false;
    const workers = await Promise.allSettled([0, 1, 2, 3].map(async () => {
      try { while (!failed && cursor < briefs.length) {
        const seed = briefs[cursor++];
        if (seed.pilotId) continue; // Accepted pilots are copied separately without new calls.
        const destination = seed.id + '.json';
        if (existsSync(join(output, destination))) continue;
        let issues = [], value;
        for (let attempt = 1; attempt <= 3; attempt++) {
          const result = await provider.request(`${seed.id}-draft-${attempt}`, npcStoryPrompt, {
            seed: { name: seed.name, age: seed.age, gender: seed.gender, regionId: seed.regionId, actionId: seed.actionId, scene: seed.scene, brief: seed.brief },
            corrections: issues,
          });
          issues = validate(result, seed);
          if (!issues.length) { value = result; break; }
        }
        if (!value) { write(seed.id + '.issues.json', issues); continue; }
        write(destination, value);
        console.log(JSON.stringify({ phase, id: seed.id, status: 'draft-needs-editorial-review', accountedCNY: provider.accountedCNY() }));
      } } catch (error) { failed = true; throw error; }
    }));
    const failure = workers.find(result => result.status === 'rejected');
    if (failure) throw failure.reason;
  }
} finally {
  closeSync(descriptor);
  unlinkSync(lock);
}
