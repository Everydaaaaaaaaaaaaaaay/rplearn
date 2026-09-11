// Bind explicit editorial decisions to exact content; never refresh stale hashes.
import {readFileSync,writeFileSync,existsSync,openSync,closeSync,unlinkSync} from 'node:fs';
import {join} from 'node:path';import {createHash} from 'node:crypto';
const[out,source]=process.argv.slice(2),dir=join(out,'production-v3');
const hash=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
const read=f=>JSON.parse(readFileSync(join(dir,f),'utf8')),decisions=JSON.parse(readFileSync(source,'utf8'));
const lock=join(out,'running.lock'),fd=openSync(lock,'wx');writeFileSync(fd,String(process.pid));
try{
 for(const mode of ['cards','stories'])for(const r of decisions[mode]??[]){
  if(r.status!=='distinct'||r.reasonZh?.length<40)throw Error('Explicit reason/status required');
  for(const side of ['left','right'])if(!/^library-\d{3}$/.test(r[side])||hash(read(r[side]+(mode==='cards'?'.card.json':'.json')))!==r[side+'Hash'])throw Error('Stale editorial evidence '+mode+'/'+r[side]);
 }
 for(const mode of ['cards','stories']){
  const f='manual-'+mode+'-adjudications.json',old=existsSync(join(dir,f))?read(f):[];
  for(const r of decisions[mode]??[])if(!old.some(x=>x.left===r.left&&x.right===r.right&&x.leftHash===r.leftHash&&x.rightHash===r.rightHash))old.push(r);
  writeFileSync(join(dir,f),JSON.stringify(old,null,2)+'\n');
 }
 console.log('Exact-content editorial decisions recorded');
}finally{closeSync(fd);unlinkSync(lock);}
