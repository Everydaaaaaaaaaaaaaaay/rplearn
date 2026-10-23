/** New explicit picture cards: six simple shapes, four basic colours, six four-card practices. */
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import sharp from '../Backend/node_modules/sharp/lib/index.js';
const root = path.resolve(import.meta.dirname, '..');
const directory = path.join(root, 'Backend/config/learning/expansions/2026-10-24');
const batch = 'b011';
try { await fs.access(path.join(directory, batch + '.source.json')); throw new Error('Preserve an existing source; author a new batch.'); }
catch (error) { if (error.code !== 'ENOENT') throw error; }
const sourceDirectory = path.join(directory, 'color-shape-sources');
const media = path.join(root, 'Backend/config/learning/originals/media');
await fs.mkdir(sourceDirectory, { recursive: true });
const colors = [['red', '#dc3838'], ['blue', '#2456c7'], ['green', '#248744'], ['yellow', '#f4cc30']];
const shapes = [
  ['circle', '<circle cx="256" cy="256" r="158"/>'],
  ['square', '<rect x="98" y="98" width="316" height="316"/>'],
  ['triangle', '<path d="M256 78 L436 414 H76 Z"/>'],
  ['star', '<path d="M256 62 L302 199 L446 199 L329 284 L374 422 L256 337 L138 422 L183 284 L66 199 L210 199 Z"/>'],
  ['heart', '<path d="M256 427 C220 397 68 285 68 178 C68 81 190 56 256 148 C322 56 444 81 444 178 C444 285 292 397 256 427 Z"/>'],
  ['rectangle', '<rect x="64" y="155" width="384" height="202"/>'],
];
const assets = [], specs = new Map(), previews = [];
for (const [name, drawing] of shapes) for (const [color, fill] of colors) {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512"><rect width="512" height="512" fill="white"/><g fill="${fill}" stroke="#263444" stroke-width="7" stroke-linejoin="round">${drawing}</g></svg>`;
  const source = path.join(sourceDirectory, `${color}-${name}.svg`);
  await fs.writeFile(source, svg);
  const bytes = await sharp(Buffer.from(svg)).flatten({ background: '#fff' }).removeAlpha().png().toBuffer();
  const sha256 = crypto.createHash('sha256').update(bytes).digest('hex');
  const id = 'image.' + sha256;
  await fs.writeFile(path.join(media, id + '.png'), bytes);
  const phrase = `a ${color} ${name}`;
  specs.set(`${color}-${name}`, { id, phrase });
  previews.push({ label: `${color} ${name}`, svg });
  assets.push({ id, sha256, byteSize: bytes.length, width: 512, height: 512, contentType: 'image/png', description: `Original picture card showing ${phrase}, one centered shape on white without printed text.`, source: `New owned vector ${path.relative(root, source)}.`, reviewedBy: 'Codex vector author and contact-sheet inspection', reviewedAt: '2026-10-24', reviewNotes: 'Single clear outline; shape and basic colour both distinguish the four candidates. Provisional primary1 vocabulary extension, not independent learner calibration.' });
}
const units = [];
for (const pair of [['circle', 'square'], ['triangle', 'star'], ['heart', 'rectangle']]) {
  for (const names of [['red', 'blue'], ['green', 'yellow']]) {
    const candidates = pair.flatMap(shape => names.map(color => specs.get(`${color}-${shape}`)));
    const number = units.length + 1;
    const order = number % 2 ? [3, 1, 0, 2] : [2, 0, 3, 1];
    const ordered = order.map(i => candidates[i]);
    units.push({ id: `primary1.color-shapes-${String(number).padStart(3, '0')}`, level: 'primary1', title: `颜色与形状 ${String(number).padStart(2, '0')}`, family: 'word_picture_matching', minutes: 6, sourceUnitId: 'original.primary1-four-picture-matches', alignmentNote: 'Uses the source four-picture matching task only. Six shape nouns with four colour adjectives are a declared provisional vocabulary extension; no claim of original-paper vocabulary equivalence.', materials: [{ id: 'whole', title: 'Four coloured shapes', text: 'Choose the picture that matches each word group. Look at both the colour and the shape.', questions: candidates.map(candidate => ({ prompt: `Choose: ${candidate.phrase}.`, options: ['Picture A', 'Picture B', 'Picture C', 'Picture D'], optionImages: ordered.map(o => o.id), answer: ordered.findIndex(o => o.id === candidate.id), explanation: `Choose the card showing ${candidate.phrase}. One other card has the same shape in a different colour, one has the same colour but a different shape, and one differs in both. Only the keyed card matches both words.` })) }] });
  }
}
await fs.writeFile(path.join(directory, batch + '.source.json'), JSON.stringify({ createdAt: new Date().toISOString(), reviewBoundary: 'New owned simple shape drawings and 24 colour-plus-shape examples in six complete four-picture practices. Source supplies task rules; vocabulary expansion is explicit and provisional. Same-author visual and option-key review, not independent teacher or student validation.', imageAssets: assets, units }, null, 2) + '\n');
const cell = 180, columns = 6;
const contact = `<svg xmlns="http://www.w3.org/2000/svg" width="${columns * cell}" height="${Math.ceil(previews.length / columns) * 205}"><rect width="100%" height="100%" fill="#eee"/>${previews.map((p, i) => `<g transform="translate(${i % columns * cell},${Math.floor(i / columns) * 205})"><svg width="180" height="180" viewBox="0 0 512 512">${p.svg.replace(/^.*?<svg[^>]*>/s, '').replace(/<\/svg>\s*$/, '')}</svg><text x="90" y="198" text-anchor="middle" font-family="sans-serif" font-size="14">${p.label}</text></g>`).join('')}</svg>`;
await sharp(Buffer.from(contact)).png().toFile(path.join(root, 'build/expansion-primary1-color-shapes-contact.png'));
console.log(JSON.stringify({ batch, units: units.length, questions: units.length * 4, newAssets: assets.length }));
