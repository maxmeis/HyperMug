"""Publish a release once and update the one-repository cask directly."""
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FAKE_GH = '''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
state_path = Path(os.environ['RELEASE_STATE'])
state = json.loads(state_path.read_text())
args = sys.argv[1:]
def save(): state_path.write_text(json.dumps(state))
if args[0] == 'api':
    if args[1].endswith('/releases/latest'):
        if os.environ.get('FAKE_LATEST_TAG'):
            print(os.environ['FAKE_LATEST_TAG']); sys.exit(0)
        print('HTTP 404', file=sys.stderr); sys.exit(1)
    sys.exit(2)
elif args[:2] == ['release', 'view']:
    if not state['exists']: sys.exit(1)
    field = args[args.index('--jq') + 1] if '--jq' in args else ''
    if field == '.body': print(state['body'])
    elif field == '.isDraft': print(str(state['draft']).lower())
    elif field == '.assets[].name': print(state['asset_name'] if state['asset'] else '')
    else: print('{}')
elif args[:2] == ['release', 'create']:
    if state['exists']: sys.exit(2)
    state['exists'] = True
    state['draft'] = True
    state['body'] = args[args.index('--notes') + 1]
    file = Path(args[3]); state['asset_name'] = file.name; state['asset'] = file.read_bytes().hex()
    state['creates'] += 1; save()
elif args[:2] == ['release', 'download']:
    if not state['exists'] or not state['asset']: sys.exit(3)
    file = Path(args[args.index('--dir') + 1]) / state['asset_name']
    file.write_bytes(bytes.fromhex(state['asset']))
elif args[:2] == ['release', 'edit']:
    state['draft'] = False; state['publishes'] += 1
    state['latest_flag'] = '--latest=false' if '--latest=false' in args else '--latest'
    save()
elif args[:2] == ['release', 'upload']:
    if not state['draft'] or state['asset']: sys.exit(4)
    file = Path(args[3]); state['asset_name'] = file.name; state['asset'] = file.read_bytes().hex(); save()
else: sys.exit('Unsupported gh: ' + repr(args))
'''


class PublishTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        base = Path(self.temp.name)
        self.remote = base / 'remote.git'
        self.repo = base / 'repo'
        subprocess.run(['git', 'init', '--bare', '-q', str(self.remote)], check=True)
        subprocess.run(['git', 'clone', '-q', str(self.remote), str(self.repo)], check=True)
        subprocess.run(['git', '-C', str(self.repo), 'switch', '-qc', 'main'], check=True)
        (self.repo / 'helpers').mkdir()
        for name in ('publish_release.sh', 'release_metadata.py'):
            shutil.copy2(ROOT / 'helpers' / name, self.repo / 'helpers' / name)
        verifier = self.repo / 'helpers/verify_release_archive.sh'
        verifier.write_text('#!/usr/bin/env bash\nexit 0\n')
        verifier.chmod(0o755)
        (self.repo / 'Casks').mkdir()
        (self.repo / 'Casks/hypermug.rb').write_text('cask "hypermug" do\n  version "0.2.0"\nend\n')
        self.git('add', '.')
        self.git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'source')
        self.sha = self.git('rev-parse', 'HEAD').stdout.strip()
        self.git('tag', 'v0.2.1')
        self.git('push', '-q', 'origin', 'main', 'v0.2.1')
        archive = self.repo / 'build/release/HyperMug-0.2.1.zip'
        archive.parent.mkdir(parents=True)
        archive.write_bytes(b'notarized archive 1')
        self.state = base / 'state.json'
        self.state.write_text(json.dumps(dict(exists=False, draft=False, body='', asset_name='',
                                              asset='', creates=0, publishes=0)))
        bin_dir = base / 'bin'
        bin_dir.mkdir()
        gh = bin_dir / 'gh'
        gh.write_text(FAKE_GH)
        gh.chmod(0o755)
        self.env = dict(os.environ, PATH=f'{bin_dir}:{os.environ["PATH"]}',
                        RELEASE_STATE=str(self.state), VERSION='0.2.1', GITHUB_SHA=self.sha,
                        GITHUB_REPOSITORY='maxmeis/hypermug', GH_TOKEN='fixture-token',
                        APPLE_TEAM_ID='TEAM123')

    def git(self, *args):
        result = subprocess.run(['git', '-C', str(self.repo), *args], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def publish(self):
        return subprocess.run(['bash', 'helpers/publish_release.sh'], cwd=self.repo, env=self.env,
                              capture_output=True, text=True)

    def test_publishes_exact_archive_and_direct_cask_commit_then_rerun_is_idempotent(self):
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        state = json.loads(self.state.read_text())
        self.assertEqual((state['creates'], state['publishes']), (1, 1))
        cask = self.git('show', 'origin/main:Casks/hypermug.rb').stdout
        self.assertIn('version "0.2.1"', cask)
        self.assertIn('sha256 "', cask)
        self.assertEqual(self.git('rev-list', '--count', self.sha + '..origin/main').stdout.strip(), '1')
        # A retry must use the already-published immutable asset even after a rebuild.
        (self.repo / 'build/release/HyperMug-0.2.1.zip').write_bytes(b'different rebuild')
        retry = self.publish()
        self.assertEqual(retry.returncode, 0, retry.stderr)
        self.assertEqual(json.loads(self.state.read_text())['creates'], 1)
        self.assertEqual(self.git('rev-list', '--count', self.sha + '..origin/main').stdout.strip(), '1')

    def test_existing_release_for_other_source_is_rejected(self):
        state = json.loads(self.state.read_text())
        state.update(exists=True, body='HyperMug 0.2.1; source ' + 'f' * 40)
        self.state.write_text(json.dumps(state))
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('different source', result.stderr)
        self.assertEqual(self.git('rev-parse', 'origin/main').stdout.strip(), self.sha)

    def test_older_draft_does_not_replace_newer_latest_release(self):
        state = json.loads(self.state.read_text())
        state.update(exists=True, draft=True, body=f'HyperMug 0.2.1; source {self.sha}',
                     asset_name='HyperMug-0.2.1.zip', asset=b'original archive'.hex())
        self.state.write_text(json.dumps(state))
        self.env['FAKE_LATEST_TAG'] = 'v0.2.2'
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.state.read_text())['latest_flag'], '--latest=false')


if __name__ == '__main__':
    unittest.main()
