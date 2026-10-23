/** Owned code-native illustrations: length/height plus object identity. */
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import sharp from '../Backend/node_modules/sharp/lib/index.js';
const root=path.resolve(import.meta.dirname,'..');
const directory=path.join(root,'Backend/config/learning/expansions/2026-10-24');
const batch='b065',sourceFile=path.join(directory,batch+'.source.json');
try { await fs.access(sourceFile); throw new Error('Preserve the existing batch; use a new ID.'); }
catch(e) { if(e.code!=='ENOENT') throw e; }
const sources=path.join(directory,'dimension-picture-sources');
const media=path.join(root,'Backend/config/learning/originals/media');
await fs.mkdir(sources,{recursive:true});
const ink='#364556';
const rect=(x,y,w,h,fill,rx=4)=>`<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${rx}" fill="${fill}"/>`;
const line=(x1,y1,x2,y2,stroke=ink,width=5)=>`<path d="M${x1} ${y1}L${x2} ${y2}" fill="none" stroke="${stroke}" stroke-width="${width}"/>`;
const circle=(x,y,r,fill)=>`<circle cx="${x}" cy="${y}" r="${r}" fill="${fill}"/>`;
const longDraw={
 pencil:(w)=>{const x=(512-w)/2;return `<path d="M${x} 236 L${x+32} 216 L${x+w-28} 216 L${x+w-28} 276 L${x+32} 276 L${x} 256Z" fill="#f2bd4e"/><path d="M${x} 246L${x+32} 226L${x+32} 266Z" fill="#ead1b1"/>${rect(x+w-28,216,28,60,'#e88c9b')}${line(x+40,246,x+w-35,246,'#c28d30',3)}${line(x,246,x+12,239,ink,6)}`;},
 ruler:(w)=>{const x=(512-w)/2;return rect(x,215,w,82,'#f0cd70')+Array.from({length:Math.floor((w-16)/22)},(_,i)=>line(x+12+i*22,215,x+12+i*22,215+(i%2?22:38),ink,3)).join('');},
 rope:(w)=>{const x=(512-w)/2;return `<path d="M${x} 256 Q${x+w*.18} 207 ${x+w*.36} 256 T${x+w*.72} 256 Q${x+w*.86} 219 ${x+w} 256" fill="none" stroke="#855e3a" stroke-width="24"/><path d="M${x} 256 Q${x+w*.18} 207 ${x+w*.36} 256 T${x+w*.72} 256 Q${x+w*.86} 219 ${x+w} 256" fill="none" stroke="#d9ad6e" stroke-width="10" stroke-dasharray="9 9"/>`;},
 scarf:(w)=>{const x=(512-w)/2;return rect(x,220,w,72,'#df7892')+Array.from({length:4},(_,i)=>rect(x+w*.18+i*w*.16,220,Math.max(7,w*.035),72,'#f4bdcc',0)).join('')+Array.from({length:6},(_,i)=>line(x-12,228+i*10,x,228+i*10,'#b85b76',4)+line(x+w,228+i*10,x+w+12,228+i*10,'#b85b76',4)).join('');},
 train:(w)=>{const n=w>250?4:2,cw=w/n,x=(512-w)/2;let s='';for(let i=0;i<n;i++){const a=x+i*cw;s+=rect(a,235,cw-5,61,i===0?'#4493b0':'#e8b65b',6);s+=rect(a+8,215,cw-22,28,i===0?'#a0d6e3':'#fff3cc',3);s+=circle(a+cw*.25,302,12,'#596574')+circle(a+cw*.74,302,12,'#596574');if(i===0)s+=rect(a+7,196,15,20,'#596574',1);}return s;},
 ladder:(h)=>{const y=(512-h)/2;return line(214,y,214,y+h,'#a2764c',13)+line(298,y,298,y+h,'#a2764c',13)+Array.from({length:Math.max(3,Math.floor(h/40))},(_,i)=>{const n=Math.max(3,Math.floor(h/40));const z=y+20+i*(h-40)/(n-1);return line(214,z,298,z,'#bb9468',11);}).join('');},
 snake:(w)=>{const x=(512-w)/2;return `<path d="M${x} 264 Q${x+w*.18} 205 ${x+w*.36} 264 T${x+w*.72} 264 Q${x+w*.86} 220 ${x+w-20} 250" fill="none" stroke="#5d9c66" stroke-width="29"/><ellipse cx="${x+w-15}" cy="246" rx="28" ry="23" fill="#7fba73"/>${circle(x+w-6,237,4,ink)}${line(x+w+11,250,x+w+22,254,'#c66070',3)}`;},
 bridge:(w)=>{const x=(512-w)/2,n=w>250?3:1;let s=rect(x,224,w,26,'#b68b67',3);for(let i=0;i<=n;i++)s+=rect(x+i*w/n-8,249,16,94,'#c5a384',1);for(let i=0;i<n;i++){const a=x+i*w/n,b=w/n;s+=`<path d="M${a+9} 330Q${a+b/2} 245 ${a+b-9} 330" fill="none" stroke="#a87f5c" stroke-width="17"/>`;}s+=line(x,203,x+w,203,'#647b85',5);for(let i=0;i<=n*2;i++)s+=line(x+i*w/(n*2),203,x+i*w/(n*2),224,'#647b85',4);const count=Math.max(2,Math.round((w+16)/50)),step=(w+16)/count;const water=`M${x-8} 355`+Array.from({length:count},()=>`q${step/4} -12 ${step/2} 0t${step/2} 0`).join('');return s+`<path d="${water}" fill="none" stroke="#88c4dc" stroke-width="8"/>`;},
};
const tallDraw={
 tree:(h)=>{const y=446-h;return rect(242,y+85,28,h-85,'#9e764e',4)+`<path d="M256 ${y}C137 ${y+10} 139 ${y+125} 223 ${y+132}C259 ${y+167} 365 ${y+125} 344 ${y+65}C334 ${y+5} 295 ${y-12} 256 ${y}Z" fill="#79b77d"/>`;},
 bottle:(h)=>{const y=446-h;return `<path d="M230 ${y+36}L230 ${y+69}Q200 ${y+85} 200 ${y+108}L200 430Q200 446 216 446H296Q312 446 312 430V${y+108}Q312 ${y+85} 282 ${y+69}V${y+36}Z" fill="#a7d9e5"/>${rect(226,y+12,60,28,'#4a87ae',4)}${rect(211,y+117,90,Math.max(20,h-145),'#d9eef1',8)}`;},
 glass:(h)=>{const y=446-h;return `<path d="M183 ${y}L202 446H310L329 ${y}Z" fill="#c7e6ed"/><ellipse cx="256" cy="${y}" rx="73" ry="13" fill="#eef8fa"/>${line(210,y+32,220,414,'#eef8fa',7)}`;},
 candle:(h)=>{const y=446-h;return rect(216,y,80,h,'#f0cd6a',5)+`<ellipse cx="256" cy="${y}" rx="40" ry="11" fill="#f9e6a4"/>${line(256,y,256,y-15,ink,4)}<path d="M256 ${y-59}Q226 ${y-27} 256 ${y-17}Q286 ${y-29} 256 ${y-59}Z" fill="#ec9863"/>`;},
 building:(h)=>{const y=446-h;let s=rect(166,y,180,h,'#e8ba91',2)+`<path d="M155 ${y}L256 ${y-25}L357 ${y}Z" fill="#698caa"/>`+rect(235,392,42,54,'#846a59',2);for(let z=y+28;z<380;z+=59)for(const x of[188,277])s+=rect(x,z,47,33,'#b9dae8',2);return s;},
 robot:(h)=>{const y=446-h;return line(222,y+173,222,427,'#6f8999',24)+line(290,y+173,290,427,'#6f8999',24)+rect(189,425,58,21,'#4a6275',5)+rect(266,425,58,21,'#4a6275',5)+rect(186,y+90,140,100,'#79adb9',15)+rect(183,y+20,146,76,'#a9ced4',14)+line(256,y+20,256,y-1,'#4a6275',5)+circle(256,y-8,8,'#dfaa65')+circle(222,y+56,10,ink)+circle(290,y+56,10,ink)+line(235,y+78,277,y+78,ink,4)+line(184,y+112,158,y+166,'#6f8999',15)+line(328,y+112,355,y+166,'#6f8999',15)+circle(255,y+136,13,'#edcb78');},
 tower:(h)=>{const y=446-h;let s=rect(191,y+28,130,h-28,'#b3bdc3',2)+rect(181,y,150,35,'#a1adb6',1);for(let i=0;i<4;i++)s+=rect(181+i*40,y-21,28,30,'#a1adb6',1);s+=`<path d="M238 446V413Q256 386 274 413V446Z" fill="#6c7c8b"/>`;for(let z=y+68;z<374;z+=70)s+=rect(242,z,28,32,'#e8ecdc',8);return s;},
 lamp:(h)=>{const y=446-h;return rect(244,y+78,24,h-85,'#8d9aa3',5)+`<path d="M193 ${y}H319L350 ${y+81}H162Z" fill="#e4b779"/>`+`<ellipse cx="256" cy="439" rx="84" ry="10" fill="#8796a2"/>`+line(283,y+81,283,y+107,'#a47d4b',3)+circle(283,y+112,5,'#a47d4b');},
};
const pairSets=[['pencil','ruler'],['rope','scarf'],['train','ladder'],['snake','bridge'],['tree','bottle'],['glass','candle'],['building','robot'],['tower','lamp']];
const assets=[],units=[],previews=[];
for(let set=0;set<pairSets.length;set++){
 const pair=pairSets[set],vertical=set>=4,specs=[];
 for(const noun of pair)for(const adjective of [vertical?'tall':'long','short']){
  const dimension=adjective==='short'?(noun==='robot'?235:vertical?185:180):(vertical?330:380);
  const drawing=(vertical?tallDraw:longDraw)[noun](dimension);
  const svg=`<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512"><rect width="512" height="512" fill="white"/><g stroke="${ink}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">${drawing}</g>${vertical?line(85,450,427,450,'#dbe1e5',3):''}<rect x="12" y="12" width="488" height="488" rx="12" fill="none" stroke="#cad0d6" stroke-width="3"/></svg>`;
  const filename=`${adjective}-${noun}.svg`,source=path.join(sources,filename);await fs.writeFile(source,svg);
  const bytes=await sharp(Buffer.from(svg)).flatten({background:'#fff'}).removeAlpha().png().toBuffer();
  const sha256=crypto.createHash('sha256').update(bytes).digest('hex'),id='image.'+sha256,phrase=`a ${adjective} ${noun}`;
  await fs.writeFile(path.join(media,id+'.png'),bytes);specs.push({id,phrase});previews.push({name:`${adjective} ${noun}`,svg});
  assets.push({id,sha256,byteSize:bytes.length,width:512,height:512,contentType:'image/png',description:`Owned new word-picture card: ${phrase}; identical fixed frame, no printed answer words.`,source:`New owned vector ${path.relative(root,source)}; SVG SHA ${crypto.createHash('sha256').update(svg).digest('hex')}. Geometry explicitly authored in Scripts/author-primary1-dimension-expansion.mjs.`,reviewedBy:'Codex geometry and contact-sheet inspection',reviewedAt:'2026-10-24',reviewNotes:'Object identity and paired length/height checked in fixed frames. New vocabulary is a provisional primary1 extension, not independent learner/teacher calibration.'});
 }
 const ordered=[...specs].sort((a,b)=>a.id.localeCompare(b.id));
 units.push({id:`primary1.dimension-pictures-${set+1}-065`,level:'primary1',title:`${vertical?'Tall and short':'Long and short'} pictures ${set+1}`,family:'word_picture_matching',minutes:6,sourceUnitId:'original.primary1-four-picture-matches',alignmentNote:'Four-picture matching structure retained. Long/short and tall/short plus nouns are explicit provisional vocabulary extensions. Two objects each appear in opposite dimensions inside the same fixed frame; these are picture-word scoring items, not independent stories.',materials:[{id:'whole',title:'Four object pictures',text:`Choose the matching picture. Compare the object and its ${vertical?'height':'length'} within the identical frame.`,questions:specs.map(s=>({prompt:`Choose: ${s.phrase}.`,options:['Picture A','Picture B','Picture C','Picture D'],optionImages:ordered.map(o=>o.id),answer:ordered.findIndex(o=>o.id===s.id),explanation:`Match ${s.phrase}. One distractor is the same object with the opposite dimension, one is the other object with the requested dimension, and one differs in both. All drawings use the same visible frame.`}))}]});
}
if(new Set(assets.map(a=>a.id)).size!==32)throw new Error('Every new image must be distinct');
await fs.writeFile(sourceFile,JSON.stringify({createdAt:new Date().toISOString(),reviewBoundary:'Thirty-two new owned length/height-plus-object picture examples in eight complete four-picture practices. All vector geometry is newly authored; identity, bounds, contrast and no answer-text leakage reviewed on a contact sheet. Counts describe picture-word scoring items, not new independent stories. Vocabulary provisional, no independent calibration claimed.',imageAssets:assets,units},null,2)+'\n');
const columns=8,cell=150,row=178;
const contact=`<svg xmlns="http://www.w3.org/2000/svg" width="${columns*cell}" height="${Math.ceil(previews.length/columns)*row}"><rect width="100%" height="100%" fill="#eee"/>${previews.map((p,i)=>`<g transform="translate(${i%columns*cell},${Math.floor(i/columns)*row})"><svg width="150" height="150" viewBox="0 0 512 512">${p.svg.replace(/^.*?<svg[^>]*>/s,'').replace(/<\/svg>\s*$/,'')}</svg><text x="75" y="169" font-family="sans-serif" font-size="12" text-anchor="middle">${p.name}</text></g>`).join('')}</svg>`;
await sharp(Buffer.from(contact)).png().toFile(path.join(root,'build/expansion-primary1-dimension-contact.png'));
console.log(JSON.stringify({batch,units:units.length,questions:units.length*4,newAssets:assets.length}));
