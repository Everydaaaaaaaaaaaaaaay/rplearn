"""Prepare ignored render assets from originals; verify all copied source identities."""
import argparse, hashlib, json, shutil, subprocess
from pathlib import Path

root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser()
p.add_argument('--screenshots',type=Path,default=Path('/Users/tiantian/Pictures/LingoTrip-Promo-20260915-v2/final'))
p.add_argument('--captures',type=Path,default=Path('/Users/tiantian/Movies/Coovingo-Promo-20260915/raw'))
p.add_argument('--learning-capture',type=Path,default=Path('/Users/tiantian/Movies/Coovingo-Promo-20260915-v2/raw/10-level.png'))
p.add_argument('--landscape-captures',type=Path,default=Path('/Users/tiantian/Movies/Coovingo-Landscape-20260916/raw'))
a=p.parse_args();repo=root.parents[1];dest=root/'public/media';dest.mkdir(parents=True,exist_ok=True)
expected={e['file']:e['sha256'] for e in json.loads((root/'assets.json').read_text())}
def verify(path):
 if path.name in expected and hashlib.sha256(path.read_bytes()).hexdigest()!=expected[path.name]:
  raise ValueError(f'Source hash mismatch: {path}')
def copy(src,name):
 target=dest/name;shutil.copy2(src,target);verify(target)
for name in ['01-messages','02-chat','03-dictionary','04-companion','05-city','07-encounter','08-story','09-favorites']:
 copy(a.screenshots/(name+'.png'),name+'.png')
copy(a.captures/'city-singapore.png','city-singapore.png')
copy(a.learning_capture,'10-level.png')
for name in ['ruby','oliver','marcus']:
 copy(repo/f'App/Resources/Avatars/avatar_p3r_{name}.png',name+'.png')
copy(repo/'App/Debug/MarketingCapture/marketing-victor.png','victor.png')
copy(repo/'App/Assets.xcassets/AppIcon.appiconset/icon_1024.png','icon.png')
music=dest/'george-street-shuffle.mp3'
if not music.exists():
 subprocess.run(['curl','-L','--fail','--max-time','90','https://incompetech.com/music/royalty-free/mp3-royaltyfree/George%20Street%20Shuffle.mp3','-o',str(music)],check=True)
verify(music)
subprocess.run(['ffmpeg','-hide_banner','-y','-ss','18.823529','-i',str(music),'-t','40','-af','afade=t=in:st=0:d=0.6,afade=t=out:st=37:d=3,loudnorm=I=-18:TP=-2:LRA=9','-c:a','aac','-b:a','256k',str(dest/'music-v2.m4a')],check=True)
raw_motion=a.captures/'take2/chat-motion-raw.mp4'
record=next(r for r in json.loads((root/'capture-manifest.json').read_text()) if r['file'].endswith('/take2/chat-motion-raw.mp4'))
if hashlib.sha256(raw_motion.read_bytes()).hexdigest()!=record['sha256']:
 raise ValueError('Capture changed: review native timing and update capture-manifest.json first')
# simctl emits no further frames once UI becomes idle. Hold its verified completed
# end-state for two editorial seconds; active typing/arrival timestamps are unchanged.
subprocess.run(['ffmpeg','-hide_banner','-y','-i',str(a.captures/'take2/chat-motion-raw.mp4'),'-vf','fps=60,tpad=stop_mode=clone:stop_duration=2','-an','-c:v','libx264','-crf','17','-pix_fmt','yuv420p','-movflags','+faststart',str(dest/'chat-motion.mp4')],check=True)
print('Prepared original screenshots, native footage and attributed music.')

# Third edition uses existing product artwork as editorial backgrounds.
copy(repo/'App/Assets.xcassets/home_city_london.imageset/home_city_london.jpg','bg-london.jpg')
copy(repo/'App/Assets.xcassets/detail_placement_learning_desk.imageset/detail_placement_learning_desk.jpg','bg-desk.jpg')
copy(repo/'App/Resources/StoryArt/Departures/dp_london_day.jpg','bg-bookshop.jpg')

# Landscape uses a 44-second score and fresh native static activity captures.
subprocess.run(['ffmpeg','-hide_banner','-y','-ss','18.823529','-i',str(music),'-t','44','-af','afade=t=in:st=0:d=0.6,afade=t=out:st=41.1:d=2.9,loudnorm=I=-18:TP=-1.5:LRA=9','-ar','48000','-c:a','aac','-b:a','256k',str(dest/'music.m4a')],check=True)
attachments=json.loads((a.landscape_captures/'manifest.json').read_text())[0]['attachments']
for scene in ['park','pond','raincafe']:
 record=next(x for x in attachments if f'-{scene}_' in x['suggestedHumanReadableName'])
 copy(a.landscape_captures/record['exportedFileName'],f'activity-{scene}-wide.png')
