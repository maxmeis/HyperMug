"""Run the inline secret-free Stable owner gate against forged API responses."""
import copy
import json
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest

WORKFLOW = Path(__file__).resolve().parents[1] / '.github/workflows/release-stable.yml'


def authorization_script():
    block = WORKFLOW.read_text().split('      - name: Authorize owner dispatch and rerun identity\n', 1)[1]
    block = block.split('      - name: Validate tag and source\n', 1)[0]
    return textwrap.dedent(block.split('        run: |\n', 1)[1])


class StableAuthorizationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        gh = self.bin / 'gh'
        gh.write_text('#!/bin/sh\ntest "$1" = api && test "$2" = repos/maxmeis/hypermug/actions/runs/42 || exit 3\ncat "$RUN_JSON"\n')
        gh.chmod(0o755)
        self.run_json = self.root / 'run.json'
        self.run = dict(id=42, repository=dict(id=1455862604, full_name='maxmeis/hypermug', owner=dict(id=41482988)),
                        head_repository=dict(id=1455862604), actor=dict(id=41482988),
                        triggering_actor=dict(id=41482988), event='workflow_dispatch',
                        path='.github/workflows/release-stable.yml', head_branch='main',
                        head_sha='a' * 40, run_attempt=1)
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                        RUN_JSON=str(self.run_json), RUNNER_TEMP=str(self.root),
                        GITHUB_REPOSITORY='maxmeis/hypermug', GITHUB_REPOSITORY_ID='1455862604',
                        GITHUB_ACTOR_ID='41482988', GITHUB_REF='refs/heads/main',
                        GITHUB_RUN_ID='42', GITHUB_RUN_ATTEMPT='1', GITHUB_SHA='a' * 40)

    def check(self, **env):
        self.run_json.write_text(json.dumps(self.run))
        return subprocess.run(['/bin/bash', '-c', authorization_script()],
                              env=dict(self.env, **env), capture_output=True, text=True)

    def test_exact_owner_dispatch_passes_without_secrets(self):
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_wrong_numeric_actor_or_rerunner_is_rejected(self):
        for field in ('actor', 'triggering_actor'):
            with self.subTest(field=field):
                original = copy.deepcopy(self.run[field]); self.run[field]['id'] = 999
                self.assertNotEqual(self.check().returncode, 0)
                self.run[field] = original
        self.assertNotEqual(self.check(GITHUB_ACTOR_ID='999').returncode, 0)

    def test_wrong_repository_or_workflow_run_is_rejected(self):
        changes = [('repository', 'id', 1), ('repository', 'full_name', 'other/repo'),
                   ('head_repository', 'id', 1), ('repository', 'owner', {'id': 999})]
        for section, key, value in changes:
            with self.subTest(section=section, key=key):
                original = copy.deepcopy(self.run[section][key]); self.run[section][key] = value
                self.assertNotEqual(self.check().returncode, 0)
                self.run[section][key] = original
        for field, value in [('id', 41), ('event', 'push'), ('path', '.github/workflows/other.yml'),
                             ('head_branch', 'other'), ('head_sha', 'b' * 40), ('run_attempt', 2)]:
            with self.subTest(field=field):
                original = self.run[field]; self.run[field] = value
                self.assertNotEqual(self.check().returncode, 0)
                self.run[field] = original
        self.assertNotEqual(self.check(GITHUB_REPOSITORY_ID='1').returncode, 0)

    def test_api_failure_rejects_dispatch(self):
        (self.bin / 'gh').write_text('#!/bin/sh\nexit 9\n')
        self.assertNotEqual(self.check().returncode, 0)


if __name__ == '__main__':
    unittest.main()
