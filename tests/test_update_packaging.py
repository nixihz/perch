"""验证发布元数据与配置失败路径，不访问网络或钥匙串。"""
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("configure_updates", ROOT / "script/configure_updates.py")
updates = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(updates)
PUBLIC_KEY = "11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo="


class UpdatePackagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.config_path = Path(self.temp.name) / "updates.json"
        self.plist_path = Path(self.temp.name) / "Info.plist"
        self.config = {"version": "1.2.3", "build": "42", "feedURL": "", "publicEDKey": ""}
        self.plist_path.write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "com.brian.skillset", "CFBundleExecutable": "SkillSet",
            "SUFeedURL": "https://old.example.com/appcast.xml", "SUPublicEDKey": "old-key",
        }))

    def load(self, config=None, environ=None):
        self.config_path.write_text(json.dumps(self.config if config is None else config))
        return updates.load_configuration(self.config_path, {} if environ is None else environ)

    def test_unconfigured_bundle_removes_stale_feed_and_preserves_identity(self):
        updates.apply_configuration(self.plist_path, self.load())
        result = plistlib.loads(self.plist_path.read_bytes())
        self.assertEqual(result["CFBundleIdentifier"], "com.brian.skillset")
        self.assertEqual(result["CFBundleExecutable"], "SkillSet")
        self.assertEqual(result["CFBundleShortVersionString"], "1.2.3")
        self.assertEqual(result["CFBundleVersion"], "42")
        self.assertNotIn("SUFeedURL", result)
        self.assertNotIn("SUPublicEDKey", result)
        self.assertFalse(result["SUAutomaticallyUpdate"])
        self.assertFalse(result["SUAllowsAutomaticUpdates"])
        self.assertTrue(result["SUVerifyUpdateBeforeExtraction"])

    def test_environment_overrides_embed_feed_and_public_key(self):
        config = self.load(environ={
            "PERCH_VERSION": "2.0.0", "PERCH_BUILD_NUMBER": "43",
            "PERCH_SPARKLE_FEED_URL": "https://updates.example.com/perch/appcast.xml",
            "PERCH_SPARKLE_PUBLIC_KEY": PUBLIC_KEY,
        })
        updates.apply_configuration(self.plist_path, config)
        result = plistlib.loads(self.plist_path.read_bytes())
        self.assertEqual(result["CFBundleShortVersionString"], "2.0.0")
        self.assertEqual(result["CFBundleVersion"], "43")
        self.assertEqual(result["SUFeedURL"], "https://updates.example.com/perch/appcast.xml")
        self.assertEqual(result["SUPublicEDKey"], PUBLIC_KEY)

    def test_partial_unsafe_or_malformed_configuration_is_rejected(self):
        invalid = [
            {"feedURL": "https://example.com/appcast.xml"}, {"publicEDKey": PUBLIC_KEY},
            {"version": "1.0"}, {"version": "1.0.0-preview"}, {"build": "0"}, {"build": "-1"}, {"build": 42},
        ]
        for feed in ["http://example.com/a.xml", "https:///", "file:///tmp/a.xml",
                     "https://user:secret@example.com/a.xml", "https://example.com/a.xml#fragment",
                     "https://example.com/app cast.xml", "https://$(HOST)/a.xml"]:
            invalid.append({"feedURL": feed, "publicEDKey": PUBLIC_KEY})
        for key in ["YWJj", "not-base64", PUBLIC_KEY + "!"]:
            invalid.append({"feedURL": "https://example.com/a.xml", "publicEDKey": key})
        for overrides in invalid:
            with self.subTest(overrides=overrides), self.assertRaises(ValueError):
                self.load(self.config | overrides)

    def test_invalid_cli_configuration_leaves_existing_plist_unchanged(self):
        original = self.plist_path.read_bytes()
        self.config_path.write_text(json.dumps(self.config | {"build": "0"}))
        result = subprocess.run([
            "python3", str(ROOT / "script/configure_updates.py"), "--config", str(self.config_path),
            "--plist", str(self.plist_path),
        ], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("构建号", result.stderr)
        self.assertEqual(self.plist_path.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
