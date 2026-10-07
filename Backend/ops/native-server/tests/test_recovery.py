"""临时目录验证回滚和版本竞争，不操作生产路径或真实服务。"""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / 'recover-deployment.sh'

class RecoveryTest(unittest.TestCase):
    def test_recovery_and_stale_state_protection(self):
        for changed in (False, True):
            with self.subTest(changed=changed), tempfile.TemporaryDirectory() as folder:
                root = Path(folder).resolve()
                app, etc = root / 'app', root / 'etc'
                (app / 'releases').mkdir(parents=True); etc.mkdir()
                old, target, other = [app / 'releases' / name for name in ('old1234', 'new1234', 'other123')]
                for path in (old, target, other):
                    path.mkdir(); (path / 'RELEASE').write_text(path.name)
                (app / 'current').symlink_to(other if changed else target)
                (etc / 'release.env').write_text('APP_VERSION=new1234\n')
                state = root / 'transaction'
                state.write_text(f'{old}\nold1234\n{target}\n')
                fakebin = root / 'bin'; fakebin.mkdir()
                commands = {
                    'chown': '#!/bin/bash\nexit 0\n',
                    'systemctl': '#!/bin/bash\nprintf "%s\\n" "$*" >> "$TEST_LOG"\n',
                    'mv': '#!/usr/bin/env python3\nimport os,sys\nos.replace(sys.argv[-2],sys.argv[-1])\n',
                    'ln': '#!/usr/bin/env python3\nimport os,sys\np=sys.argv[-1]\nif os.path.lexists(p): os.unlink(p)\nos.symlink(sys.argv[-2],p)\n',
                }
                for name, body in commands.items():
                    file = fakebin / name; file.write_text(body); file.chmod(0o755)
                script = root / 'recover.sh'
                script.write_text(SCRIPT.read_text().replace('/opt/lingotrip', str(app)).replace('/etc/lingotrip', str(etc)).replace('/run/lingotrip-release-transaction', str(state)))
                result = subprocess.run(['bash', str(script)], env={**os.environ, 'PATH': str(fakebin) + ':' + os.environ['PATH'], 'TEST_LOG': str(root / 'calls')}, capture_output=True)
                if changed:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual((app / 'current').resolve(), other)
                    self.assertTrue(state.exists())
                    self.assertFalse((root / 'calls').exists())
                else:
                    self.assertEqual(result.returncode, 0, result.stderr.decode())
                    self.assertEqual((app / 'current').resolve(), old)
                    self.assertEqual((etc / 'release.env').read_text(), 'APP_VERSION=old1234\n')
                    self.assertFalse(state.exists())
                    self.assertIn('restart --no-block', (root / 'calls').read_text())

if __name__ == '__main__':
    unittest.main()
