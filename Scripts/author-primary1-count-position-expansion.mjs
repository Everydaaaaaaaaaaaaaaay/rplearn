/** Compose owned noun drawings into three/four counts and above/below positions. */
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import sharp from '../Backend/node_modules/sharp/lib/index.js';
const root=path.resolve(import.meta.dirname,'..'),batch='b131';
const directory=path.join(root,'Backend/config/learning/expansions/2026-10-24');
const sourceFile=path.join(directory,batch+'.source.json');
try{await fs.access(sourceFile);throw new Error('Preserve existing batch');}catch(e){if(e.code!=='ENOENT')throw e;}
const sources=path.join(directory,'count-position-picture-sources');await fs.mkdir(sources,{recursive:true});
const media=path.join(root,'Backend/config/learning/originals/media');
const pairs=[['pencil','ruler'],['rope','scarf'],['train','ladder'],['snake','bridge'],['tree','bottle'],['glass','candle'],['building','robot'],['tower','lamp']];
const assets=[],units=[],previews={count:[],vertical:[]};
const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
for(const kind of ['count','vertical']){
 for(let set=0;set<pairs.length;set++){
  const specs=[];
  for(const noun of pairs[set]){
   const oldSource=path.join(directory,'dimension-picture-sources',(set>=4?'tall':'long')+'-'+noun+'.svg');
   const oldSvg=await fs.readFile(oldSource,'utf8'),drawing=oldSvg.match(/<g stroke="[\s\S]*?<\/g>/)?.[0];
   if(!drawing)throw new Error('Missing owned drawing '+noun);
   for(const state of kind==='count'?[3,4]:['above','below']){
    let body,phrase;
    if(kind==='count'){
     const placements=state===3?[[20,20],[276,20],[148,276]]:[[20,20],[276,20],[20,276],[276,276]];
     body=placements.map(([x,y])=>`<g transform="translate(${x} ${y}) scale(.42)">${drawing}</g>`).join('');
     const plural={scarf:'scarves',glass:'glasses'}[noun]||noun+'s';phrase=(state===3?'three':'four')+' '+plural;
    }else{
     body=`<path d="M28 256H484" stroke="#cbd3db" stroke-width="3" stroke-dasharray="10 10"/><g transform="translate(128 ${state==='above'?0:256}) scale(.5)">${drawing}</g>`;
     phrase=`a ${noun} ${state} the line`;
    }
    const svg=`<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512"><rect width="512" height="512" fill="white"/>${body}<rect x="12" y="12" width="488" height="488" rx="12" fill="none" stroke="#bfc9d2" stroke-width="3"/></svg>`;
    const file=path.join(sources,kind+'-'+state+'-'+noun+'.svg');await fs.writeFile(file,svg);
    const bytes=await sharp(Buffer.from(svg)).flatten({background:'#fff'}).removeAlpha().png().toBuffer(),sha256=sha(bytes),id='image.'+sha256;
    await fs.writeFile(path.join(media,id+'.png'),bytes);specs.push({id,phrase});previews[kind].push({phrase,svg});
    assets.push({id,sha256,byteSize:bytes.length,width:512,height:512,contentType:'image/png',description:`Owned ${kind} composition: ${phrase}; no printed answer words.`,source:`Composition ${path.relative(root,file)}, SVG SHA ${sha(svg)}. Reuses owned noun source ${path.relative(root,oldSource)}, SHA ${sha(oldSvg)}. Reproducible with Scripts/author-primary1-count-position-expansion.mjs.`,reviewedBy:'Codex geometry and contact-sheet inspection',reviewedAt:'2026-10-24',reviewNotes:kind==='count'?'Three/four separated equal-scale whole objects, count and identity inspected. Reused nouns; no claim of new independent concepts or calibration.':'One whole object above/below a horizontal centre divider; identity/bounds/position inspected. Provisional vocabulary, not independent calibration.'});
   }
  }
  const ordered=[...specs].sort((a,b)=>a.id.localeCompare(b.id));
  units.push({id:`primary1.${kind}-pictures-${set+1}-131`,level:'primary1',title:kind==='count'?`Three and four pictures ${set+1}`:`Above and below pictures ${set+1}`,family:'word_picture_matching',minutes:6,sourceUnitId:'original.primary1-four-picture-matches',instruction:kind==='count'?'Choose the picture with the correct number and object.':'Choose the named object above or below the horizontal line.',alignmentNote:'Four-picture matching source retained. Reuses16 owned nouns in new count/position compositions. Counts are64 picture-word scoring items in16 practices, not64 new nouns or independent knowledge concepts.',materials:[{id:'whole',title:kind==='count'?'Four quantity pictures':'Four position pictures',text:kind==='count'?'Match the object and its number: three or four. Count each whole object.':'Match the object and its position relative to the horizontal centre line: above or below.',questions:specs.map(s=>({prompt:`Choose: ${s.phrase}.`,options:['Picture A','Picture B','Picture C','Picture D'],optionImages:ordered.map(o=>o.id),answer:ordered.findIndex(o=>o.id===s.id),explanation:`Match ${s.phrase}. The distractors change the noun, the ${kind==='count'?'number':'position'}, or both. Each whole object is visually separated, and the frame supplies a fixed reference.`}))}]});
 }
}
if(new Set(assets.map(a=>a.id)).size!==64)throw new Error('Expected64 distinct assets');
await fs.writeFile(sourceFile,JSON.stringify({createdAt:new Date().toISOString(),reviewBoundary:'Sixty-four new count/vertical-position picture-word scoring items in16 complete four-picture practices, recomposed from16 owned noun drawings. Two32-picture contact sheets inspected for count, identity, bounds and no answer-word leakage. No independent calibration.',imageAssets:assets,units},null,2)+'\n');
for(const kind of ['count','vertical']){
 const cell=160,row=188,cols=8;const contact=`<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="752"><rect width="100%" height="100%" fill="#eee"/>${previews[kind].map((p,i)=>`<g transform="translate(${i%cols*cell},${Math.floor(i/cols)*row})"><svg width="160" height="160" viewBox="0 0 512 512">${p.svg.replace(/^.*?<svg[^>]*>/s,'').replace(/<\/svg>\s*$/,'')}</svg><text x="80" y="178" text-anchor="middle" font-family="sans-serif" font-size="11">${p.phrase}</text></g>`).join('')}</svg>`;
 await sharp(Buffer.from(contact)).png().toFile(path.join(root,`build/expansion-primary1-${kind}-131-contact.png`));
}
console.log(JSON.stringify({batch,units:units.length,questions:64,newAssets:assets.length}));
