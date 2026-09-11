import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';

const slots = JSON.parse(readFileSync('Content/NPCLibrary/2026-09-11/slots.json', 'utf8'));
const accepted = JSON.parse(readFileSync('Assets/NPC/Library/v3/catalog.json', 'utf8')).entries.filter(e => e.status === 'accepted');
const scenes = readFileSync('Packages/LingoKit/Sources/HomeFeature/Models/ActivitySceneCatalog.swift', 'utf8')
  + readFileSync('Packages/LingoKit/Sources/HomeFeature/Models/NeighbourhoodSceneActivities.swift', 'utf8');
const actions = [...scenes.matchAll(/\.init\(id: "([a-z-]+)", scene:/g)].map(m => m[1]);
const cities = ['london', 'melbourne', 'newyork', 'capetown', 'singapore', 'dublin', 'edinburgh', 'vancouver', 'auckland', 'nairobi', 'toronto', 'sydney', 'neworleans', 'manchester', 'kingston'];
assert.equal(slots.length, 200);
assert.equal(new Set(slots.map(s => s.id)).size, 200);
assert.equal(new Set(slots.map(s => s.avatarId)).size, 200);
assert.equal(accepted.length, 200);
for (const slot of slots) {
  const avatar = accepted.find(e => e.id === slot.avatarId);
  assert.ok(avatar, slot.id + ': avatar must be accepted');
  assert.equal(slot.avatarKey, avatar.key);
  assert.equal(slot.avatarPath, 'Assets/NPC/Library/v3/' + avatar.image);
  assert.equal(slot.avatarSHA256, avatar.review.sha256);
  assert.equal(createHash('sha256').update(readFileSync(slot.avatarPath)).digest('hex'), slot.avatarSHA256);
  assert.equal(slot.ageMin, avatar.observed.ageMin);
  assert.equal(slot.ageMax, avatar.observed.ageMax);
  assert.ok(slot.age >= slot.ageMin && slot.age <= slot.ageMax);
  assert.equal(slot.gender, avatar.observed.gender);
  assert.equal(slot.appearance, avatar.observed.appearance);
  assert.ok(actions.includes(slot.actionId), 'Unknown app action: ' + slot.actionId);
  assert.ok(cities.includes(slot.regionId));
}
for (const city of cities) for (const action of actions) {
  assert.ok(slots.some(s => s.regionId === city && s.actionId === action), `Missing ${city}/${action}`);
}
console.log(JSON.stringify({ slots: slots.length, avatarHashesVerified: accepted.length, cityActionPairs: cities.length * actions.length, status: 'bindings-only; content and deployment not certified' }));
