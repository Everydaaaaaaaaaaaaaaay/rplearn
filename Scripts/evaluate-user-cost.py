#!/usr/bin/env python3
"""Opt-in paid native E2E evaluation. Credentials remain outside tracked artifacts."""
import argparse
import datetime
import json
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import time
import urllib.request
import urllib.parse

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--live', action='store_true', help='Explicitly allow real paid model requests')
p.add_argument('--output', type=Path, required=True)
p.add_argument('--simulator', required=True, help='Dedicated simulator UUID; never erased by this script')
p.add_argument('--max-model-cny', type=float, default=4)
p.add_argument('--port', type=int, default=55452)
p.add_argument('--replicates', type=int, default=1)
p.add_argument('--resume', action='store_true', help='Resume the same interrupted run without new identities or budget')
a = p.parse_args()
if not a.live:
    p.error('Use --live only for an explicitly authorized paid evaluation; ordinary tests stay offline')
if not os.environ.get('DEEPSEEK_API_KEY'):
    p.error('DEEPSEEK_API_KEY must be supplied in the environment; never put it in arguments or artifacts')
u = urllib.parse.urlparse(os.environ.get('DATABASE_URL', ''))
if u.hostname not in ('127.0.0.1', 'localhost') or not u.path.startswith('/lingotrip_cost_eval_'):
    p.error('DATABASE_URL must point to a dedicated loopback lingotrip_cost_eval_* database')
if not (1 <= a.replicates <= 10) or a.max_model_cny < 3.5 * a.replicates:
    p.error('Each replicate has ¥3.50 in total nominal per-user budgets; increase the explicit cap or reduce replicates')
# A fresh user budget may reset at UTC midnight. Keep one evaluation within its issuance day.
now = datetime.datetime.now(datetime.timezone.utc)
if now.hour >= 22:
    p.error('Start at least two hours before UTC midnight to avoid resetting daily budgets during a run')
a.output = a.output.resolve()
a.output.mkdir(parents=True, exist_ok=True, mode=0o700)
if (a.output / 'private-config.json').exists() and not a.resume:
    p.error('Output already contains a run; use a fresh directory. Existing evidence is never overwritten')
if a.resume:
    prior_report = a.output / 'report.json'
    if not prior_report.exists() or any(s['ledger'] for s in json.loads(prior_report.read_text())['rawSessions']):
        p.error('Resume is limited to setup failures with zero recorded model calls; preserve paid partial samples and start a separate run')
env = dict(os.environ, NODE_ENV='test', HOST='127.0.0.1', PORT=str(a.port),
           AI_USER_MINUTE_LIMIT='30', LOG_LEVEL='warn', METRICS_ENABLED='false',
           COST_EVAL_BASE_URL=f'http://127.0.0.1:{a.port}', COST_EVAL_REPLICATES=str(a.replicates),
           COST_EVAL_MAX_CNY=str(a.max_model_cny))

def run(args, log):
    with (a.output / log).open('ab') as out:
        subprocess.run(args, cwd=ROOT / 'Backend', env=env, stdout=out, stderr=subprocess.STDOUT, check=True)

if not a.resume:
    run(['pnpm', 'exec', 'tsx', 'src/cli/cost-eval.ts', 'prepare', str(a.output)], 'prepare.log')
# Only the isolated backend process needs a provider credential; the simulator never receives it.
child = None
try:
    backend_log = (a.output / 'backend.log').open('ab')
    child = subprocess.Popen(['pnpm', 'exec', 'tsx', 'src/server.ts'], cwd=ROOT/'Backend', env=env,
                             stdout=backend_log, stderr=subprocess.STDOUT, start_new_session=True)
    for _ in range(60):
        try:
            with urllib.request.urlopen(f'http://127.0.0.1:{a.port}/health/ready', timeout=1) as r:
                if r.status == 200:
                    break
        except (OSError, ValueError):
            if child.poll() is not None:
                raise RuntimeError('Isolated backend exited; see backend.log')
            time.sleep(1)
    else:
        raise RuntimeError('Isolated backend did not become ready')
    build_env = {k:v for k,v in env.items() if k not in ('DEEPSEEK_API_KEY','DATABASE_URL','REDIS_URL')}
    derived = ROOT/'build/DerivedData-cost-eval'
    with (a.output/'native.log').open('ab') as log:
        subprocess.run(['xcodegen','generate'],cwd=ROOT,env=build_env,stdout=log,stderr=subprocess.STDOUT,check=True)
        subprocess.run(['xcodebuild','-quiet','-project','LingoTrip.xcodeproj','-scheme','LingoTrip',
            '-configuration','Debug','-destination',f'id={a.simulator}','-derivedDataPath',str(derived),
            f'COST_EVAL_CONFIG={a.output / "private-config.json"}','build-for-testing'],
            cwd=ROOT,env=build_env,stdout=log,stderr=subprocess.STDOUT,check=True)
        paths = sorted((derived/'Build/Products').glob('*.xctestrun'), key=lambda x:x.stat().st_mtime)
        if not paths:
            raise RuntimeError('Missing compiled test run manifest')
        original = paths[-1]
        plan = plistlib.loads(original.read_bytes())
        targets = ([target for configuration in plan['TestConfigurations'] for target in configuration['TestTargets']]
                   if 'TestConfigurations' in plan else [target for name,target in plan.items() if not name.startswith('__') and isinstance(target,dict)])
        for target in targets:
            variables = target.setdefault('EnvironmentVariables', {})
            variables.update(LINGOTRIP_BACKEND_URL=env['COST_EVAL_BASE_URL'], UI_TEST_SKIP_ONBOARDING='1', UI_TEST_DISABLE_BACKGROUND_REFRESH='1')
        # __TESTROOT__ is relative to this file; retain it beside the compiled products.
        testplan = original.parent/'CostEvaluation.xctestrun'
        testplan.write_bytes(plistlib.dumps(plan))
        deadline = datetime.datetime.combine(now.date()+datetime.timedelta(days=1), datetime.time(), tzinfo=datetime.timezone.utc).timestamp()-60
        remaining_seconds = min(7000, int(deadline-time.time()))
        if remaining_seconds < 60:
            raise RuntimeError('Insufficient time before the credit window resets; preserve this unstarted run')
        subprocess.run(['xcodebuild','-quiet','-xctestrun',str(testplan),'-destination',f'id={a.simulator}',
            '-only-testing:LingoTripTests/LiveUsageCostWorkflowTests','-resultBundlePath',str(a.output/f'native-{int(time.time())}.xcresult'),
            'test-without-building'],cwd=ROOT,env=build_env,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=remaining_seconds)
finally:
    # Partial runs also get reports, including missing native evidence and unresolved fees.
    try:
        run(['pnpm','exec','tsx','src/cli/cost-eval.ts','report',str(a.output)],'report.log')
    finally:
        if child and child.poll() is None:
            os.killpg(child.pid,signal.SIGTERM)
            try: child.wait(timeout=15)
            except subprocess.TimeoutExpired: os.killpg(child.pid,signal.SIGKILL)
report = json.loads((a.output/'report.json').read_text())
if any(s['status'] in ('missing_native_evidence','failed') for s in report['sessions']):
    raise SystemExit(f'Workflow has failed or missing samples; inspect {a.output / "report.md"}')
print(a.output/'report.md')
