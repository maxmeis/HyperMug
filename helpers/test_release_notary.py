import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "helpers" / "notary_auth.sh"


class ReleaseNotaryAuthTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.work = Path(self.temp_dir.name) / "work"
        self.work.mkdir()
        self.bin_dir = Path(self.temp_dir.name) / "bin"
        self.bin_dir.mkdir()
        self.capture = Path(self.temp_dir.name) / "notary.json"
        fake_xcrun = self.bin_dir / "xcrun"
        fake_xcrun.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, pathlib, sys\n"
            "args = sys.argv[1:]\n"
            "key = pathlib.Path(args[args.index('--key') + 1]).read_text() if '--key' in args else None\n"
            "pathlib.Path(os.environ['NOTARY_CAPTURE']).write_text(json.dumps({'args': args, 'key': key}))\n"
        )
        fake_xcrun.chmod(0o755)

    def tearDown(self):
        self.temp_dir.cleanup()

    def invoke(self, variables):
        env = os.environ.copy()
        for name in (
            "APP_STORE_CONNECT_PRIVATE_KEY", "APP_STORE_CONNECT_KEY_ID",
            "APP_STORE_CONNECT_ISSUER_ID", "APPLE_ID",
            "APPLE_APP_SPECIFIC_PASSWORD", "APPLE_TEAM_ID",
        ):
            env.pop(name, None)
        env.update(variables)
        env["PATH"] = f"{self.bin_dir}:{env['PATH']}"
        env["NOTARY_CAPTURE"] = str(self.capture)
        return subprocess.run(
            [
                "bash",
                "-c",
                'umask 077 && source "$1" && configure_notary_auth "$2" && submit_for_notarization "$3"',
                "notary-test",
                str(HELPER),
                str(self.work),
                "artifact.zip",
            ],
            env=env,
            capture_output=True,
            text=True,
        )

    def test_api_key_is_preferred_and_written_to_ephemeral_file(self):
        result = self.invoke(
            {
                "APP_STORE_CONNECT_PRIVATE_KEY": "test-only-p8-key\n",
                "APP_STORE_CONNECT_KEY_ID": "TESTKEY123",
                "APP_STORE_CONNECT_ISSUER_ID": "test-issuer-uuid",
                "APPLE_ID": "fallback@example.test",
                "APPLE_APP_SPECIFIC_PASSWORD": "fallback-password",
                "APPLE_TEAM_ID": "TEAM123",
            }
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        submitted = json.loads(self.capture.read_text())
        self.assertEqual(
            submitted["args"],
            [
                "notarytool",
                "submit",
                "artifact.zip",
                "--key",
                str(self.work / "app-store-connect-key.p8"),
                "--key-id",
                "TESTKEY123",
                "--issuer",
                "test-issuer-uuid",
                "--wait",
            ],
        )
        self.assertEqual(submitted["key"], "test-only-p8-key\n")
        self.assertEqual((self.work / "app-store-connect-key.p8").stat().st_mode & 0o777, 0o600)

    def test_password_auth_remains_available_when_api_values_are_absent(self):
        result = self.invoke(
            {
                "APPLE_ID": "fallback@example.test",
                "APPLE_APP_SPECIFIC_PASSWORD": "fallback-password",
                "APPLE_TEAM_ID": "TEAM123",
            }
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        submitted = json.loads(self.capture.read_text())
        self.assertEqual(
            submitted["args"],
            [
                "notarytool",
                "submit",
                "artifact.zip",
                "--apple-id",
                "fallback@example.test",
                "--password",
                "fallback-password",
                "--team-id",
                "TEAM123",
                "--wait",
            ],
        )
        self.assertIsNone(submitted["key"])

    def test_partial_api_configuration_fails_without_falling_back_or_submitting(self):
        result = self.invoke(
            {
                "APP_STORE_CONNECT_PRIVATE_KEY": "test-only-p8-key",
                "APP_STORE_CONNECT_KEY_ID": "TESTKEY123",
                "APPLE_ID": "fallback@example.test",
                "APPLE_APP_SPECIFIC_PASSWORD": "fallback-password",
                "APPLE_TEAM_ID": "TEAM123",
            }
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Incomplete App Store Connect API", result.stderr)
        self.assertFalse(self.capture.exists())

    def test_missing_fallback_configuration_fails_without_submitting(self):
        result = self.invoke({})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing Apple app-specific password", result.stderr)
        self.assertFalse(self.capture.exists())

    def test_keychain_snapshot_failure_stops_before_creating_signing_keychain(self):
        project = Path(self.temp_dir.name) / "project"
        scripts = project / "helpers"
        scripts.mkdir(parents=True)
        for name in ("release.sh", "notary_auth.sh", "release_metadata.py"):
            shutil.copy2(ROOT / "helpers" / name, scripts / name)
        calls = Path(self.temp_dir.name) / "security-calls.jsonl"
        security = self.bin_dir / "security"
        security.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys\n"
            "with open(os.environ['SECURITY_CALLS'], 'a') as f: f.write(json.dumps(sys.argv[1:]) + '\\n')\n"
            "if sys.argv[1] == 'list-keychains':\n"
            "    print('injected keychain snapshot failure', file=sys.stderr)\n"
            "    sys.exit(64)\n"
        )
        security.chmod(0o755)
        env = os.environ.copy()
        env.update({
            "PATH": f"{self.bin_dir}:{env['PATH']}", "SECURITY_CALLS": str(calls),
            "CHANNEL": "stable", "VERSION": "1.2.3", "BUILD_NUMBER": "1.2.3",
            "SOURCE_REPOSITORY": "maxmeis/HyperMug", "RELEASES_REPOSITORY": "maxmeis/HyperMug",
            "TAP_REPOSITORY": "maxmeis/homebrew-formulae", "GITHUB_ACTOR": "maxmeis",
            "GITHUB_TRIGGERING_ACTOR": "maxmeis", "GITHUB_REF": "refs/tags/v1.2.3",
            "GITHUB_SHA": "a" * 40, "DEVELOPER_ID_P12_BASE64": "ZmFrZQ==",
            "DEVELOPER_ID_P12_PASSWORD": "test-only", "SIGN_ID": "test-only",
            "SPARKLE_EDDSA_PRIVATE_KEY": "test-only", "RUNNER_TEMP": str(self.work),
            "APP_STORE_CONNECT_PRIVATE_KEY": "test-only", "APP_STORE_CONNECT_KEY_ID": "test-only",
            "APP_STORE_CONNECT_ISSUER_ID": "test-only",
        })
        result = subprocess.run(["bash", str(scripts / "release.sh")], env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("injected keychain snapshot failure", result.stderr)
        invocations = [json.loads(line) for line in calls.read_text().splitlines()]
        self.assertEqual(invocations[0], ["list-keychains", "-d", "user"])
        self.assertFalse(any(args[0] == "create-keychain" for args in invocations))
        self.assertEqual(invocations[-1][0], "delete-keychain")
        self.assertFalse(Path(invocations[-1][1]).parent.exists(), "Temporary signing data must be removed")


if __name__ == "__main__":
    unittest.main()
