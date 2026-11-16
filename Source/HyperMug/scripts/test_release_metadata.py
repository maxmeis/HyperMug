import hashlib
import unittest
from release_metadata import appcast, asset_url, cask, validate, stable_order, publication_decision

SHA = 'a' * 40
ARGS = ('maxmeis', 'maxmeis', 'refs/tags/v1.2.3', SHA, 'maxmeis/HyperMug', 'maxmeis/HyperMug', 'maxmeis/homebrew-formulae')


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

    def test_appcast_escapes_and_signs(self):
        url = asset_url('maxmeis/HyperMug', 'v1.2.3', 'HyperMug-1.2.3.zip')
        xml = appcast('stable', '1.2.3<&', 123, url + '?x="&', 'abc+/=', 17)
        self.assertIn('sparkle:edSignature="abc+/="', xml)
        self.assertIn('1.2.3&lt;&amp;', xml)
        self.assertIn('x=&quot;&amp;', xml)
        self.assertIn('<sparkle:version>123</sparkle:version>', xml)
        stable_xml = appcast('stable', '1.2.3', '1.2.3', url, 'abc+/=', 17)
        self.assertIn('<sparkle:version>1.2.3</sparkle:version>', stable_xml)

    def test_production_cask_and_order(self):
        digest = hashlib.sha256(b'archive').hexdigest()
        result = cask('stable', '1.2.3', 'https://example.test/file.zip', digest)
        self.assertIn('cask "hypermug"', result)
        self.assertIn('version "1.2.3"', result)
        self.assertIn(f'sha256 "{digest}"', result)
        self.assertEqual(publication_decision('stable', '2.0.1', '2.0.1', '2.0.0', '2.0.0'), 'advance')
        self.assertEqual(publication_decision('stable', '2.0.0', '2.0.0', '2.0.0', '2.0.0'), 'resume')
        self.assertEqual(publication_decision('stable', '1.9.9', '1.9.9', '2.0.0', '2.0.0'), 'archive')

    def test_stable_downgrade_and_retry(self):
        stable_order('2.1.0', ['v2.0.0', 'v0.0.0-beta.20'])
        stable_order('2.0.0', ['v2.0.0'], retry=True)
        with self.assertRaises(ValueError):
            stable_order('1.9.9', ['v2.0.0'], retry=True)
        with self.assertRaises(ValueError):
            stable_order('2.0.0', ['v2.0.0'])


if __name__ == '__main__':
    unittest.main()
