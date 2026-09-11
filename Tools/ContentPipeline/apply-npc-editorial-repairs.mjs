// Apply reviewed, bounded editorial corrections without regenerating settled content.
import {readFileSync,writeFileSync,openSync,closeSync,unlinkSync,existsSync} from 'node:fs';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
const [output,input]=process.argv.slice(2);
if(!output||!input)throw Error('private-output editorial-story-repairs.json');
const dir=join(output,'production-v3'),hash=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
const patches=JSON.parse(readFileSync(input));
const lock=join(output,'running.lock'),fd=openSync(lock,'wx');writeFileSync(fd,String(process.pid));
try{
 const staged=patches.map(p=>{
  if(!/^library-\d{3}$/.test(p.id)||!p.reasonZh||!p.expectedContent||!p.content)throw Error('Invalid editorial patch');
  const path=join(dir,p.id+'.json'),current=JSON.parse(readFileSync(path));
  if(hash(current)===hash(p.content))return null;
  if(hash(current)!==hash(p.expectedContent))throw Error('Stale editorial patch '+p.id);
  if(hash(current.card)!==hash(p.content.card))throw Error('Story patch must preserve approved card '+p.id);
  return {p,path,before:hash(current),after:hash(p.content)};
 });
 for(const row of staged.filter(Boolean)){
  const {p,path,before,after}=row;
  writeFileSync(join(dir,p.id+'.editorial-before-'+before.slice(0,12)+'.json'),JSON.stringify(p.expectedContent,null,2)+'\n');
  writeFileSync(path,JSON.stringify(p.content,null,2)+'\n');
  writeFileSync(join(dir,p.id+'.editorial-patch-'+after.slice(0,12)+'.json'),JSON.stringify({before,after,reasonZh:p.reasonZh},null,2)+'\n');
  console.log(p.id);
 }
}finally{closeSync(fd);unlinkSync(lock);}
