// Offline conversion of SHA-bound, owned SVG inputs; never fetches remote assets.
const fs = require('node:fs/promises');
const sharp = require(process.argv[2]);
(async () => {
  const source = await fs.readFile(process.argv[3]);
  const resized = await sharp(source, { limitInputPixels: 8_000_000 }).resize({ width: 1024, height: 1024, fit: 'inside', withoutEnlargement: true }).ensureAlpha().png().toBuffer();
  const meta = await sharp(resized).metadata();
  await sharp(resized).extend({ top: 0, left: 0, bottom: Math.max(0, 128 - meta.height), right: Math.max(0, 128 - meta.width), background: '#ffffff' }).png().toFile(process.argv[4]);
})().catch(e => { console.error(e.message); process.exitCode = 1; });
