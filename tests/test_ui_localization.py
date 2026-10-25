"""检查应用文案覆盖率，不翻译或执行来源内容。"""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "Sources/SkillSetApp"
HAN = re.compile(r"[\u3400-\u9fff]")


def swift_string(source, start, with_end=False):
    key = ""
    index = start + 1
    while index < len(source):
        if source[index] == '"':
            return (key, index + 1) if with_end else key
        if source[index:index + 2] == "\\(":
            index += 2
            depth = 1
            while depth:
                char = source[index]
                if char == '"':
                    index = skip_string(source, index)
                    continue
                if char == "(":
                    depth += 1
                elif char == ")":
                    depth -= 1
                index += 1
            key += "%@"
        elif source[index] == "\\":
            key += {"n": "\n", "t": "\t", "r": "\r"}.get(source[index + 1], source[index + 1])
            index += 2
        else:
            key += source[index]
            index += 1
    raise ValueError("文案字符串未闭合")


def skip_string(source, start):
    return swift_string(source, start, with_end=True)[1]


def string_starts(source):
    starts = set()
    index = 0
    while index < len(source):
        if source[index:index + 2] == "//":
            end = source.find("\n", index)
            index = len(source) if end < 0 else end
        elif source[index] == '"':
            starts.add(index)
            index = skip_string(source, index)
        else:
            index += 1
    return starts


class UILocalizationTests(unittest.TestCase):
    def setUp(self):
        self.english = json.loads((APP / "Resources/English.json").read_text())

    def assert_translated(self, key, context):
        if not HAN.search(key):
            return
        self.assertTrue(key in self.english, f"{context} 缺少英文文案: {key}")
        self.assertFalse(HAN.search(self.english[key]), f"{context} 英文文案夹带中文: {key}")

    def test_visible_message_keys_are_covered(self):
        pattern = re.compile(r'(?:L10n\.(?:tr|text)|(?:model\.)?report)\(\s*(")')
        for path in APP.rglob("*.swift"):
            source = path.read_text()
            for match in pattern.finditer(source):
                self.assert_translated(swift_string(source, match.start(1)), path.name)

    def test_sanitized_diagnostic_outputs_are_covered(self):
        source = (APP / "Support/UserFacingText.swift").read_text()
        starts = string_starts(source)
        for match in re.finditer(r'(?:return|:)\s*(")', source):
            if match.start(1) in starts:
                self.assert_translated(swift_string(source, match.start(1)), "UserFacingText")

    def test_english_catalog_has_no_chinese_and_keeps_placeholder_counts(self):
        for key, translation in self.english.items():
            self.assertFalse(HAN.search(translation), key)
            self.assertEqual(key.count("%@"), translation.count("%@"), key)

    def test_skill_and_rule_bodies_bypass_localization(self):
        for name in ["SkillsView", "ConfigurationResourceView"]:
            self.assertIn("Text(skill.description)", (APP / f"Views/{name}.swift").read_text())
        self.assertIn("Text(candidate.description)", (APP / "Views/SourcesView.swift").read_text())
        self.assertIn("Text(template.body)", (APP / "Views/TemplatesView.swift").read_text())


if __name__ == "__main__":
    unittest.main()
