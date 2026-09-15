"""Capture actual App rendering using an isolated DEBUG workspace; never composite UI."""
import argparse, json, os, subprocess, time
from pathlib import Path

SCENES = [
    ('01-messages', {'UI_TEST_TAB': 'messages'}, 6),
    ('02-chat', {'UI_TEST_NATIVE_CAPTURE': 'chat'}, 6),
    ('03-dictionary', {'UI_TEST_NATIVE_CAPTURE': 'chat', 'UI_TEST_CAPTURE_DICTIONARY': '1'}, 7),
    ('04-companion', {'UI_TEST_NATIVE_CAPTURE': 'profile'}, 6),
    ('05-city', {'UI_TEST_TAB': 'home'}, 7),
    ('06-activities', {'UI_TEST_TAB': 'home', 'UI_TEST_HOME_DESTINATION': 'activities', 'UI_TEST_SOCIAL_FIXTURE': '1'}, 7),
    ('07-encounter', {'UI_TEST_TAB': 'home', 'UI_TEST_HOME_DESTINATION': 'activities', 'UI_TEST_SOCIAL_FIXTURE': '1', 'UI_TEST_NATIVE_CAPTURE': 'encounter'}, 21),
    ('08-story', {'UI_TEST_TAB': 'home', 'UI_TEST_LONDON_EPISODE': '1', 'UI_TEST_EPISODE_AUDIO': '0'}, 7),
    ('09-favorites', {'UI_TEST_TAB': 'favorites'}, 7),
]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('device')
    parser.add_argument('output', type=Path)
    parser.add_argument('--simulator', action='store_true')
    parser.add_argument('--scene', choices=[s[0] for s in SCENES])
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    bundle = 'com.tiantian.lingotrip'
    try:
        for name, overrides, settle in SCENES:
            if args.scene and name != args.scene:
                continue
            flags = {
                'UI_TEST_SKIP_ONBOARDING': '1', 'UI_TEST_DISABLE_BACKGROUND_REFRESH': '1',
                'UI_TEST_WELCOME_CAPTURE': '1', 'UI_TEST_MARKETING_CAPTURE': '1',
                'UI_TEST_CAPTURE_APPEARANCE': 'light', 'UI_TEST_CITY_TAB_REGION': 'london',
                'UI_TEST_ACTIVITY_NAMESPACE': f'marketing-{time.time_ns()}',
                'LINGOTRIP_BACKEND_URL': 'http://127.0.0.1:9', **overrides,
            }
            if args.simulator:
                subprocess.run(['xcrun', 'simctl', 'terminate', args.device, bundle], env=env, capture_output=True)
                subprocess.run(['xcrun', 'simctl', 'launch', args.device, bundle],
                               env={**env, **{f'SIMCTL_CHILD_{k}': v for k,v in flags.items()}}, check=True)
            else:
                command = ['xcrun', 'devicectl', '--timeout', '45', 'device', 'process', 'launch', '--device', args.device,
                           '--terminate-existing', '--environment-variables', json.dumps(flags), bundle]
                for attempt in range(3):
                    result = subprocess.run(command, env=env)
                    if result.returncode == 0:
                        break
                    if attempt == 2:
                        result.check_returncode()
                    time.sleep(3)

            time.sleep(settle)
            dest = args.output / f'{name}.png'
            command = ['xcrun', 'simctl', 'io', args.device, 'screenshot', str(dest)] if args.simulator else [
                'xcrun', 'devicectl', '--timeout', '45', 'device', 'capture', 'screenshot', '--device', args.device, '--destination', str(dest)]
            subprocess.run(command, env=env, check=True)
            print(f'Saved {dest}', flush=True)
    finally:
        if not args.simulator:
            subprocess.run(['xcrun', 'devicectl', '--timeout', '30', 'device', 'process', 'launch', '--device', args.device,
                            '--terminate-existing', bundle], env=env)

if __name__ == '__main__':
    main()
