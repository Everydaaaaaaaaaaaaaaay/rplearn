/** Four-picture practices contrasting object identity and big/small size. */
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import sharp from '../Backend/node_modules/sharp/lib/index.js';
const root=path.resolve(import.meta.dirname,'..');
const directory=path.join(root,'Backend/config/learning/expansions/2026-10-24');
const batch='b030';
try { await fs.access(path.join(directory,batch+'.source.json')); throw new Error('Preserve the authored batch and use a new ID.'); }
catch(error) { if(error.code!=='ENOENT') throw error; }
const sources=path.join(directory,'size-picture-sources');
const media=path.join(root,'Backend/config/learning/originals/media');
await fs.mkdir(sources,{recursive:true});
const shellComponent='<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 256 256"><rect width="256" height="256" fill="white"/><g stroke="#645947" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"><path d="M128 222 L38 105 Q30 78 56 67 Q71 40 96 53 Q128 24 160 53 Q186 40 201 67 Q226 80 218 105 Z" fill="#edc897"/><path d="M128 217 L57 88 M128 217 L94 67 M128 217 L128 56 M128 217 L163 67 M128 217 L199 88" fill="none"/></g></svg>';
await fs.writeFile(path.join(sources,'component-shell.svg'),shellComponent);
const pairs=[
 [['apple','primary1-apple.svg'],['pear','primary1-pear.svg']],
 [['banana','primary1-banana.svg'],['orange','primary1-orange.svg']],
 [['cat','primary1-animal-cat.svg'],['dog','primary1-animal-dog.svg']],
 [['bird','primary1-animal-bird.svg'],['monkey','primary1-animal-monkey.svg']],
 [['book','primary1-book.svg'],['bag','primary1-schoolbag.svg']],
 [['pencil','primary1-pencil.svg'],['ruler','primary1-ruler.svg']],
 [['tiger','primary1-animal-tiger.svg'],['shell','component-shell.svg']],
];
const assets=[],units=[],previews=[];
for(const pair of pairs){
 const specs=[];
 for(const [noun,file] of pair) for(const [size,side] of [['big',420],['small',210]]){
  const original=await fs.readFile(file==='component-shell.svg'?path.join(sources,file):path.join(root,'Backend/config/learning/image-sources',file),'utf8');
  const box=original.match(/viewBox\s*=\s*"([^"]+)"/)?.[1];
  if(!box) throw new Error('Source viewBox must be explicit');
  const inner=original.replace(/^.*?<svg[^>]*>/s,'').replace(/<\/svg>\s*$/,'');
  const offset=(512-side)/2;
  const svg=`<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512"><rect width="512" height="512" fill="white"/><svg x="${offset}" y="${offset}" width="${side}" height="${side}" viewBox="${box}">${inner}</svg><rect x="12" y="12" width="488" height="488" rx="12" fill="none" stroke="#cad0d6" stroke-width="3"/></svg>`;
  const source=path.join(sources,`${size}-${noun}.svg`);await fs.writeFile(source,svg);
  const bytes=await sharp(Buffer.from(svg)).flatten({background:'#fff'}).removeAlpha().png().toBuffer();
  const sha256=crypto.createHash('sha256').update(bytes).digest('hex'),id='image.'+sha256;
  await fs.writeFile(path.join(media,id+'.png'),bytes);
  const phrase=`a ${size} ${noun}`;specs.push({id,phrase});previews.push({name:`${size} ${noun}`,svg});
  assets.push({id,sha256,byteSize:bytes.length,width:512,height:512,contentType:'image/png',description:`New picture card: ${phrase}, centred within the same visible reference frame as all other cards. No printed words.`,source:`Owned composition ${path.relative(root,source)}; owned component ${file} SHA ${crypto.createHash('sha256').update(original).digest('hex')}. Original viewBox preserved.`,reviewedBy:'Codex vector composition and contact-sheet inspection',reviewedAt:'2026-10-24',reviewNotes:'Object and relative size inspected against its paired card. Big/small are an explicit provisional vocabulary adaptation, not independent primary1 learner calibration.'});
 }
 const number=units.length+1;
 const order=[0,1,2,3].sort((a,b)=>crypto.createHash('sha256').update(`${number}:${a}`).digest('hex').localeCompare(crypto.createHash('sha256').update(`${number}:${b}`).digest('hex')));
 const options=order.map(i=>specs[i]);
 units.push({id:`primary1.size-pictures-${String(number).padStart(3,'0')}`,level:'primary1',title:`大小与物品 ${String(number).padStart(2,'0')}`,family:'word_picture_matching',minutes:6,sourceUnitId:'original.primary1-four-picture-matches',alignmentNote:'Uses the source four-picture matching rules. Big/small plus object names are an explicit provisional vocabulary adaptation. Within each four-card set, two drawings of the same object have visibly different sizes inside identical fixed frames.',materials:[{id:'whole',title:'Four object pictures',text:'Choose the matching picture. Look at the object and its size inside the frame. Each object appears in a big version and a small version.',questions:specs.map(s=>({prompt:`Choose: ${s.phrase}.`,options:['Picture A','Picture B','Picture C','Picture D'],optionImages:options.map(o=>o.id),answer:options.findIndex(o=>o.id===s.id),explanation:`Match ${s.phrase}. The other card of the same object has the opposite size; one card has another object at the requested size, and the final card differs in both object and size. Compare the drawings inside the identical reference frames.`}))}]});
}
await fs.writeFile(path.join(directory,batch+'.source.json'),JSON.stringify({createdAt:new Date().toISOString(),reviewBoundary:'Twenty-eight new size-plus-object picture examples in seven complete four-picture practices. Reuses owned drawing components with source viewBox preserved; new compositions, keys and size contrasts inspected. Counts are picture-word scoring items, not new independent stories or source papers. No independent teacher/learner calibration claimed.',imageAssets:assets,units},null,2)+'\n');
const columns=7,cell=160,height=190;
const contact=`<svg xmlns="http://www.w3.org/2000/svg" width="${columns*cell}" height="${Math.ceil(previews.length/columns)*height}"><rect width="100%" height="100%" fill="#eee"/>${previews.map((p,i)=>`<g transform="translate(${i%columns*cell},${Math.floor(i/columns)*height})"><svg width="160" height="160" viewBox="0 0 512 512">${p.svg.replace(/^.*?<svg[^>]*>/s,'').replace(/<\/svg>\s*$/,'')}</svg><text x="80" y="180" font-family="sans-serif" font-size="13" text-anchor="middle">${p.name}</text></g>`).join('')}</svg>`;
await sharp(Buffer.from(contact)).png().toFile(path.join(root,'build/expansion-primary1-size-contact.png'));
console.log(JSON.stringify({batch,units:units.length,questions:units.length*4,newAssets:assets.length}));
