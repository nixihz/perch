"""验证发布信任边界与失败不发布；不访问生产钥匙串或线上服务。"""

import argparse
import base64
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "script"))
import mac_release_support as support
import release_macos as release

PUBLIC_KEY = "11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo="
# 公开测试向量只用于临时产物，不读取生产私钥。
SEED = bytes.fromhex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")


class MacReleaseTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name).resolve()

    def test_private_key_source_is_exclusive_and_owner_only(self):
        key = self.directory / "sparkle.key"
        key.write_text(base64.b64encode(SEED).decode())
        key.chmod(0o644)
        with self.assertRaisesRegex(ValueError, "0600"):
            support.signer_options(ed_key_file=key)
        key.chmod(0o600)
        self.assertEqual(support.signer_options(ed_key_file=key), ["--ed-key-file", str(key.resolve())])
        with self.assertRaisesRegex(ValueError, "只能选择一个"):
            support.signer_options("account", key)
        link = self.directory / "key-link"
        link.symlink_to(key)
        with self.assertRaises(ValueError):
            support.signer_options(ed_key_file=link)

    @unittest.skipUnless(shutil.which("openssl"), "需要 OpenSSL Ed25519 支持")
    def test_public_key_verifies_real_signature_and_rejects_changed_archive(self):
        archive = self.directory / "archive.bin"
        archive.write_bytes(b"release content")
        private = self.directory / "private.der"
        private.write_bytes(bytes.fromhex("302e020100300506032b657004220420") + SEED)
        private.chmod(0o600)
        signature_path = self.directory / "signature"
        subprocess.run(["openssl", "pkeyutl", "-sign", "-inkey", str(private), "-keyform", "DER",
                        "-rawin", "-in", str(archive), "-out", str(signature_path)], check=True,
                       capture_output=True)
        signature = base64.b64encode(signature_path.read_bytes()).decode()
        support.verify_signature(archive, signature, PUBLIC_KEY)
        archive.write_bytes(b"tampered release")
        with self.assertRaisesRegex(ValueError, "客户端公钥验签"):
            support.verify_signature(archive, signature, PUBLIC_KEY)

    @unittest.skipUnless((ROOT / ".build/artifacts/sparkle/Sparkle/bin/sign_update").exists(),
                         "需要已解析的官方 Sparkle 工具")
    def test_official_sparkle_file_signer_must_match_client_public_key(self):
        key = self.directory / "sparkle.key"
        key.write_text(base64.b64encode(SEED).decode())
        key.chmod(0o600)
        sparkle_bin = ROOT / ".build/artifacts/sparkle/Sparkle/bin"
        support.check_sparkle(sparkle_bin, PUBLIC_KEY, ed_key_file=key)
        wrong_key = base64.b64encode(b"x" * 32).decode()
        with self.assertRaisesRegex(ValueError, "客户端公钥验签"):
            support.check_sparkle(sparkle_bin, wrong_key, ed_key_file=key)

    def test_signing_error_never_includes_tool_output(self):
        failed = subprocess.CompletedProcess([], 1, b"SECRET PRIVATE KEY", b"SECRET PRIVATE KEY")
        with patch.object(support.subprocess, "run", return_value=failed):
            with self.assertRaises(ValueError) as raised:
                support.capture(["sign_update"], "签名")
        self.assertNotIn("SECRET", str(raised.exception))

    def test_feed_rejects_html_missing_archives_bad_builds_and_credentials(self):
        valid = '''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
        <channel><item><sparkle:version>15</sparkle:version>
        <enclosure url="https://example.com/Perch.dmg"/></item></channel></rss>'''
        self.assertEqual(release.read_feed(valid)["build"], 15)
        for invalid in ("<html/>", valid.replace("15", "abc"), valid.replace("15", "0"),
                        valid.replace("https://", "http://"),
                        valid.replace("example.com", "user:secret@example.com"),
                        valid.replace('<enclosure url="https://example.com/Perch.dmg"/>', "")):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                release.read_feed(invalid)

    def test_old_build_is_rejected_before_credentials_or_build(self):
        config = {"version": "0.0.1", "build": "15", "feedURL": "", "publicEDKey": ""}
        config_path = self.directory / "updates.json"
        config_path.write_text(json.dumps(config))
        args = argparse.Namespace(config=config_path, build="15", version=None)
        with patch.object(release, "online_release", return_value=({"build": 15}, b"")), \
                patch.object(release, "preflight") as preflight, patch.object(release, "run") as run:
            with self.assertRaisesRegex(ValueError, "高于线上"):
                release.prepare_release(args, config)
        preflight.assert_not_called()
        run.assert_not_called()

    def test_platform_package_uses_release_version_in_both_download_links(self):
        sparkle = self.directory / "sparkle"
        sparkle.mkdir()
        (sparkle / "appcast.xml").write_text("<rss/>")
        (sparkle / "Perch-1.2.3-42-universal.dmg").write_bytes(b"DMG")
        with patch.object(release, "run"):
            files = release.stage_platform(self.directory, {"version": "1.2.3", "build": "42"})
        html = (self.directory / "platform/dist/index.html").read_text()
        self.assertEqual(html.count("Perch-1.2.3-42-universal.dmg"), 2)
        self.assertIn("v1.2.3 (42)", html)
        self.assertIn("version: 1.2.3", (self.directory / "platform/apps.yaml").read_text())
        self.assertEqual(len(files), 5)

    def test_modified_platform_file_blocks_publication_before_network_access(self):
        config = {"version": "0.0.1", "build": "16", "feedURL": "https://app.u1.fan/x/perch/updates/macos/appcast.xml", "publicEDKey": PUBLIC_KEY}
        (self.directory / "updates.json").write_text(json.dumps(config))
        (self.directory / "release.json").write_text(json.dumps({
            "status": "prepared", "config": config, "platformFiles": {"dist/index.html": "old hash"},
        }))
        page = self.directory / "platform/dist/index.html"
        page.parent.mkdir(parents=True)
        page.write_text("modified")
        with patch.object(release, "online_release") as online, patch.object(release, "run") as run:
            with self.assertRaisesRegex(ValueError, "发生变化"):
                release.publish_release(argparse.Namespace(release_dir=self.directory))
        online.assert_not_called()
        run.assert_not_called()

    def test_platform_publish_is_pinned_to_app_u1_fan_and_repeated_run_does_not_republish(self):
        config = {"version": "0.0.1", "build": "16", "feedURL": "https://app.u1.fan/x/perch/updates/macos/appcast.xml", "publicEDKey": PUBLIC_KEY}
        (self.directory / "updates.json").write_text(json.dumps(config))
        platform = self.directory / "platform"
        platform.mkdir()
        (self.directory / "release.json").write_text(json.dumps({
            "status": "prepared", "config": config, "platformFiles": {},
        }))
        appcast = platform / "dist/updates/macos/appcast.xml"
        appcast.parent.mkdir(parents=True)
        url = config["feedURL"].rsplit("/", 1)[0] + "/Perch-0.0.1-16-universal.dmg"
        new_feed = f'<rss><channel><item><enclosure url="{url}" xmlns:s="http://www.andymatuschak.org/xml-namespaces/sparkle" s:version="16"/></item></channel></rss>'.encode()
        old_feed = new_feed.replace(b'="16"', b'="15"')
        appcast.write_bytes(new_feed)
        report = json.loads((self.directory / "release.json").read_text())
        report["platformFiles"] = {"dist/updates/macos/appcast.xml": support.sha256(appcast)}
        (self.directory / "release.json").write_text(json.dumps(report))
        args = argparse.Namespace(release_dir=self.directory, client_data=None)
        with patch.object(release, "validate_appcast", return_value="signature"), \
                patch.object(release, "verify_signature"), \
                patch.object(release, "online_release", return_value=({"build": 15, "url": url}, old_feed)), \
                patch.object(release, "verify_public", return_value={"rangeSupported": True}), \
                patch.object(release, "run") as run:
            release.publish_release(args)
        run.assert_called_once_with("app-platform", "--server", "https://app.u1.fan", "publish", "--update", platform)
        self.assertEqual((self.directory / "previous-appcast.xml").read_bytes(), old_feed)
        with patch.object(release, "validate_appcast", return_value="signature"), \
                patch.object(release, "verify_signature"), \
                patch.object(release, "online_release", return_value=({"build": 16, "url": url}, new_feed)), \
                patch.object(release, "verify_public", return_value={"rangeSupported": True}), \
                patch.object(release, "run") as run:
            release.publish_release(args)
        run.assert_not_called()



if __name__ == "__main__":
    unittest.main()
