"""Native capture: simulator recording or phone screenshots, isolated DEBUG data."""
import argparse, json, os, signal, subprocess, time
from pathlib import Path

p=argparse.ArgumentParser()
p.add_argument('--device', required=True)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--simulator', action='store_true')
p.add_argument('--screenshots-only', action='store_true', help='For phones without CoreDevice Screen Recording support')
a=p.parse_args(); a.output.mkdir(parents=True, exist_ok=True)
bundle='com.tiantian.lingotrip'
def run(*args):
 return subprocess.run(['xcrun','devicectl','--timeout','50',*args], check=True)
def launch(flags):
 if a.simulator:
  subprocess.run(['xcrun','simctl','launch','--terminate-running-process',a.device,bundle],env={**os.environ,**{'SIMCTL_CHILD_'+k:v for k,v in flags.items()}},check=True)
 else:
  run('device','process','launch','--device',a.device,'--terminate-existing','--environment-variables',json.dumps(flags),bundle)
def screenshot(name):
 if a.simulator:
  subprocess.run(['xcrun','simctl','io',a.device,'screenshot',str(a.output/name)],check=True)
 else:
  run('device','capture','screenshot','--device',a.device,'--destination',str(a.output/name))
base={'UI_TEST_SKIP_ONBOARDING':'1','UI_TEST_REQUIRE_AUTHENTICATION':'0','UI_TEST_DISABLE_BACKGROUND_REFRESH':'1','UI_TEST_WELCOME_CAPTURE':'1','UI_TEST_MARKETING_CAPTURE':'1','UI_TEST_CAPTURE_APPEARANCE':'light','UI_TEST_CITY_TAB_REGION':'london','LINGOTRIP_BACKEND_URL':'http://127.0.0.1:9'}
try:
 if not a.screenshots_only:
  launch({**base,'UI_TEST_NATIVE_CAPTURE':'chat','UI_TEST_MARKETING_MOTION':'1'})
  if a.simulator:
   r=subprocess.Popen(['xcrun','simctl','io',a.device,'recordVideo','--codec=h264','--force',str(a.output/'chat-motion-raw.mp4')])
   try:time.sleep(30)
   finally:r.send_signal(signal.SIGINT);r.wait(timeout=20)
  else:
   run('device','capture','screen-record','--device',a.device,'--destination',str(a.output/'chat-motion-raw.mp4'),'--duration','30','--codec','h264')
  screenshot('chat-after.png')
 else:
  launch({**base,'UI_TEST_TAB':'home','UI_TEST_CITY_TAB_REGION':'singapore'})
  time.sleep(6)
  screenshot('city-singapore.png')
finally:
 if not a.simulator:
  run('device','process','launch','--device',a.device,'--terminate-existing',bundle)
