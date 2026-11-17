"""Adversarial ZIP and native-signature checks for Cask promotion."""
import hashlib
import plistlib
import stat
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

import verify_published_app as subject
from release_metadata import appcast, asset_url


class PublishedAppTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.zip = self.root / "HyperMug-0.0.0-canary.10.zip"
        self.feed = self.root / "appcast-canary.xml"
        self.version = "0.0.0-canary.10"
        self.repo = "maxmeis/hypermug"
        self.info = dict(CFBundleIdentifier="com.maxmeis.hypermug",
                         CFBundleShortVersionString="0.0.10", CFBundleVersion="10",
                         HyperMugReleaseChannel="canary", LSMinimumSystemVersion="14.0",
                         SUPublicEDKey=subject.PUBLIC_KEYS["canary"], CFBundleExecutable="HyperMug")
        self.make_zip()
        self.make_feed()

    def make_zip(self, extra=None):
        with zipfile.ZipFile(self.zip, "w") as archive:
            archive.writestr("HyperMug.app/", b"")
            archive.writestr("HyperMug.app/Contents/Info.plist", plistlib.dumps(self.info))
            executable = zipfile.ZipInfo("HyperMug.app/Contents/MacOS/HyperMug")
            executable.external_attr = (stat.S_IFREG | 0o755) << 16
            archive.writestr(executable, b"binary")
            if extra:
                for name, data, mode in extra:
                    entry = zipfile.ZipInfo(name)
                    entry.external_attr = mode << 16
                    archive.writestr(entry, data)

    def make_feed(self, url=None, length=None, signature=None):
        self.feed.write_text(appcast("canary", self.version, "10",
            url or asset_url(self.repo, "v" + self.version, self.zip.name),
            signature or ("A" * 86 + "=="), length or self.zip.stat().st_size))

    def verify(self):
        details = ("Authority=Developer ID Application: Max Meissgeier (S5R3X22G84)\n"
                   "CodeDirectory v=20500 flags=0x10000(runtime)\n"
                   "TeamIdentifier=S5R3X22G84\nTimestamp=Nov 17, 2026\n")
        def native(command, **kwargs):
            if command[0] == "codesign" and "-dv" in command:
                return subprocess.CompletedProcess(command, 0, "", details)
            return subprocess.CompletedProcess(command, 0)
        with patch.object(subject.subprocess, "check_output", return_value="arm64"), \
             patch.object(subject.subprocess, "run", side_effect=native) as calls:
            subject.verify(self.zip, self.feed, self.repo, "canary", self.version,
                           hashlib.sha256(self.zip.read_bytes()).hexdigest(), self.root / "work")
        return calls

    def test_valid_archive_preserves_sparkle_symlink_and_verifies_native_tools(self):
        self.make_zip([("HyperMug.app/Contents/Frameworks/Sparkle.framework/Versions/Current", b"B", stat.S_IFLNK | 0o777),
                       ("HyperMug.app/Contents/Frameworks/Sparkle.framework/Versions/B/Info.plist", b"data", stat.S_IFREG | 0o644)])
        self.make_feed()
        calls = self.verify()
        link = self.root / "work/extracted/HyperMug.app/Contents/Frameworks/Sparkle.framework/Versions/Current"
        self.assertTrue(link.is_symlink())
        commands = [call.args[0][0] for call in calls.call_args_list]
        self.assertEqual(commands, ["codesign", "codesign", "xcrun", "spctl", "swift"])

    def test_unsafe_zip_paths_and_links_fail_before_extraction(self):
        for name, data, mode in [
            ("../escape", b"bad", stat.S_IFREG | 0o644),
            ("/absolute", b"bad", stat.S_IFREG | 0o644),
            ("HyperMug.app/link", b"../../escape", stat.S_IFLNK | 0o777),
            ("HyperMug.app/link", b"/tmp/escape", stat.S_IFLNK | 0o777),
        ]:
            with self.subTest(name=name, data=data):
                self.make_zip([(name, data, mode)])
                with self.assertRaises(ValueError):
                    subject.extract_safe(self.zip, self.root / "extracted")
                self.assertFalse((self.root / "extracted").exists())
        self.make_zip([("HyperMug.app/Contents/Info.plist", b"duplicate", stat.S_IFREG | 0o644)])
        with self.assertRaisesRegex(ValueError, "duplicate"):
            subject.extract_safe(self.zip, self.root / "extracted")

    def test_chained_symlink_escape_and_symlink_child_fail_before_extraction(self):
        self.make_zip([
            ("HyperMug.app/Contents/link-a", b"link-b", stat.S_IFLNK | 0o777),
            ("HyperMug.app/Contents/link-b", b"../../escape", stat.S_IFLNK | 0o777),
        ])
        with self.assertRaises(ValueError):
            subject.extract_safe(self.zip, self.root / "chain")
        self.assertFalse((self.root / "chain").exists())
        self.make_zip([
            ("HyperMug.app/Contents/link", b"MacOS", stat.S_IFLNK | 0o777),
            ("HyperMug.app/Contents/link/payload", b"bad", stat.S_IFREG | 0o644),
        ])
        with self.assertRaisesRegex(ValueError, "descends through a symlink"):
            subject.extract_safe(self.zip, self.root / "child")
        self.assertFalse((self.root / "child").exists())

    def test_wrong_feed_metadata_fails_before_native_checks(self):
        self.make_feed(url="https://example.invalid/other.zip")
        with self.assertRaisesRegex(ValueError, "appcast archive identity"):
            self.verify()
        self.make_feed(length=123)
        with self.assertRaisesRegex(ValueError, "appcast archive identity"):
            self.verify()

    def test_wrong_archive_digest_fails_before_extraction(self):
        with self.assertRaisesRegex(ValueError, "digest"):
            subject.verify(self.zip, self.feed, self.repo, "canary", self.version,
                           "0" * 64, self.root / "digest-work")
        self.assertFalse((self.root / "digest-work").exists())

    def test_wrong_sparkle_signature_blocks_verification(self):
        details = ("Authority=Developer ID Application: Max Meissgeier (S5R3X22G84)\n"
                   "CodeDirectory v=20500 flags=0x10000(runtime)\n"
                   "TeamIdentifier=S5R3X22G84\nTimestamp=Nov 17, 2026\n")
        def native(command, **kwargs):
            if command[0] == "swift":
                raise subprocess.CalledProcessError(1, command)
            if command[0] == "codesign" and "-dv" in command:
                return subprocess.CompletedProcess(command, 0, "", details)
            return subprocess.CompletedProcess(command, 0)
        with patch.object(subject.subprocess, "check_output", return_value="arm64"), \
             patch.object(subject.subprocess, "run", side_effect=native):
            with self.assertRaises(subprocess.CalledProcessError):
                subject.verify(self.zip, self.feed, self.repo, "canary", self.version,
                               hashlib.sha256(self.zip.read_bytes()).hexdigest(), self.root / "bad-signature")

    def test_wrong_bundle_team_or_unsigned_app_fails(self):
        self.info["SUPublicEDKey"] = subject.PUBLIC_KEYS["stable"]
        self.make_zip(); self.make_feed()
        with self.assertRaisesRegex(ValueError, "bundle identity"):
            self.verify()
        self.info["SUPublicEDKey"] = subject.PUBLIC_KEYS["canary"]
        self.make_zip(); self.make_feed()
        original = subject.subprocess.run
        with patch.object(subject.subprocess, "check_output", return_value="arm64"), \
             patch.object(subject.subprocess, "run", side_effect=lambda args, **kw: subprocess.CompletedProcess(args, 0, "", "TeamIdentifier=OTHER")):
            with self.assertRaisesRegex(ValueError, "Developer ID"):
                subject.verify(self.zip, self.feed, self.repo, "canary", self.version,
                               hashlib.sha256(self.zip.read_bytes()).hexdigest(), self.root / "wrong-team")
        with patch.object(subject.subprocess, "check_output", return_value="arm64"), \
             patch.object(subject.subprocess, "run", side_effect=lambda args, **kw: (_ for _ in ()).throw(subprocess.CalledProcessError(1, args))):
            with self.assertRaises(subprocess.CalledProcessError):
                subject.verify(self.zip, self.feed, self.repo, "canary", self.version,
                               hashlib.sha256(self.zip.read_bytes()).hexdigest(), self.root / "unsigned")


if __name__ == "__main__":
    unittest.main()
