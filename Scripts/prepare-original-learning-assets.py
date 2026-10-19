#!/usr/bin/env python3
"""Archive only new SHA objects and prepare bounded, temporary deployment transports."""
import hashlib,json,os,shutil,tarfile,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'Research/GuYouJi-English-Benchmark'
CAT=ROOT/'Backend/config/learning/originals'
def digest(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
def main():
 data=json.loads((CAT/'catalog.json').read_text());registry=json.loads((BASE/'Storage/local-snapshots.json').read_text());store=Path(registry['content_archives'][-1]['archive_path'])/'objects'
 transport=ROOT/'build/learning-original-assets';transport.mkdir(exist_ok=True)
 records=[];new=0;newbytes=0
 for asset in data['audioAssets']+data['imageAssets']:
  ext='.wav' if asset['id'].startswith('audio.') else '.png';source=CAT/'media'/(asset['id']+ext);h=asset['sha256'];target=store/h
  if digest(source)!=h or source.stat().st_size!=asset['byteSize']:raise ValueError('Changed release asset')
  if not target.exists():
   shutil.copyfile(source,target);new+=1;newbytes+=asset['byteSize']
  if target.is_symlink() or target.stat().st_size!=asset['byteSize'] or digest(target)!=h:raise ValueError('Archive mismatch')
  target.chmod(0o400)
  records.append(dict(id=asset['id'],sha256=h,bytes=asset['byteSize'],archive_object=str(target),publication_path=str(source.relative_to(ROOT))))
 # Restore two different kinds to independent files; no full tree or snapshot.
 with tempfile.TemporaryDirectory(prefix='original-restore-',dir=transport) as td:
  for prefix in ['audio.','image.']:
   row=next(r for r in records if r['id'].startswith(prefix));target=Path(td)/prefix
   shutil.copyfile(row['archive_object'],target)
   if digest(target)!=row['sha256'] or target.stat().st_ino==Path(row['archive_object']).stat().st_ino:raise ValueError('Restore differs')
 archive=dict(version=1,scope='derived owned original learning media only',archiveRoot=str(store),newObjects=new,newBytes=newbytes,restoreVerified=True,newFullSnapshots=0,objects=records)
 record=BASE/'Storage/LearningOriginalPublicationAssets-v0.1.json'
 if record.exists():
  old=json.loads(record.read_text())
  if old['objects']!=records:raise ValueError('Frozen archive record differs')
 else:record.write_text(json.dumps(archive,ensure_ascii=False,indent=2)+'\n')
 packs=[];pending=[];size=0
 def pack(rows):
  name=f'part-{len(packs):03d}.tar.gz';p=transport/name
  if not p.exists():
   with tarfile.open(p,'w:gz',compresslevel=1) as tar:
    for r in rows:tar.add(ROOT/r['publication_path'],arcname=Path(r['publication_path']).name,recursive=False)
  with tarfile.open(p) as tar:
   names=tar.getnames()
   if names!=[Path(r['publication_path']).name for r in rows]:raise ValueError('Existing transport differs')
  packs.append(dict(path=str(p.relative_to(ROOT)),sha256=digest(p),assetCount=len(rows),uncompressedBytes=sum(r['bytes'] for r in rows)))
 for row in records:
  if pending and size+row['bytes']>128*1024**2:pack(pending);pending=[];size=0
  pending.append(row);size+=row['bytes']
 if pending:pack(pending)
 report=dict(catalogSHA256=digest(CAT/'catalog.json'),objects=len(records),uniqueSHA=len({r['sha256'] for r in records}),newArchivedObjects=new,newArchivedBytes=newbytes,transportPacks=packs,temporaryTransportNotRecoverySnapshot=True)
 (transport/'index.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items() if k!='transportPacks'}));print('transport packs:',len(packs))
if __name__=='__main__':main()
