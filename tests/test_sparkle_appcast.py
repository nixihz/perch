"""检查发布清单的版本、签名和下载包绑定，拒绝错包与网页回退。"""
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "script"))
SPEC = importlib.util.spec_from_file_location("prepare_sparkle_update", ROOT / "script/prepare_sparkle_update.py")
updates = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(updates)


class SparkleAppcastTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.archive = self.root / "Perch-0.0.1-2-universal.dmg"
        self.archive.write_bytes(b"fixture DMG bytes")
        self.path = self.root / "appcast.xml"
        self.config = {"version": "0.0.1", "build": "2",
                       "feedURL": "https://perch.keli.tech/updates/macos/appcast.xml", "publicEDKey": "fixture-key"}
        self.xml = '''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
          <sparkle:version>2</sparkle:version><sparkle:shortVersionString>0.0.1</sparkle:shortVersionString>
          <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
          <enclosure url="https://perch.keli.tech/updates/macos/Perch-0.0.1-2-universal.dmg"
          length="17" sparkle:edSignature="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="/>
        </item></channel></rss>'''

    def validate(self, text):
        self.path.write_text(text)
        return updates.validate_appcast(self.path, self.config, self.archive)

    def test_valid_metadata_is_bound_to_actual_archive_length(self):
        signature = self.validate(self.xml)
        self.assertEqual(len(signature), 88)
        self.archive.write_bytes(b"modified archive")
        with self.assertRaisesRegex(ValueError, "长度"):
            self.validate(self.xml)

    def test_wrong_release_url_version_system_or_signature_is_rejected(self):
        mutations = [
            ("https://perch.keli.tech/updates/macos/Perch", "https://other.example/Perch"),
            ("length=\"17\"", "length=\"999\""),
            ("<sparkle:version>2<", "<sparkle:version>1<"),
            ("<sparkle:shortVersionString>0.0.1<", "<sparkle:shortVersionString>0.0.2<"),
            ("<sparkle:minimumSystemVersion>14.0<", "<sparkle:minimumSystemVersion>15.0<"),
            ("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==", "bad-signature"),
        ]
        for before, after in mutations:
            with self.subTest(before=before), self.assertRaises(ValueError):
                self.validate(self.xml.replace(before, after))

    def test_html_fallback_missing_enclosure_and_multiple_releases_are_rejected(self):
        for text in ["<html><body>website fallback</body></html>", "<rss><channel><item/></channel></rss>",
                     self.xml.replace("</item>", "</item><item/>"), "<!doctype html><html>"]:
            with self.subTest(text=text), self.assertRaises((ValueError, ET.ParseError)):
                self.validate(text)

    def test_client_metadata_must_match_release_and_require_verification(self):
        info = {"CFBundleIdentifier": "com.xiezhixin.perch", "CFBundleShortVersionString": "0.0.1",
                "CFBundleVersion": "2", "SUFeedURL": self.config["feedURL"], "SUPublicEDKey": "fixture-key",
                "SUVerifyUpdateBeforeExtraction": True, "SUAllowsAutomaticUpdates": False}
        updates.validate_info(info, self.config)
        for field in info:
            with self.subTest(field=field), self.assertRaises(ValueError):
                updates.validate_info(info | {field: None}, self.config)


if __name__ == "__main__":
    unittest.main()
