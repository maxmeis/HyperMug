import hashlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from release_metadata import appcast, asset_url, bundle_identity, cask, validate, stable_order, canary_superseded, release_order, publication_decision

SHA = 'a' * 40
ARGS = ('maxmeis', 'maxmeis', 'refs/tags/v1.2.3', SHA, 'maxmeis/hypermug', 'maxmeis/hypermug', 'maxmeis/homebrew-formulae')


class ReleaseMetadataTests(unittest.TestCase):
    def test_stable_authorization_and_semver(self):
        validate('stable', '1.2.3', *ARGS)
        for version in ('1.2', '01.2.3', '1.2.3-rc1', '1.2.3;echo bad'):
            with self.assertRaises(ValueError):
                validate('stable', version, *ARGS)
        for i in (0, 1):
            args = list(ARGS)
            args[i] = 'other'
            with self.assertRaises(ValueError):
                validate('stable', '1.2.3', *args)
        args = list(ARGS)
        args[2] = 'refs/heads/feature'
        with self.assertRaises(ValueError):
            validate('stable', '1.2.3', *args)

    def test_canary_requires_exact_main_and_its_own_version_namespace(self):
        args = ('contributor', 'contributor', 'refs/heads/main', SHA,
                'maxmeis/hypermug', 'maxmeis/hypermug', 'maxmeis/homebrew-formulae')
        validate('canary', '0.0.0-canary.12', *args)
        for version in ('1.2.3', '0.0.0-canary.0', '0.0.0-beta.12'):
            with self.assertRaises(ValueError):
                validate('canary', version, *args)
        for index, value in ((2, 'refs/heads/feature'), (4, 'fork/hypermug'), (4, 'maxmeis/HyperMug')):
            changed = list(args); changed[index] = value
            with self.assertRaises(ValueError):
                validate('canary', '0.0.0-canary.12', *changed)

    def test_appcast_escapes_and_signs(self):
        url = asset_url('maxmeis/hypermug', 'v1.2.3', 'HyperMug-1.2.3.zip')
        xml = appcast('stable', '1.2.3', 123, url + '?x="&', 'abc+/=', 17)
        self.assertIn('sparkle:edSignature="abc+/="', xml)
        self.assertIn('<sparkle:shortVersionString>1.2.3</sparkle:shortVersionString>', xml)
        self.assertIn('x=&quot;&amp;', xml)
        self.assertIn('<sparkle:version>123</sparkle:version>', xml)
        stable_xml = appcast('stable', '1.2.3', '1.2.3', url, 'abc+/=', 17)
        self.assertIn('<sparkle:version>1.2.3</sparkle:version>', stable_xml)

    def test_bundle_versions_match_apple_and_canary_feed_identity(self):
        self.assertEqual(bundle_identity('stable', '2.3.4'), ('2.3.4', '2.3.4'))
        self.assertEqual(bundle_identity('canary', '0.0.0-canary.12'), ('0.0.12', '12'))
        short, build = bundle_identity('canary', '0.0.0-canary.12')
        self.assertRegex(short, r'^\d+\.\d+\.\d+$')
        self.assertRegex(build, r'^\d+(?:\.\d+){0,2}$')
        xml = appcast('canary', '0.0.0-canary.12', build, 'https://example.test/zip', 'abc+/=', 17)
        self.assertIn('<sparkle:shortVersionString>0.0.12</sparkle:shortVersionString>', xml)
        self.assertIn('<sparkle:version>12</sparkle:version>', xml)
        self.assertIn('<title>HyperMug 0.0.0-canary.12</title>', xml)

    def test_canary_render_emits_numeric_bundle_matching_feed_and_cask(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / 'HyperMug-0.0.0-canary.12.zip'
            archive.write_bytes(b'signed archive fixture')
            output = Path(directory) / 'output'
            command = [sys.executable, str(Path(__file__).with_name('release_metadata.py')), 'render',
                       '--channel', 'canary', '--version', '0.0.0-canary.12',
                       '--actor', 'maxmeis', '--triggering-actor', 'maxmeis', '--ref', 'refs/heads/main',
                       '--sha', SHA, '--source-repo', 'maxmeis/hypermug',
                       '--releases-repo', 'maxmeis/hypermug', '--tap-repo', 'maxmeis/homebrew-formulae',
                       '--build-number', '12', '--zip', str(archive), '--signature', 'abc+/=',
                       '--output', str(output)]
            subprocess.run(command, check=True, capture_output=True, text=True)
            feed = (output / 'appcast-canary.xml').read_text()
            cask_text = (output / 'hypermug@canary.rb').read_text()
            self.assertIn('<sparkle:shortVersionString>0.0.12</sparkle:shortVersionString>', feed)
            self.assertIn('<sparkle:version>12</sparkle:version>', feed)
            self.assertIn('version "0.0.12"', cask_text)
            self.assertIn('homepage "https://github.com/maxmeis/hypermug"', cask_text)
            self.assertIn('/releases/download/v0.0.0-canary.12/', feed)
            wrong = command.copy()
            wrong[wrong.index('--build-number') + 1] = '13'
            self.assertNotEqual(subprocess.run(wrong, capture_output=True).returncode, 0)

    def test_production_cask_and_order(self):
        digest = hashlib.sha256(b'archive').hexdigest()
        result = cask('stable', '1.2.3', 'https://example.test/file.zip', digest)
        self.assertIn('cask "hypermug"', result)
        self.assertIn('version "1.2.3"', result)
        self.assertIn(f'sha256 "{digest}"', result)
        self.assertEqual(publication_decision('stable', '2.0.1', '2.0.1', '2.0.0', '2.0.0'), 'advance')
        self.assertEqual(publication_decision('stable', '2.0.0', '2.0.0', '2.0.0', '2.0.0'), 'resume')
        self.assertEqual(publication_decision('stable', '1.9.9', '1.9.9', '2.0.0', '2.0.0'), 'archive')

    def test_canary_cask_feed_and_out_of_order_queue(self):
        digest = hashlib.sha256(b'canary archive').hexdigest()
        result = cask('canary', '0.0.0-canary.12', 'https://example.test/canary.zip', digest)
        self.assertIn('cask "hypermug@canary"', result)
        self.assertIn('version "0.0.12"', result)
        self.assertIn('conflicts_with cask: "hypermug"', result)
        self.assertIn('conflicts_with cask: "hypermug@nightly"', result)
        self.assertTrue(canary_superseded('0.0.0-canary.9', ['v0.0.0-canary.10', 'v2.0.0']))
        self.assertFalse(canary_superseded('0.0.0-canary.11', ['v0.0.0-canary.10', 'v2.0.0']))
        release_order('canary', '0.0.0-canary.11', ['v0.0.0-canary.10', 'v2.0.0'])
        with self.assertRaises(ValueError):
            release_order('canary', '0.0.0-canary.9', ['v0.0.0-canary.10'])
        self.assertEqual(publication_decision('canary', '0.0.0-canary.12', '12', '0.0.0-canary.11', '11'), 'advance')
        self.assertEqual(publication_decision('canary', '0.0.0-canary.11', '11', '0.0.0-canary.12', '12'), 'archive')
        self.assertEqual(publication_decision('canary', '0.0.0-canary.13', '1000', '0.0.0-canary.12', '1200'), 'archive')
        self.assertEqual(publication_decision('canary', '0.0.0-canary.12', '12', '0.0.0-canary.12', '12'), 'resume')
        with self.assertRaises(ValueError):
            publication_decision('canary', '0.0.0-canary.12', '1300', '0.0.0-canary.12', '1200')

    def test_stable_downgrade_and_retry(self):
        stable_order('2.1.0', ['v2.0.0', 'v0.0.0-beta.20'])
        stable_order('2.0.0', ['v2.0.0'], retry=True)
        with self.assertRaises(ValueError):
            stable_order('1.9.9', ['v2.0.0'], retry=True)
        with self.assertRaises(ValueError):
            stable_order('2.0.0', ['v2.0.0'])


if __name__ == '__main__':
    unittest.main()
