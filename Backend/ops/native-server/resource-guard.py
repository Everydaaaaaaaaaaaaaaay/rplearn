#!/usr/bin/env python3
"""维护准入与有界资源留档；只读取 /proc，不记录参数、环境变量或业务数据。"""
import json
import os
import shutil
import sys
import time
import urllib.request
from pathlib import Path

PROC = Path('/proc')
LOG = Path('/var/log/lingotrip/resources.jsonl')
STATE = Path('/var/log/lingotrip/resources-state.json')
MAX_LOG_BYTES = 4 * 1024 * 1024
BACKUPS = 6


def pressure(text):
    return {line.split()[0]: {k: float(v) for k, v in
            (item.split('=') for item in line.split()[1:])}
            for line in text.splitlines()}


def snapshot():
    memory = {line.split(':')[0]: int(line.split()[1])
              for line in (PROC / 'meminfo').read_text().splitlines()}
    return {'time': time.time(), 'availableMiB': memory['MemAvailable'] / 1024,
            'swapUsedMiB': (memory['SwapTotal'] - memory['SwapFree']) / 1024,
            'memory': pressure((PROC / 'pressure/memory').read_text()),
            'io': pressure((PROC / 'pressure/io').read_text()),
            'load': os.getloadavg(), 'diskFreeMiB': shutil.disk_usage('/opt').free / 1024**2}


def problems(data, minimum_memory=384):
    result = []
    if data['availableMiB'] < minimum_memory:
        result.append('可用内存低于维护余量')
    if data['diskFreeMiB'] < 512:
        result.append('磁盘剩余空间不足')
    if data['memory']['some']['avg10'] >= 5 or data['memory']['full']['avg10'] >= 1:
        result.append('存在持续内存阻塞')
    if data['io']['some']['avg10'] >= 10 or data['io']['full']['avg10'] >= 5:
        result.append('存在持续磁盘阻塞')
    return result


def check(minimum_memory=384):
    data = snapshot()
    failures = problems(data, minimum_memory)
    try:
        with urllib.request.urlopen('http://127.0.0.1:8080/health/ready', timeout=3) as response:
            if response.status != 200 or json.load(response).get('status') != 'ready':
                failures.append('服务尚未就绪')
    except Exception:
        failures.append('健康检查失败')
    print(json.dumps({'event': '维护资源检查', **data, 'failures': failures}, ensure_ascii=False), flush=True)
    if failures:
        raise RuntimeError('；'.join(failures))


def observe():
    # 一次 ready 不能证明稳定；持续观察一分钟后才允许下一项维护。
    started = time.monotonic()
    while True:
        check(256)
        if time.monotonic() - started >= 60:
            return
        time.sleep(5)


def process_sample(previous):
    current = {}
    for path in PROC.iterdir():
        if not path.name.isdigit():
            continue
        try:
            raw = (path / 'stat').read_text()
            fields = raw[raw.rindex(')') + 2:].split()
            identity = path.name + ':' + fields[19]
            io = dict(line.split(': ', 1) for line in (path / 'io').read_text().splitlines())
            cpu = int(fields[11]) + int(fields[12])
            read = int(io['read_bytes'])
            written = int(io['write_bytes'])
            before = previous.get(identity, {})
            current[identity] = {
                'pid': int(path.name), 'name': raw[raw.index('(') + 1:raw.rindex(')')],
                'rssKiB': int(fields[21]) * os.sysconf('SC_PAGE_SIZE') // 1024,
                'cpuTicks': cpu, 'readBytes': read, 'writeBytes': written,
                'cpuDelta': max(0, cpu - before.get('cpuTicks', cpu)),
                'readDelta': max(0, read - before.get('readBytes', read)),
                'writeDelta': max(0, written - before.get('writeBytes', written)),
            }
        except (OSError, ValueError, IndexError, KeyError):
            continue  # 进程可能在读取期间退出。
    return current


def rotate(path):
    if not path.exists() or path.stat().st_size < MAX_LOG_BYTES:
        return
    for index in range(BACKUPS, 0, -1):
        source = path if index == 1 else Path(str(path) + '.' + str(index - 1))
        if source.exists():
            source.replace(Path(str(path) + '.' + str(index)))


def record():
    data = snapshot()
    try:
        previous = json.loads(STATE.read_text())
    except (OSError, ValueError):
        previous = {}
    current = process_sample(previous)
    top = {}
    for metric in ('rssKiB', 'cpuDelta', 'readDelta', 'writeDelta'):
        for item in sorted(current.values(), key=lambda p: p[metric], reverse=True)[:8]:
            top[item['pid']] = item
    data['processes'] = list(top.values())
    data['cpuCounters'] = (PROC / 'stat').read_text().splitlines()[0]
    data['diskCounters'] = (PROC / 'diskstats').read_text().splitlines()
    data['alerts'] = problems(data, 128)
    LOG.parent.mkdir(mode=0o750, parents=True, exist_ok=True)
    rotate(LOG)
    with LOG.open('a') as output:
        output.write(json.dumps(data, ensure_ascii=False) + '\n')
    temporary = STATE.with_suffix('.next')
    temporary.write_text(json.dumps(current))
    temporary.replace(STATE)
    if data['alerts']:
        print(json.dumps({'event': '主机资源告警', 'time': data['time'], 'alerts': data['alerts']}, ensure_ascii=False))


if __name__ == '__main__':
    try:
        {'check': check, 'observe': observe, 'record': record}[sys.argv[1]]()
    except Exception as error:
        print('资源检查失败：' + str(error), file=sys.stderr)
        sys.exit(1)
