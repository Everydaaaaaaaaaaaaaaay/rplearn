// Read-only content verification; no credentials, model calls or database needed.
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { validate } from './npc-content.mjs';
const root = fileURLToPath(new URL('../../', import.meta.url));
const folder = join(root, 'Content/NPCPilot/2026-09-11');
const seeds = JSON.parse(readFileSync(join(folder, 'briefs.json')));
const catalog = JSON.parse(readFileSync(join(root, 'Assets/NPC/Library/v3/catalog.json'))).entries;
let paths = 0, bytes = 0;
const endings = new Set(), identities = new Set(), avatars = new Set();
for (const seed of seeds) {
  const raw = readFileSync(join(folder, seed.id + '.json')); bytes += raw.length;
  const value = JSON.parse(raw), issues = validate(value, seed);
  if (issues.length) throw Error(seed.id + ': ' + issues.join('; '));
  const asset = catalog.find(a => a.id === seed.avatarId && a.status === 'accepted');
  if (!asset || seed.age < asset.observed.ageMin || seed.age > asset.observed.ageMax || seed.gender !== asset.observed.gender) throw Error('Avatar compatibility: ' + seed.id);
  if (createHash('sha256').update(readFileSync(join(root, seed.avatarPath))).digest('hex') !== seed.avatarSHA256 || asset.review.sha256 !== seed.avatarSHA256) throw Error('Changed avatar');
  identities.add(value.card.name); avatars.add(seed.avatarId);
  const nodes = new Map(value.story.nodes.map(n => [n.id, n]));
  for (const id of ['aa', 'ab', 'ba', 'bb']) {
    const count = ['start', id[0], id].reduce((n, k) => n + nodes.get(k).beats.length, 0);
    if (count < 12 || count > 18) throw Error('Incomplete path');
    endings.add(JSON.stringify(nodes.get(id).beats)); paths++;
  }
}
if (seeds.length !== 10 || identities.size !== 10 || avatars.size !== 10 || endings.size !== 40) throw Error('Repeated identity/avatar/ending');
console.log(JSON.stringify({ characters: 10, paths, distinctEndings: endings.size, textBytes: bytes, avatarHashes: 'verified' }));
