/** Recompose owned noun illustrations for one/two quantity matching. */
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import sharp from '../Backend/node_modules/sharp/lib/index.js';
const root=path.resolve(import.meta.dirname,'..');
const directory=path.join(root,'Backend/config/learning/expansions/2026-10-24');
const batch='b110',sourceFile=path.join(directory,batch+'.source.json');
try{await fs.access(sourceFile);throw new Error('Preserve existing source; choose a fresh batch');}catch(e){if(e.code!=='ENOENT')throw e;}
const sources=path.join(directory,'quantity-picture-sources');
const media=path.join(root,'Backend/config/learning/originals/media');
await fs.mkdir(sources,{recursive:true});
const pairs=[['pencil','ruler'],['rope','scarf'],['train','ladder'],['snake','bridge'],['tree','bottle'],['glass','candle'],['building','robot'],['tower','lamp']];
const assets=[],units=[],previews=[];
for(let set=0;set<pairs.length;set++){
 const specs=[];
 for(const noun of pairs[set]){
  const dimension=set>=4?'tall':'long';
  const oldSource=path.join(directory,'dimension-picture-sources',dimension+'-'+noun+'.svg');
  const oldSvg=await fs.readFile(oldSource,'utf8');
  const drawing=oldSvg.match(/<g stroke="[\s\S]*?<\/g>/)?.[0];
  if(!drawing)throw new Error('Missing owned drawing: '+noun);
  for(const count of [1,2]){
   const plural={scarf:'scarves',glass:'glasses'}[noun]||noun+'s';
   const placements=count===1?[148]:[20,276];
   const svg=`<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512"><rect width="512" height="512" fill="white"/>${placements.map(tx=>`<g transform="translate(${tx} 148) scale(.42)">${drawing}</g>`).join('')}<rect x="12" y="12" width="488" height="488" rx="12" fill="none" stroke="#bfc9d2" stroke-width="3"/></svg>`;
   const file=path.join(sources,count+'-'+noun+'.svg');await fs.writeFile(file,svg);
   const bytes=await sharp(Buffer.from(svg)).flatten({background:'#fff'}).removeAlpha().png().toBuffer();
   const sha256=crypto.createHash('sha256').update(bytes).digest('hex'),id='image.'+sha256,phrase=count===1?`one ${noun}`:`two ${plural}`;
   await fs.writeFile(path.join(media,id+'.png'),bytes);
   specs.push({id,phrase});previews.push({name:phrase,svg});
   assets.push({id,sha256,byteSize:bytes.length,width:512,height:512,contentType:'image/png',description:`Owned quantity composition: ${phrase}; separated, equal-scale objects on white, without printed answer words.`,source:`New composition ${path.relative(root,file)}, SVG SHA ${crypto.createHash('sha256').update(svg).digest('hex')}; noun drawing reused from ${path.relative(root,oldSource)}, SHA ${crypto.createHash('sha256').update(oldSvg).digest('hex')}. Composition authored in Scripts/author-primary1-quantity-expansion.mjs.`,reviewedBy:'Codex quantity/identity geometry and contact-sheet inspection',reviewedAt:'2026-10-24',reviewNotes:'One/two count and noun identity checked. Reuses16 owned noun drawings in32 new quantity compositions; provisional vocabulary and number matching, not independent calibration.'});
  }
 }
 const ordered=[...specs].sort((a,b)=>a.id.localeCompare(b.id));
 units.push({id:`primary1.quantity-pictures-${set+1}-110`,level:'primary1',title:`One and two pictures ${set+1}`,family:'word_picture_matching',minutes:6,sourceUnitId:'original.primary1-four-picture-matches',alignmentNote:'Four-picture word matching retained. One/two-plus-noun is a provisional extension. Each pair of owned nouns is composed in counts1 and2. Counts are32 quantity-picture items, not32 independent nouns or stories.',materials:[{id:'whole',title:'Four quantity pictures',instruction:'Choose the picture with the correct object and number.',text:'Look at all four pictures. Match both the object name and the number: one or two.',questions:specs.map(s=>({prompt:`Choose: ${s.phrase}.`,options:['Picture A','Picture B','Picture C','Picture D'],optionImages:ordered.map(o=>o.id),answer:ordered.findIndex(o=>o.id===s.id),explanation:`Match ${s.phrase}. One distractor has the same noun but the other count; one has the other noun at the requested count; one differs in both. Equal-scale separated objects make the quantity visible.`}))}]});
}
if(new Set(assets.map(a=>a.id)).size!==32)throw new Error('Images must be distinct');
await fs.writeFile(sourceFile,JSON.stringify({createdAt:new Date().toISOString(),reviewBoundary:'Thirty-two new one/two-plus-noun picture compositions in eight complete four-picture practices. Reuses16 owned noun illustrations from the earlier dimension batch, with separate equal-scale objects. Contact-sheet identity/bounds/count/no-answer-leakage review only; no independent calibration.',imageAssets:assets,units},null,2)+'\n');
const cols=8,cell=160,row=188;
const contact=`<svg xmlns="http://www.w3.org/2000/svg" width="${cols*cell}" height="${Math.ceil(previews.length/cols)*row}"><rect width="100%" height="100%" fill="#eee"/>${previews.map((p,i)=>`<g transform="translate(${i%cols*cell},${Math.floor(i/cols)*row})"><svg width="160" height="160" viewBox="0 0 512 512">${p.svg.replace(/^.*?<svg[^>]*>/s,'').replace(/<\/svg>\s*$/,'')}</svg><text x="80" y="178" text-anchor="middle" font-family="sans-serif" font-size="13">${p.name}</text></g>`).join('')}</svg>`;
await sharp(Buffer.from(contact)).png().toFile(path.join(root,'build/expansion-primary1-quantity-contact.png'));
console.log(JSON.stringify({batch,units:units.length,questions:32,newAssets:assets.length}));
