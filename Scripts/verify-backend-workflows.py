#!/usr/bin/env python3
"""Opt-in database/process workflows; owns local services and preserves evidence on failure."""
import argparse
import datetime
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]


def free_port():
    with socket.socket() as listener:
        listener.bind(('127.0.0.1', 0))
        return listener.getsockname()[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--phase', choices=['integration', 'e2e', 'all'], default='all')
    parser.add_argument('--output', type=Path, help='New evidence directory (must not exist)')
    parser.add_argument('--test', action='append', help='Integration test filename, repeatable; default all except external S3 media')
    args = parser.parse_args()
    for binary in ['initdb', 'pg_ctl', 'createdb', 'redis-server', 'pnpm']:
        if not shutil.which(binary):
            parser.error(f'Missing local dependency: {binary}')
    run_id = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex[:8]
    output = (args.output or ROOT / 'build' / 'verification' / run_id).resolve()
    output.mkdir(parents=True, exist_ok=False)
    os.chmod(output, 0o700)
    env = {key: value for key, value in os.environ.items() if key in ['PATH', 'HOME', 'TMPDIR', 'USER', 'LANG', 'LC_ALL']}
    pg_port, redis_port = free_port(), free_port()
    while redis_port == pg_port:
        redis_port = free_port()
    database = 'lingotrip_test_' + uuid.uuid4().hex[:12]
    env.update(DATABASE_URL=f'postgres://127.0.0.1:{pg_port}/{database}', REDIS_URL=f'redis://127.0.0.1:{redis_port}', NODE_ENV='test')
    report = {'runId': run_id, 'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(), 'workingTree': subprocess.check_output(['git', 'status', '--short'], cwd=ROOT, text=True).splitlines(), 'modelCalls': 'mocked; no live providers', 'phases': [], 'excluded': ['S3 media integration requires a dedicated object store', 'NPC art-library benchmark is a separate opt-in dataset evaluation'], 'status': 'running'}
    pg_started = False
    redis = None
    pg_data = output / 'postgres'

    def save():
        temp = output / 'report.tmp'
        temp.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
        temp.replace(output / 'report.json')

    def run(name, command, cwd=ROOT / 'Backend'):
        phase = {'name': name, 'command': command, 'status': 'running', 'log': f'{name}.log'}
        report['phases'].append(phase)
        save()
        print(f'{name}: running; evidence {output / phase["log"]}', flush=True)
        start = time.monotonic()
        with (output / phase['log']).open('w') as log:
            child = subprocess.Popen(command, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                code = child.wait(timeout=600)
            except (BaseException,):
                # Stop the complete pnpm/test/API process group before stopping its database.
                try:
                    os.killpg(child.pid, signal.SIGTERM)
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(child.pid, signal.SIGKILL)
                    child.wait()
                except ProcessLookupError:
                    pass
                raise
        phase.update(status='passed' if code == 0 else 'failed', exitCode=code, seconds=round(time.monotonic() - start, 2))
        save()
        return code == 0

    def interrupted(signum, frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, interrupted)
    try:
        save()
        if not run('initdb', ['initdb', '-D', str(pg_data), '-A', 'trust', '--no-locale', '-E', 'UTF8']):
            raise RuntimeError('Isolated PostgreSQL initialization failed')
        if not run('postgres-start', ['pg_ctl', '-D', str(pg_data), '-l', str(output / 'postgres.log'), '-o', f'-h 127.0.0.1 -p {pg_port} -k {output}', '-w', 'start']):
            raise RuntimeError('Isolated PostgreSQL did not start')
        pg_started = True
        if not run('createdb', ['createdb', '-h', '127.0.0.1', '-p', str(pg_port), database]):
            raise RuntimeError('Test database creation failed')
        redis = subprocess.Popen(['redis-server', '--bind', '127.0.0.1', '--port', str(redis_port), '--save', '', '--appendonly', 'no', '--dir', str(output), '--logfile', str(output / 'redis.log')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for attempt in range(100):
            if redis.poll() is not None:
                raise RuntimeError('Isolated Redis failed to start')
            try:
                with socket.create_connection(('127.0.0.1', redis_port), timeout=.2):
                    break
            except OSError:
                time.sleep(.05)
        else:
            raise RuntimeError('Isolated Redis did not become ready')
        successes = []
        if args.phase in ['integration', 'all']:
            env['RUN_INTEGRATION_TESTS'] = 'true'
            tests = args.test or [str(p.relative_to(ROOT / 'Backend')) for p in sorted((ROOT / 'Backend/test/integration').glob('*.test.ts')) if p.name != 'media.test.ts']
            if args.test:
                report['selection'] = tests
            successes.append(run('integration', ['pnpm', 'exec', 'vitest', 'run', '--maxWorkers=1', '--no-file-parallelism', '--reporter=default', '--reporter=json', f'--outputFile.json={output / "integration.json"}', *tests]))
            env.pop('RUN_INTEGRATION_TESTS')
        if args.phase in ['e2e', 'all']:
            built = run('build', ['pnpm', 'build'])
            successes.append(built)
            if built:
                env['RUN_E2E_TESTS'] = 'true'
                successes.append(run('process-e2e', ['pnpm', 'exec', 'vitest', 'run', '--maxWorkers=1', '--no-file-parallelism', '--reporter=default', '--reporter=json', f'--outputFile.json={output / "process-e2e.json"}', 'test/e2e/backend-process.test.ts']))
        report['status'] = 'passed' if all(successes) else 'failed'
    except (Exception, KeyboardInterrupt) as error:
        report.update(status='interrupted' if isinstance(error, KeyboardInterrupt) else 'failed', error=str(error))
        for phase in report['phases']:
            if phase['status'] == 'running':
                phase['status'] = report['status']
    finally:
        if redis is not None:
            redis.terminate()
            try:
                redis.wait(timeout=10)
            except subprocess.TimeoutExpired:
                redis.kill()
                redis.wait()
        if pg_started:
            if not run('postgres-stop', ['pg_ctl', '-D', str(pg_data), '-m', 'fast', '-w', 'stop']):
                report['status'] = 'failed'
        save()
        print(f'{report["status"]}: {output / "report.json"}', flush=True)
    return 0 if report['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
