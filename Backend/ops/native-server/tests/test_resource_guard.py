"""本地夹具验证维护门槛及留档上限，不访问生产。"""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('guard', Path(__file__).parents[1] / 'resource-guard.py')
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


def healthy():
    return {'availableMiB': 420, 'diskFreeMiB': 1024,
            'memory': guard.pressure('some avg10=0 avg60=0 avg300=0 total=10\nfull avg10=0 avg60=0 avg300=0 total=0'),
            'io': guard.pressure('some avg10=0 avg60=0 avg300=0 total=10\nfull avg10=0 avg60=0 avg300=0 total=0')}


class ResourceGuardTest(unittest.TestCase):
    def test_memory_budget(self):
        data = healthy()
        self.assertEqual(guard.problems(data), [])
        data['availableMiB'] = 383
        self.assertIn('可用内存低于维护余量', guard.problems(data))
        self.assertEqual(guard.problems(data, 256), [])

    def test_pressure_and_disk(self):
        data = healthy()
        data['memory']['full']['avg10'] = 1
        data['io']['some']['avg10'] = 10
        data['diskFreeMiB'] = 511
        self.assertEqual(len(guard.problems(data)), 3)

    def test_health_timeout_refuses_maintenance(self):
        with patch.object(guard, 'snapshot', return_value=healthy()), patch.object(guard.urllib.request, 'urlopen', side_effect=TimeoutError), patch('builtins.print'):
            with self.assertRaisesRegex(RuntimeError, '健康检查失败'):
                guard.check()

    def test_rotation_has_fixed_limit(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(guard, 'MAX_LOG_BYTES', 4), patch.object(guard, 'BACKUPS', 2):
            path = Path(folder) / 'record'
            for number in range(6):
                path.write_text(str(number) * 5)
                guard.rotate(path)
            self.assertEqual(sorted(p.name for p in Path(folder).iterdir()), ['record.1', 'record.2'])
            self.assertEqual(Path(str(path) + '.2').read_text(), '44444')

    def test_process_deltas_handle_pid_reuse_without_arguments(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(guard, 'PROC', Path(folder)):
            p = Path(folder) / '9'; p.mkdir()
            fields = ['0'] * 22
            fields[11], fields[12], fields[19], fields[21] = '15', '5', '123', '2'
            (p / 'stat').write_text('9 (node worker) ' + ' '.join(fields))
            (p / 'io').write_text('read_bytes: 50\nwrite_bytes: 70\n')
            row = guard.process_sample({'9:123': {'cpuTicks': 17, 'readBytes': 40, 'writeBytes': 60}})['9:123']
            self.assertEqual((row['cpuDelta'], row['readDelta'], row['writeDelta']), (3, 10, 10))
            self.assertNotIn('arguments', row)
            self.assertEqual(guard.process_sample({'9:122': {'readBytes': 0}})['9:123']['readDelta'], 0)

    def test_observation_stops_at_first_pressure_failure(self):
        with patch.object(guard, 'check', side_effect=RuntimeError('压力')), patch.object(guard.time, 'sleep') as sleep:
            with self.assertRaises(RuntimeError):
                guard.observe()
            sleep.assert_not_called()

if __name__ == '__main__':
    unittest.main()
