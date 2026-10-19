#!/usr/bin/env python3
"""Up to three independently atomic catalogs under one existing maintenance budget."""
import json,os,re,subprocess,sys
from pathlib import Path

def commands(value):
 if not isinstance(value,list) or not 1<=len(value)<=3:raise ValueError('One to three batches required')
 seen=set();result=[]
 for row in value:
  if not isinstance(row,dict) or set(row)!={'batch','hash'} or not re.fullmatch(r'b[0-9]{3}',row['batch']) or not re.fullmatch(r'[a-f0-9]{64}',row['hash']) or row['batch'] in seen:raise ValueError('Invalid publication plan')
  seen.add(row['batch']);result.append(['/opt/lingotrip/runtime/bin/node','--max-old-space-size=128','--env-file=/etc/lingotrip/backend.env','--env-file=/etc/lingotrip/release.env','dist/cli/learning-originals.js','publish',row['hash'],row['batch']])
 return result
if __name__=='__main__':
 if os.geteuid()!=0 or '0::/system.slice/lingotrip-maintenance.service' not in Path('/proc/self/cgroup').read_text().splitlines():raise SystemExit('Maintenance scope required')
 for cmd in commands(json.loads(Path(sys.argv[1]).read_text())):subprocess.run(cmd,check=True)
