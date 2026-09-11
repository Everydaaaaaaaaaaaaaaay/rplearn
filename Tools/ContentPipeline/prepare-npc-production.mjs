import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
const base = 'Content/NPCLibrary/2026-09-11/';
const read = name => JSON.parse(readFileSync(base + name, 'utf8'));
const slots = read('slots.json');
const old = new Map(read('briefs.draft.json').map(s => [s.id, s]));
const jobs = read('directions/occupations.json');
const tensions = read('directions/tensions.json');
const interests = read('directions/interests.json');
const lives = read('directions/lifeTextures.json');
const events = read('directions/events.json');
const voices = ['short direct sentences, comfortable pauses', 'warmly energetic, tells one concrete detail before the point', 'dry humour with precise ordinary words', 'quick playful questions followed by genuine listening', 'unhurried vivid comparisons used sparingly', 'matter-of-fact then unexpectedly delighted by a small thing', 'slightly formal courtesy, willing to disagree plainly', 'gentle volume and firm preferences', 'candid self-corrections without excessive apologies', 'buoyant rhythm, short enthusiastic observations', 'thoughtful questions without interrogating', 'practical demonstrations, explains what they are doing', 'understated teasing aimed only at themself', 'clear boundaries said kindly and briefly', 'curious tangents but remembers the other person’s answer', 'expressive descriptions without universal life lessons', 'economical words, occasionally adds an exact small detail', 'confident opinion with room for a different taste', 'reflective but never solemn or a therapist', 'relaxed and conversational, admits uncertainty'];
const dynamics = ['NPC has a clear preference and can disagree without ending the encounter', 'a small test reveals a tradeoff and changes what NPC is willing to do', 'NPC asks for perspective but keeps responsibility for their own decision', 'playful approach meets a practical constraint; neither person is the universal expert', 'NPC initially overcomplicates one small step, then explicitly chooses what to keep', 'two legitimate priorities remain different; finish without forced agreement', 'a personal detail emerges through action, not a biography speech', 'NPC says no to one part kindly and offers a real alternative', 'a tentative idea gets a concrete trial and an imperfect but satisfying result', 'one quiet pause matters; do not fill every gap with moral commentary', 'NPC spots an inconsistency in their own plan and names it without a redemption arc', 'a small shared joke appears from the particular materials, not a stock punchline', 'user choice affects whether NPC keeps, changes or abandons their own draft', 'NPC respects a less ambitious option and does not pressure the user to do more', 'a specific memory is volunteered briefly when the present action makes it relevant', 'NPC can be pleased by a partial result without claiming instant intimacy', 'NPC’s mild impatience or hesitation has an observable consequence, then settles', 'the second choice resolves a fresh practical detail, not a reworded first choice', 'NPC offers the user a meaningful role without assigning them expertise', 'a concrete object ends up visibly different depending on the path'];
let index = 0;
const actionCounts = new Map();
const result = slots.map(slot => {
  if (slot.pilotId) return { ...slot, productionVersion: 3, editorialSource: 'accepted-pilot' };
  const i = index++;
  const job = jobs[(i * 73) % jobs.length];
  const career = slot.age < 24 ? `职业起点：${job}的入门助理或学徒，不具有超出年龄的资历。` : slot.age >= 65 ? (i % 3 === 0 ? `过去从事${job}，现在已退休；日常不以指导年轻人为中心。` : i % 3 === 1 ? `仍以适合体力的兼职方式从事${job}，不把工作当全部身份。` : `有${job}背景，如今把更多时间给私人生活；不自动改成志愿导师。`) : `职业背景：${job}。`;
  const pair = [interests[i % interests.length], interests[(i * 17 + 13 + Math.floor(i / interests.length)) % interests.length]];
  if (pair[0] === pair[1]) pair[1] = interests[(interests.indexOf(pair[1]) + 1) % interests.length];
  const eventIndex = actionCounts.get(slot.actionId) ?? 0;
  actionCounts.set(slot.actionId, eventIndex + 1);
  const personality = tensions[(i * 11) % tensions.length];
  const life = lives[(i * 19) % lives.length];
  return { ...slot, productionVersion: 3, name: old.get(slot.id).name,
    brief: `${career}私人兴趣为${pair.join('和')}，不必两项都与职业有关。核心性格矛盾：${personality}。具体生活关系或当前事项：${life}。围绕这些要素写一个有日常质感的人；不要复用旧稿，不要补一个犯错后学会放松的励志模板。`,
    niche: { occupation: job, interests: pair, tension: personality, life, voice: voices[(i * 7) % voices.length] },
    eventKey: `${slot.actionId}-${eventIndex + 1}`, event: events[slot.actionId][eventIndex], dynamics: dynamics[(i * 13) % dynamics.length],
  };
});
if (index !== 190 || result.some(s => !s.pilotId && !s.event)) throw Error('Incomplete directions');
const pairs = [];
for (let i=0;i<result.length;i++) for (let j=i+1;j<result.length;j++) {
  const a=result[i].niche,b=result[j].niche;if(!a||!b)continue;
  const shared=['occupation','tension','life','voice'].filter(k=>a[k]===b[k]);
  if (a.interests.some(x=>b.interests.includes(x))) shared.push('interest');
  if(shared.length>=3)pairs.push({ids:[result[i].id,result[j].id],shared});
}
if(pairs.length)throw Error('Insufficient niche separation: '+JSON.stringify(pairs));
writeFileSync(base+'briefs.production.json',JSON.stringify(result,null,2)+'\n');
writeFileSync(base+'direction-audit.json',JSON.stringify({version:3,identityCount:result.length,uniqueNewOccupations:new Set(result.filter(s=>s.niche).map(s=>s.niche.occupation)).size,uniqueEvents:new Set(result.filter(s=>s.eventKey).map(s=>s.eventKey)).size,comparedNewPairs:190*189/2,threeSharedAxisPairs:pairs,inputHash:createHash('sha256').update(JSON.stringify(result)).digest('hex'),limitations:'Direction separation is a planning check, not semantic approval of generated cards or stories.'},null,2)+'\n');
console.log(JSON.stringify({identities:result.length,newDirections:index}));
