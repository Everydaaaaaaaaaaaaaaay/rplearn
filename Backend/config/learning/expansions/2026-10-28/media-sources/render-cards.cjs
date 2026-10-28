// Deterministic renderer for explicitly authored, owned four-card SVG worksheets.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
exports.render=async({base,batch,icons,sets})=>{
 if(!/^\d{3}$/.test(batch)||fs.existsSync(path.join(base,'../sources',`primary1-visual-${batch}.json`)))throw Error('Invalid or already frozen authoring batch');
 const sharp=require(process.argv[2]||'sharp'),media=path.resolve(base,'../../../originals/media'),rows=[];
 for(const[name,items]of sets){
  if(!/^[a-z][a-z0-9-]+$/.test(name)||items.length!==4||items.some(k=>!icons[k]||/<(?:image|script|foreignObject)\b/i.test(icons[k])))throw Error('Explicit owned four-card drawings required');
  let cards='';for(let i=0;i<4;i++){const x=12+i%2*378,y=12+Math.floor(i/2)*250;cards+=`<g transform="translate(${x} ${y})"><rect width="366" height="238" rx="16" fill="white" stroke="#c5cfd9" stroke-width="2"/><text x="22" y="48" font-family="Arial,sans-serif" font-size="36" font-weight="bold" fill="#253b50">${'ABCD'[i]}</text><g transform="translate(100 32) scale(1.65)" stroke="#344554" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${icons[items[i]]}</g></g>`;}
  const svg=`<svg xmlns="http://www.w3.org/2000/svg" width="768" height="512"><rect width="768" height="512" fill="#f6f8fb"/>${cards}</svg>`,file=`primary1-${name}-${batch}.svg`;
  fs.writeFileSync(path.join(base,file),svg);const bytes=await sharp(Buffer.from(svg)).ensureAlpha().png({palette:false}).toBuffer(),sha=crypto.createHash('sha256').update(bytes).digest('hex'),id='image.'+sha;
  fs.writeFileSync(path.join(media,id+'.png'),bytes);rows.push({name,items,source:file,id,sha256:sha,byteSize:bytes.length,width:768,height:512,contentType:'image/png'});
 }
 fs.writeFileSync(path.join(base,`primary1-visual-${batch}.assets.json`),JSON.stringify(rows,null,2)+'\n');console.log(rows.map(x=>({name:x.name,bytes:x.byteSize})));
};
