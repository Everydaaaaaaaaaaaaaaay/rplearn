#!/usr/bin/env python3
"""Verify current publication media and prepare temporary deployment transports."""
import hashlib,json,tarfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
CAT=ROOT/'Backend/config/learning/originals'
def digest(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
def main():
 data=json.loads((CAT/'catalog.json').read_text())
 transport=ROOT/'build/learning-original-assets';transport.mkdir(exist_ok=True,parents=True)
 records=[]
 for asset in data['audioAssets']+data['imageAssets']:
  ext='.wav' if asset['id'].startswith('audio.') else '.png';source=CAT/'media'/(asset['id']+ext);h=asset['sha256']
  if source.is_symlink() or digest(source)!=h or source.stat().st_size!=asset['byteSize']:raise ValueError('Changed release asset')
  records.append(dict(id=asset['id'],sha256=h,bytes=asset['byteSize'],publication_path=str(source.relative_to(ROOT))))
 packs=[];pending=[];size=0
 def pack(rows):
  name=f'part-{len(packs):03d}.tar.gz';p=transport/name
  if not p.exists():
   with tarfile.open(p,'w:gz',compresslevel=1) as tar:
    for r in rows:tar.add(ROOT/r['publication_path'],arcname=Path(r['publication_path']).name,recursive=False)
  with tarfile.open(p) as tar:
   names=tar.getnames()
   if names!=[Path(r['publication_path']).name for r in rows]:raise ValueError('Existing transport differs')
   for row in rows:
    member=tar.getmember(Path(row['publication_path']).name)
    if not member.isfile() or member.size!=row['bytes']:raise ValueError('Transport asset size differs')
    with tar.extractfile(member) as stream:
     if hashlib.sha256(stream.read()).hexdigest()!=row['sha256']:raise ValueError('Transport asset digest differs')
  packs.append(dict(path=str(p.relative_to(ROOT)),sha256=digest(p),assetCount=len(rows),uncompressedBytes=sum(r['bytes'] for r in rows)))
 for row in records:
  if pending and size+row['bytes']>128*1024**2:pack(pending);pending=[];size=0
  pending.append(row);size+=row['bytes']
 if pending:pack(pending)
 report=dict(catalogSHA256=digest(CAT/'catalog.json'),objects=len(records),uniqueSHA=len({r['sha256'] for r in records}),newArchivedObjects=0,newArchivedBytes=0,transportPacks=packs,temporaryTransportNotRecoverySnapshot=True)
 (transport/'index.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items() if k!='transportPacks'}));print('transport packs:',len(packs))
if __name__=='__main__':main()
