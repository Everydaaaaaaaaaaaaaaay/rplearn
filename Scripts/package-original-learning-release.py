#!/usr/bin/env python3
"""Package only this learning change over the running backend's known Git base.

Unrelated, not-yet-deployed commits in the workspace remain out of production.
No research tree or original media is cloned into this staging directory.
"""
import argparse,hashlib,io,json,os,subprocess,tarfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def git(*args):return subprocess.check_output(['git',*args],cwd=ROOT)
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--base',required=True);parser.add_argument('--change',required=True);args=parser.parse_args()
 base=git('rev-parse',args.base).decode().strip();change=git('rev-parse',args.change).decode().strip();version='originals-'+change[:12]
 stage=ROOT/'build'/('original-backend-source-'+change[:12]);stage.mkdir(exist_ok=False)
 archive=git('archive',base,'Backend')
 with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
  for member in tar:
   path=Path(member.name)
   if not path.parts or path.parts[0]!='Backend' or '..' in path.parts:raise ValueError('Unsafe Git archive path')
   tar.extract(member,stage)
 changed=[p for p in git('diff-tree','--no-commit-id','--name-only','-r',change,'--','Backend').decode().splitlines() if p]
 for name in changed:
  target=stage/name
  try:content=git('show',change+':'+name)
  except subprocess.CalledProcessError:
   target.unlink(missing_ok=True);continue
  target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(content)
  mode=git('ls-tree',change,'--',name).decode().split()[0]
  if mode=='100755':target.chmod(0o755)
 (stage/'Backend/node_modules').symlink_to(ROOT/'Backend/node_modules',target_is_directory=True)
 target=ROOT/'build'/('lingotrip-backend-'+version+'.tar.gz')
 subprocess.run(['bash',str(stage/'Backend/ops/native-server/package-release.sh'),version,str(target)],cwd=stage/'Backend',check=True)
 omitted=[p for p in git('diff','--name-only',base,change+'^','--','Backend/src').decode().splitlines() if p not in changed]
 record=dict(version=version,baseCommit=base,learningChangeCommit=change,overlayPaths=changed,unrelatedUnreleasedBackendPathsExcluded=omitted,archive=str(target.relative_to(ROOT)),sha256=hashlib.sha256(target.read_bytes()).hexdigest(),originalMediaExcluded=True)
 (ROOT/'build/original-backend-release.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n');print(json.dumps(record,ensure_ascii=False))
if __name__=='__main__':main()
