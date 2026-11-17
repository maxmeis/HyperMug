"""Production version selection and artifact metadata regression tests."""
import hashlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from release_metadata import next_version, render_cask

ROOT = Path(__file__).resolve().parents[1]
SHA = 'a' * 40
OTHER = 'b' * 40


class ReleasePipelineTests(unittest.TestCase):
    def test_version_is_reserved_by_run_number_even_when_queue_order_reverses(self):
        tags = [('v0.3.0', OTHER), ('v0.3.2', OTHER),
                ('v0.0.0-canary.200', OTHER)]
        self.assertEqual(next_version(tags, SHA, 1), ('0.3.1', False))
        self.assertEqual(next_version(tags, SHA, 3), ('0.3.3', False))
        self.assertEqual(next_version([], SHA, 1), ('0.3.1', False))

    def test_rerun_uses_the_version_of_the_same_source_commit(self):
        tags = [('v0.3.3', SHA), ('v0.3.4', OTHER)]
        self.assertEqual(next_version(tags, SHA, 3), ('0.3.3', True))
        with self.assertRaises(ValueError):
            next_version([('v0.3.3', OTHER)], SHA, 3)
        with self.assertRaises(ValueError):
            next_version([], 'not a sha', 1)
        with self.assertRaises(ValueError):
            next_version([], SHA, 0)

    def test_cask_uses_exact_archive_digest_and_no_in_app_update_claim(self):
        with tempfile.TemporaryDirectory() as folder:
            archive = Path(folder) / 'HyperMug-1.2.3.zip'
            archive.write_bytes(b'final notarized app archive')
            cask = Path(folder) / 'hypermug.rb'
            result = subprocess.run([sys.executable, str(ROOT / 'helpers/release_metadata.py'),
                'cask', '--version', '1.2.3', '--zip', str(archive), '--output', str(cask)],
                capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            digest = hashlib.sha256(archive.read_bytes()).hexdigest()
            self.assertEqual(cask.read_text(), render_cask('1.2.3', digest))
            self.assertIn(f'sha256 "{digest}"', cask.read_text())
            self.assertNotIn('auto_updates', cask.read_text())
            self.assertIn('conflicts_with cask: "hypermug@canary"', cask.read_text())

    def test_malformed_version_cannot_enter_cask_or_release(self):
        for bad in ('1.2', '01.2.3', '1.2.3-rc.1', '1.2.3;echo bad'):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                render_cask(bad, 'a' * 64)

    def test_release_requires_credentials_before_build(self):
        env = {'VERSION': '1.2.3', 'GITHUB_SHA': SHA,
               'GITHUB_REPOSITORY': 'maxmeis/hypermug'}
        # A missing Developer ID is an early failure, before any app build.
        import os
        values = os.environ.copy()
        for key in ('SIGN_ID', 'DEVELOPER_ID_P12_BASE64', 'DEVELOPER_ID_P12_PASSWORD', 'APPLE_TEAM_ID'):
            values.pop(key, None)
        values.update(env)
        result = subprocess.run(['bash', str(ROOT / 'helpers/release.sh')], env=values,
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('SIGN_ID', result.stderr)


class SignedReleaseIntegrationTests(unittest.TestCase):
    """The release wrapper must publish only an Accepted notarized bundle."""
    def setUp(self):
        import os, shutil
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.project = Path(self.temp.name) / 'project'
        helpers = self.project / 'helpers'
        helpers.mkdir(parents=True)
        for name in ('release.sh', 'release_metadata.py', 'notary_auth.sh'):
            shutil.copy2(ROOT / 'helpers' / name, helpers / name)
        (helpers / 'check-bundle-schema.py').write_text('pass\n')
        subprocess.run(['git', 'init', '-q', str(self.project)], check=True)
        (self.project / 'README').write_text('fixture')
        subprocess.run(['git', '-C', str(self.project), 'add', 'README'], check=True)
        subprocess.run(['git', '-C', str(self.project), '-c', 'user.name=Test',
                        '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'fixture'], check=True)
        self.sha = subprocess.check_output(['git', '-C', str(self.project), 'rev-parse', 'HEAD'], text=True).strip()
        self.bin = Path(self.temp.name) / 'bin'
        self.bin.mkdir()
        self.log = Path(self.temp.name) / 'calls'
        fixtures = {
            'security': '''
if [[ "$1" == list-keychains && "${4:-}" != -s ]]; then echo '"/tmp/login.keychain-db"'; fi
if [[ "$1" == find-identity ]]; then echo '  1) FAKE "Developer ID Application: Example"'; fi
''',
            # The production wrapper uses macOS base64 -D; emulate decoding on Linux CI too.
            'base64': "python3 -c 'import base64, sys; sys.stdout.buffer.write(base64.b64decode(sys.stdin.buffer.read()))'",
            'openssl': 'echo fakepassword',
            'make': '''
mkdir -p build/HyperMug.app/Contents
printf plist > build/HyperMug.app/Contents/Info.plist
''',
            'plutil': '''
case "$2" in
  CFBundleShortVersionString|CFBundleVersion) echo 1.2.3;;
  CFBundleIdentifier) echo com.maxmeis.hypermug;;
  *) exit 1;;
esac
''',
            'codesign': 'if [[ "$1" == -dv ]]; then printf "TeamIdentifier=TEAM123\\nCodeDirectory flags=0x10000(runtime)\\nTimestamp=Nov 17, 2026\\n" >&2; fi',
            'spctl': ':',
            'ditto': 'printf "signed and notarized archive" > "${@: -1}"',
            'xcrun': '''
if [[ "$1" == notarytool ]]; then
  echo "{\\"status\\":\\"${NOTARY_STATUS:-Accepted}\\"}"
fi
''',
        }
        for name, body in fixtures.items():
            path = self.bin / name
            path.write_text('#!/usr/bin/env bash\nset -e\necho "' + name + ' $*" >> "$MOCK_LOG"\n' + body)
            path.chmod(0o755)
        self.env = os.environ.copy()
        self.env.update(PATH=f'{self.bin}:{os.environ["PATH"]}', MOCK_LOG=str(self.log),
                        VERSION='1.2.3', GITHUB_SHA=self.sha, GITHUB_REPOSITORY='maxmeis/hypermug',
                        SIGN_ID='Developer ID Application: Example', DEVELOPER_ID_P12_BASE64='YQ==',
                        DEVELOPER_ID_P12_PASSWORD='fixture', APPLE_TEAM_ID='TEAM123',
                        APP_STORE_CONNECT_PRIVATE_KEY='fixture-key', APP_STORE_CONNECT_KEY_ID='KEY123',
                        APP_STORE_CONNECT_ISSUER_ID='ISSUER123')

    def run_release(self, status='Accepted'):
        env = dict(self.env, NOTARY_STATUS=status)
        return subprocess.run(['bash', 'helpers/release.sh'], cwd=self.project, env=env,
                              capture_output=True, text=True)

    def test_accepted_notarization_produces_final_archive_and_cleans_keychain(self):
        result = self.run_release()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.log.read_text()
        self.assertLess(calls.index('xcrun notarytool submit'), calls.index('xcrun stapler staple'))
        self.assertLess(calls.index('xcrun stapler validate'), calls.rindex('ditto -c'))
        self.assertIn('security delete-keychain', calls)
        archive = self.project / 'build/release/HyperMug-1.2.3.zip'
        self.assertTrue(archive.is_file())
        self.assertIn(hashlib.sha256(archive.read_bytes()).hexdigest(),
                      (self.project / 'build/release/hypermug.rb').read_text())

    def test_rejected_notarization_never_publishes_archive_and_cleans_keychain(self):
        result = self.run_release('Invalid')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Notarization was not accepted', result.stderr)
        self.assertNotIn('xcrun stapler staple', self.log.read_text())
        self.assertIn('security delete-keychain', self.log.read_text())
        self.assertFalse((self.project / 'build/release/HyperMug-1.2.3.zip').exists())


if __name__ == '__main__':
    unittest.main()
