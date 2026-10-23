/** Explicitly planned picture-word sets; reuse owned SVG drawing components, preserve old assets. */
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import sharp from '../Backend/node_modules/sharp/lib/index.js';
const root=path.resolve(import.meta.dirname,'..');
const output=path.join(root,'Backend/config/learning/expansions/2026-10-24');
try { await fs.access(path.join(output,'b001.source.json')); throw new Error('b001 is already authored; preserve the frozen source and use a new batch.'); }
catch (error) { if (error.code !== 'ENOENT') throw error; }
const sources=path.join(output,'visual-sources');
const media=path.join(root,'Backend/config/learning/originals/media');
await fs.mkdir(sources,{recursive:true});await fs.mkdir(media,{recursive:true});
const pairs=[
 [['apple','apples','primary1-apple.svg'],['pear','pears','primary1-pear.svg']],
 [['banana','bananas','primary1-banana.svg'],['orange','oranges','primary1-orange.svg']],
 [['cat','cats','primary1-animal-cat.svg'],['dog','dogs','primary1-animal-dog.svg']],
 [['bird','birds','primary1-animal-bird.svg'],['monkey','monkeys','primary1-animal-monkey.svg']],
 [['book','books','primary1-book.svg'],['bag','bags','primary1-schoolbag.svg']],
 [['pencil','pencils','primary1-pencil.svg'],['ruler','rulers','primary1-ruler.svg']],
 [['tiger','tigers','primary1-animal-tiger.svg'],['eye','eyes','primary1-eye.svg']],
];
const counts=['','one','two','three','four'];
const images=[];const units=[];const previews=[];
let unitNumber=0;
for(const pair of pairs)for(const quantities of [[1,2],[3,4]]){
 const specs=[];
 for(const [singular,plural,filename] of pair)for(const count of quantities){
  const original=await fs.readFile(path.join(root,'Backend/config/learning/image-sources',filename),'utf8');
  const inner=original.replace(/^.*?<svg[^>]*>/s,'').replace(/<\/svg>\s*$/,'');
  const positions=count===1?[[102,102,308]]:count===2?[[20,140,230],[262,140,230]]:count===3?[[150,16,210],[22,268,210],[280,268,210]]:[[24,24,210],[278,24,210],[24,278,210],[278,278,210]];
  const svg=`<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512"><rect width="512" height="512" fill="white"/>${positions.map(([x,y,size])=>`<svg x="${x}" y="${y}" width="${size}" height="${size}" viewBox="0 0 512 512">${inner}</svg>`).join('')}</svg>`;
  const name=`${singular}-${count}`;
  const sourcePath=path.join(sources,`${name}.svg`);
  await fs.writeFile(sourcePath,svg);
  const bytes=await sharp(Buffer.from(svg)).flatten({background:'#ffffff'}).removeAlpha().png().toBuffer();
  const hash=crypto.createHash('sha256').update(bytes).digest('hex');const id=`image.${hash}`;
  await fs.writeFile(path.join(media,id+'.png'),bytes);
  const phrase=counts[count]+' '+(count===1?singular:plural);
  images.push({id,sha256:hash,byteSize:bytes.length,width:512,height:512,contentType:'image/png',description:`Original picture card: ${phrase}. Separate complete objects on white; no written words or numbers.`,source:`Owned vector ${path.relative(root,sourcePath)}; component ${filename} reused with SHA ${crypto.createHash('sha256').update(original).digest('hex')}.`,reviewedBy:'Codex vector composition and image inspection',reviewedAt:'2026-10-24',reviewNotes:'New quantity-and-noun picture set. Reuses owned editable drawings without changing old files. No independent teacher/learner calibration claimed.'});
  specs.push({id,phrase});previews.push({name,svg});
 }
 unitNumber++;
 const title=`看图识词 ${String(unitNumber).padStart(2,'0')}`;
 const order=unitNumber%2?[2,0,3,1]:[1,3,0,2];
 const ordered=order.map(i=>specs[i]);
 units.push({id:`primary1.picture-words-${String(unitNumber).padStart(3,'0')}`,level:'primary1',title,family:'word_picture_matching',minutes:6,sourceUnitId:'original.primary1-four-picture-matches',materials:[{id:'whole',title:'Four picture cards',text:'Choose the picture that matches each word group. There are four picture cards. Look at both the object and how many there are.',questions:specs.map(s=>({prompt:`Choose: ${s.phrase}.`,options:['Picture A','Picture B','Picture C','Picture D'],optionImages:ordered.map(o=>o.id),answer:ordered.findIndex(o=>o.id===s.id),explanation:`The phrase is "${s.phrase}". Match both the named object and its exact quantity. The other three cards differ in the object, the quantity, or both; none has the same combination.`}))}]});
}
await fs.writeFile(path.join(output,'b001.source.json'),JSON.stringify({createdAt:new Date().toISOString(),reviewBoundary:'2026-10-24新原创图词组合；沿用有来源的四图匹配任务，数量词加名词是本批明确适配，不声称原卷同配置、独立教师审核或一年级实测等值。逐卡核对对象/数量和选项键。',imageAssets:images,units},null,2)+'\n');
const cell=150,columns=8;
const contact=`<svg xmlns="http://www.w3.org/2000/svg" width="${columns*cell}" height="${Math.ceil(previews.length/columns)*170}" viewBox="0 0 ${columns*cell} ${Math.ceil(previews.length/columns)*170}"><rect width="100%" height="100%" fill="#eee"/>${previews.map((p,i)=>`<g transform="translate(${i%columns*cell},${Math.floor(i/columns)*170})"><svg width="150" height="145" viewBox="0 0 512 512">${p.svg.replace(/^.*?<svg[^>]*>/s,'').replace(/<\/svg>\s*$/,'')}</svg><text x="75" y="162" text-anchor="middle" font-family="sans-serif" font-size="13">${p.name}</text></g>`).join('')}</svg>`;
await sharp(Buffer.from(contact)).png().toFile(path.join(root,'build/expansion-primary1-vector-contact.png'));
console.log(JSON.stringify({units:units.length,questions:units.length*4,newImageAssets:images.length,distinctNouns:pairs.length*2,quantities:[1,2,3,4]}));
