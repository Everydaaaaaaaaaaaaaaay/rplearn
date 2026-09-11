import json, os, subprocess, time, sys
from pathlib import Path
device=sys.argv[1]
out=Path(sys.argv[2]);out.mkdir(parents=True, exist_ok=True)
env={**os.environ,'DEVELOPER_DIR':'/Applications/Xcode-beta.app/Contents/Developer'}
base=['xcrun','devicectl','device']
try:
 for theme in ['light','dark']:
  for screen in ['chat','dictionary','activity','companion']:
   flags={'UI_TEST_SKIP_ONBOARDING':'1','UI_TEST_DISABLE_BACKGROUND_REFRESH':'1','UI_TEST_WELCOME_CAPTURE':'1','UI_TEST_CAPTURE_APPEARANCE':theme,'LINGOTRIP_BACKEND_URL':'http://127.0.0.1:9'}
   if screen in ['chat','dictionary']:
    flags['UI_TEST_NATIVE_CAPTURE']='chat'
    if screen=='dictionary': flags['UI_TEST_CAPTURE_DICTIONARY']='1'
   elif screen=='activity':
    flags.update(UI_TEST_HOME_DESTINATION='activities',UI_TEST_TAB='home',UI_TEST_SOCIAL_FIXTURE='1',UI_TEST_ACTIVITY_NAMESPACE='welcome-phone')
   else:
    flags.update(UI_TEST_SKIP_ONBOARDING='0',UI_TEST_ONBOARDING_WELCOME='0',UI_TEST_ONBOARDING_SELECTION='1')
   subprocess.run(base+['process','launch','--device',device,'--terminate-existing','--environment-variables',json.dumps(flags),'com.tiantian.lingotrip'],env=env,check=True,stdout=subprocess.DEVNULL)
   time.sleep(5)
   subprocess.run(base+['capture','screenshot','--device',device,'--destination',str(out/f'welcome-{screen}-{theme}.png')],env=env,check=True,stdout=subprocess.DEVNULL)
   print(screen,theme,'saved',flush=True)
finally:
 subprocess.run(base+['process','launch','--device',device,'--terminate-existing','com.tiantian.lingotrip'],env=env,check=True)
