#!/usr/bin/env python3
"""Stage one bounded, content-addressed asset transport inside maintenance scope."""
import hashlib, os, re, shutil, sys, tarfile, tempfile
from pathlib import Path

def digest(path):
 h=hashlib.sha256()
 with path.open('rb') as stream:
  for block in iter(lambda:stream.read(1024*1024),b''):h.update(block)
 return h.hexdigest()

def stage(archive,expected,root):
 if not re.fullmatch('[a-f0-9]{64}',expected) or digest(archive)!=expected:raise ValueError('Asset archive SHA mismatch')
 root.mkdir(parents=True,exist_ok=True)
 total=0;seen=set()
 with tempfile.TemporaryDirectory(prefix='original-media-',dir=root.parent) as scratch:
  scratch=Path(scratch)
  with tarfile.open(archive,'r|gz') as stream:
   for member in stream:
    match=re.fullmatch(r'(audio|image)\.([a-f0-9]{64})\.(wav|png)',member.name)
    if not match or not member.isfile() or member.name in seen or member.size>43300000:raise ValueError('Unsafe or oversized asset member')
    total+=member.size
    if total>160*1024**2:raise ValueError('Asset transport exceeds bounded batch')
    seen.add(member.name);source=stream.extractfile(member)
    if source is None:raise ValueError('Missing asset bytes')
    h=hashlib.sha256()
    with (scratch/member.name).open('wb') as target:
     for block in iter(lambda:source.read(1024*1024),b''):target.write(block);h.update(block)
    if h.hexdigest()!=match[2]:raise ValueError('Asset content SHA mismatch')
  if not seen:raise ValueError('Empty asset transport')
  for name in seen:
   target=root/name
   if target.exists():
    if target.is_symlink() or digest(target)!=name.split('.')[1]:raise ValueError('Existing immutable asset differs')
   else:
    source=scratch/name;source.chmod(0o640);os.replace(source,target)
 return len(seen),total

if __name__=='__main__':
 if os.geteuid()!=0 or '0::/system.slice/lingotrip-maintenance.service' not in Path('/proc/self/cgroup').read_text().splitlines():raise SystemExit('Maintenance scope required')
 count,size=stage(Path(sys.argv[1]),sys.argv[2],Path('/opt/lingotrip/shared/learning-originals-media'))
 print(f'{count} SHA-bound assets staged ({size} bytes); no learning units published')
