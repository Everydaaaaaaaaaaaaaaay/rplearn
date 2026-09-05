from pathlib import Path
from PIL import Image,ImageDraw,ImageOps
import numpy as np,json,hashlib,argparse
parser=argparse.ArgumentParser();parser.add_argument('--catalog',required=True);parser.add_argument('--output',required=True);args=parser.parse_args()
catalog_path=Path(args.catalog).resolve();root=catalog_path.parent;out=Path(args.output).resolve();out.mkdir(parents=True,exist_ok=True)
catalog=json.load(open(catalog_path));entries=[e for e in catalog['entries'] if e.get('status') not in ['rejected','removed'] and (root/e['image']).exists()];paths=[root/e['image'] for e in entries];canonical={root/e['image']:e['key'] for e in entries}
records=[];vectors=[]
for path in paths:
 im=Image.open(path).convert('RGB'); a=np.asarray(im.resize((128,128))).astype(float)/255
 mx=a.max(2);mn=a.min(2);neutral=mx-mn<.16
 g=np.where(mx<.28,.05,np.where(neutral & (mn>.68),.95,.45)).astype('float32')
 crop=g[16:91,20:109]; small=np.asarray(Image.fromarray(crop).resize((32,32))).astype(float)
 # Compare normalized graphic tone patterns and their edge gradients, including mirrored pose.
 def feat(z):
  x=np.concatenate([(z-z.mean()).ravel(),np.diff(z,axis=0).ravel(),np.diff(z,axis=1).ravel()]);return x/(np.linalg.norm(x)+1e-10)
 vectors.append((feat(small),feat(small[:,::-1])))
 records.append({'key':canonical[path],'path':str(path.relative_to(root)),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
for i,r in enumerate(records):
 ranked=[]
 for j,s in enumerate(records):
  if i==j:continue
  sim=max(float(np.dot(vectors[i][0],vectors[j][0])),float(np.dot(vectors[i][0],vectors[j][1])))
  ranked.append({'key':s['key'],'score':round(sim,4)})
 r['nearest']=sorted(ranked,key=lambda a:-a['score'])[:8]
for start in range(0,len(paths),16):
 sheet=Image.new('RGB',(1120,1200),'#e8e8ec');d=ImageDraw.Draw(sheet)
 for k,path in enumerate(paths[start:start+16]):
  x=(k%4)*280;y=(k//4)*300
  im=Image.open(path).convert('RGB');im=ImageOps.fit(im,(260,260));mask=Image.new('L',(260,260));ImageDraw.Draw(mask).ellipse((0,0,259,259),fill=255)
  sheet.paste(im,(x+10,y+5),mask);d.text((x+10,y+270),canonical[path],fill='black')
 sheet.save(out/f'all-{start//16+1}.png')
json.dump({'method':'hue-normalized fixed face-region tone and gradient cosine, mirror-aware; shortlist only, NOT an identity classifier','records':records},open(out/'neighbors.json','w'),indent=2)
print(json.dumps({'count':len(paths),'sheets':(len(paths)+15)//16,'folder':str(out),'highest':[{'key':r['key'],'nearest':r['nearest'][0]} for r in sorted([r for r in records if r['nearest']],key=lambda r:-r['nearest'][0]['score'])[:12]]}))

# Each contact row shows a new/unreviewed candidate and its five strongest numerical neighbors.
by_key={canonical[p]:p for p in paths}
unreviewed={e['key'] for e in catalog['entries'] if e.get('status')!='accepted'}
rows=[r for r in records if r['key'] in unreviewed]
for start in range(0,len(rows),5):
 sheet=Image.new('RGB',(1440,1100),'#eeeef0');draw=ImageDraw.Draw(sheet)
 for row,r in enumerate(rows[start:start+5]):
  keys=[r['key']]+[n['key'] for n in r['nearest'][:5]]
  for col,key in enumerate(keys):
   im=Image.open(by_key[key]).convert('RGB');w,h=im.size;im=im.crop((w*.15,h*.1,w*.9,h*.72));im=ImageOps.grayscale(im).convert('RGB');im=ImageOps.fit(im,(222,190));x=col*240+8;y=row*220+4;sheet.paste(im,(x,y));draw.text((x,y+193),key,fill='black')
 sheet.save(out/f'neighbors-{start//5+1}.png')
