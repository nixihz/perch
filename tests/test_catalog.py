import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location("catalog", Path(__file__).resolve().parents[1] / "scripts/catalog.py")
catalog = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(catalog)


class CatalogTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        self.source.mkdir()
        (self.source / "SKILL.md").write_text("---\nname: test\ndescription: 用例\n---\n正文\n")

    def test_link_becomes_physical_content_and_keeps_executable_bit(self):
        shared = self.root / "shared"
        shared.mkdir()
        script = shared / "run.sh"
        script.write_text("#!/bin/sh\nexit 3\n")
        script.chmod(0o755)
        (self.source / "scripts").symlink_to(shared, target_is_directory=True)
        link = self.root / "linked-skill"
        link.symlink_to(self.source, target_is_directory=True)
        manifest = catalog.snapshot(link, [self.root])
        destination = self.root / "result"
        catalog.materialize(link, destination, manifest, [self.root])
        copied = destination / "scripts/run.sh"
        self.assertEqual(copied.read_text(), "#!/bin/sh\nexit 3\n")
        self.assertTrue(copied.stat().st_mode & 0o111)
        self.assertFalse(destination.is_symlink())
        self.assertFalse((destination / "scripts").is_symlink())
        script.unlink()
        self.assertEqual(copied.read_text(), "#!/bin/sh\nexit 3\n")

    def test_broken_link_and_outside_root_are_recorded_without_reading_them(self):
        (self.source / "missing").symlink_to("../absent")
        outside = self.root / "secret.txt"
        outside.write_text("不能被读取的内容")
        (self.source / "outside").symlink_to(outside)
        result = catalog.snapshot(self.source, [self.source])
        self.assertEqual(result["issues"], [
            {"path": "missing", "reason": "broken-or-cyclic-link"},
            {"path": "outside", "reason": "outside-approved-root"},
        ])
        self.assertEqual([f["path"] for f in result["files"]], ["SKILL.md"])

    def test_cycle_does_not_recurse_forever(self):
        (self.source / "loop").symlink_to(self.source, target_is_directory=True)
        result = catalog.snapshot(self.source, [self.source])
        self.assertEqual(result["issues"], [{"path": "loop", "reason": "cyclic-link"}])

    def test_mtime_is_not_a_version_but_content_and_mode_are(self):
        entry = self.source / "SKILL.md"
        initial = catalog.snapshot(self.source, [self.source])["contentHash"]
        os.utime(entry, (123456, 123456))
        self.assertEqual(catalog.snapshot(self.source, [self.source])["contentHash"], initial)
        entry.chmod(0o755)
        self.assertNotEqual(catalog.snapshot(self.source, [self.source])["contentHash"], initial)
        entry.chmod(0o644)
        entry.write_text("已经修改的内容")
        self.assertNotEqual(catalog.snapshot(self.source, [self.source])["contentHash"], initial)

    def test_reimport_is_idempotent_but_does_not_overwrite_local_edit(self):
        expected = catalog.snapshot(self.source, [self.source])
        destination = self.root / "result"
        catalog.materialize(self.source, destination, expected, [self.source])
        self.assertEqual(catalog.materialize(self.source, destination, expected, [self.source]), "unchanged")
        (destination / "SKILL.md").write_text("保留我的修改")
        with self.assertRaisesRegex(ValueError, "拒绝覆盖"):
            catalog.materialize(self.source, destination, expected, [self.source])
        self.assertEqual((destination / "SKILL.md").read_text(), "保留我的修改")

    def test_source_changed_after_inventory_aborts_before_destination_exists(self):
        expected = catalog.snapshot(self.source, [self.source])
        (self.source / "SKILL.md").write_text("复制前发生的改动")
        destination = self.root / "result"
        with self.assertRaisesRegex(ValueError, "复制期间发生变化"):
            catalog.materialize(self.source, destination, expected, [self.source])
        self.assertFalse(destination.exists())

    def test_secret_files_are_quarantined_without_exposing_value(self):
        (self.source / ".env").write_text("PASSWORD=do-not-import")
        value = "ghp_" + "A" * 30
        (self.source / "config.txt").write_text(value)
        (self.source / ".DS_Store").write_text("噪声")
        result = catalog.snapshot(self.source, [self.source])
        self.assertEqual([item["path"] for item in result["issues"]], [".env", "config.txt"])
        self.assertNotIn(value, json.dumps(result))
        self.assertNotIn(".DS_Store", [item["path"] for item in result["files"]])

    def test_runtime_assets_are_not_part_of_a_tracked_snapshot(self):
        assets = self.source / "assets"
        assets.mkdir()
        (assets / "downloaded-runtime").write_bytes(b"runtime")
        manifest = catalog.snapshot(self.source, [self.source], ["assets"])
        self.assertEqual([item["path"] for item in manifest["files"]], ["SKILL.md"])
        self.assertEqual(manifest["excluded"], ["assets"])


if __name__ == "__main__":
    unittest.main()
