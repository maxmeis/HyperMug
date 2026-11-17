"""Exercise trusted release automation with the pinned shared signing wrapper."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SharedReleaseIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="hypermug-shared-signing-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.automation = self.root / "automation"
        self.source = self.root / "old-source"
        for project in (self.automation, self.source):
            (project / "helpers").mkdir(parents=True)
        for name in ("release.sh", "release_metadata.py"):
            shutil.copy2(ROOT / "helpers" / name, self.automation / "helpers" / name)
        (self.automation / "helpers/check-bundle-schema.py").write_text("pass\n")
        (self.source / "helpers/release.sh").write_text("exit 99\n")
        shutil.copy2(ROOT / "helpers/sparkle.sh", self.source / "helpers/sparkle.sh")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "calls"
        scripts = {
            "security": '''
if [[ "$1" == list-keychains ]]; then
  if [[ "${4:-}" == -s ]]; then shift 4; printf '%s\\n' "$@" > "$KEYCHAIN_STATE"
  elif [[ -f "$KEYCHAIN_STATE" ]]; then while IFS= read -r path; do printf '"%s"\\n' "$path"; done < "$KEYCHAIN_STATE"
  else printf '"/tmp/login.keychain-db"\\n'; fi
fi
if [[ "$1" == find-identity ]]; then echo 'Developer ID Application: Example'; fi
''',
            "openssl": "echo randompassword",
            "xcrun": '''
if [[ "$1" == notarytool && "$2" == submit ]]; then echo '{"status":"Accepted","id":"sample"}'; fi
''',
            "codesign": '''
if [[ "$1" == -dv ]]; then printf 'Authority=Developer ID Application: Example\\nCodeDirectory v=20500 flags=0x10000(runtime)\\nTeamIdentifier=TEAM\\nTimestamp=Nov 17, 2026\\n'; fi
''',
            "ditto": 'printf "archive" > "${@: -1}"',
            "plutil": '''
case "$2" in CFBundleShortVersionString) echo 1.2.3;; CFBundleVersion) echo 1.2.3;; HyperMugReleaseChannel) echo stable;; *) exit 1;; esac
''',
            "swift": ":",
            "make": '''
[[ "$1" == -C && "$2" == "$RELEASE_SOURCE_DIR" && "$3" == build ]] || exit 31
mkdir -p "$RELEASE_SOURCE_DIR/build/HyperMug.app/Contents" "$RELEASE_SOURCE_DIR/build/deps/Sparkle-2.10.1/bin"
printf plist > "$RELEASE_SOURCE_DIR/build/HyperMug.app/Contents/Info.plist"
cat > "$RELEASE_SOURCE_DIR/build/deps/Sparkle-2.10.1/bin/sign_update" <<'SIGN'
#!/usr/bin/env bash
echo 'sparkle:edSignature="YWJj"'
SIGN
chmod +x "$RELEASE_SOURCE_DIR/build/deps/Sparkle-2.10.1/bin/sign_update"
''',
        }
        for name, body in scripts.items():
            target = self.bin / name
            target.write_text('#!/usr/bin/env bash\nset -e\necho "' + name + ' $*" >> "$MOCK_LOG"\n' + body + '\n')
            target.chmod(0o755)
        self.signing = os.environ.get("RELEASE_BOT_SIGNING_SCRIPT", "")
        self.env = dict(os.environ,
            PATH=f"{self.bin}:{os.environ['PATH']}", MOCK_LOG=str(self.log),
            KEYCHAIN_STATE=str(self.root / "keychain-state"), RUNNER_TEMP=str(self.root),
            RELEASE_SOURCE_DIR=str(self.source), RELEASE_BOT_SIGNING_SCRIPT=self.signing,
            CHANNEL="stable", VERSION="1.2.3", BUILD_NUMBER="1.2.3",
            SOURCE_REPOSITORY="maxmeis/hypermug", RELEASES_REPOSITORY="maxmeis/hypermug",
            TAP_REPOSITORY="maxmeis/homebrew-formulae", GITHUB_ACTOR="maxmeis",
            GITHUB_TRIGGERING_ACTOR="maxmeis", GITHUB_REF="refs/tags/v1.2.3",
            GITHUB_SHA="a" * 40, DEVELOPER_ID_P12_BASE64="YQ==",
            DEVELOPER_ID_P12_PASSWORD="sample", SIGN_ID="Developer ID Application: Example",
            APPLE_TEAM_ID="TEAM", APP_STORE_CONNECT_PRIVATE_KEY="api-key",
            APP_STORE_CONNECT_KEY_ID="KEY", APP_STORE_CONNECT_ISSUER_ID="ISSUER",
            SPARKLE_EDDSA_PRIVATE_KEY="ed-key", SPARKLE_PUBLIC_ED_KEY="public-key")
        for name in ("APPLE_ID", "APPLE_APP_SPECIFIC_PASSWORD", "NOTARY_API_KEY_BASE64", "NOTARY_KEY_ID", "NOTARY_ISSUER_ID"):
            self.env.pop(name, None)

    def run_release(self, **changes):
        self.assertTrue(self.signing and Path(self.signing).is_file(), "CI must provide pinned shared signing.sh")
        env = dict(self.env, **changes)
        return subprocess.run(["/bin/bash", self.signing, "run", "--", "/bin/bash",
                               str(self.automation / "helpers/release.sh")],
                              env=env, capture_output=True, text=True)

    def test_old_source_uses_trusted_release_script_and_finalizes_after_notary(self):
        result = self.run_release()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.log.read_text()
        self.assertLess(calls.index("make -C"), calls.index("codesign --force"))
        self.assertLess(calls.index("xcrun notarytool submit"), calls.index("xcrun stapler staple"))
        self.assertLess(calls.index("xcrun stapler validate"), calls.index("ditto -c -k --keepParent"))
        self.assertTrue((self.automation / "build/release/HyperMug-1.2.3.zip").is_file())
        self.assertFalse((self.source / "build/release/HyperMug-1.2.3.zip").exists())

    def test_mixed_notary_modes_fail_before_build(self):
        result = self.run_release(APPLE_ID="apple@example.test", APPLE_APP_SPECIFIC_PASSWORD="password")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Mixed notarization modes", result.stderr)
        self.assertFalse(self.log.exists())


if __name__ == "__main__":
    unittest.main()
