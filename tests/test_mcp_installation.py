"""使用隔离本机库验证 MCP 的搜索、预设和完整项目安装链路。"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import uuid


ROOT = Path(__file__).resolve().parents[1]
CLI = Path(os.environ.get("SKILLSET_CLI", ROOT / ".build/debug/skillset"))


class MCPInstallationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="perch-mcp-install-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.state = self.root / "state"
        self.project = self.root / "project with spaces"
        self.project.mkdir()
        self.env = os.environ.copy()
        self.env.update({"SKILLSET_HOME": str(self.root / "home"), "CODEX_HOME": str(self.root / "codex")})
        entries = json.loads((ROOT / "registry/catalog.json").read_text())["entries"]
        records = []
        for slug in ("stc", "project-guide"):
            entry = next(dict(item) for item in entries if item["id"] == f"workspace/{slug}")
            package = f"packages/{uuid.uuid4()}"
            shutil.copytree(ROOT / entry["path"], self.state / "skills" / package)
            entry.update(id=f"personal/{slug}", sourceId="personal", path=package)
            records.append({"entry": entry})
        (self.state / "skills/index.json").write_text(json.dumps({"schemaVersion": 1, "records": records, "hiddenIDs": []}))
        # 预设引用本机片段，测试不能依赖应用附带的默认片段。
        (self.state / "templates.json").write_text(json.dumps({
            "schemaVersion": 1,
            "records": [{
                "id": "base-zh", "title": "测试中文协作规则",
                "body": "始终使用中文回复。\n", "purpose": "MCP 安装测试", "isLocal": True,
            }],
            "deletedIDs": [],
        }), encoding="utf-8")
        preset = json.loads((ROOT / "presets/personal-base.json").read_text())
        preset.update(id="local-review", name="本机审查预设", skills=["project-guide"], instructionFragments=["base-zh"])
        (self.state / "presets.json").write_text(json.dumps([preset]))
        self.project_id = self.cli("projects", "add", str(self.project))["project"]["id"]

    def cli(self, *args):
        result = subprocess.run([str(CLI), "--state", str(self.state), *args, "--json"],
                                cwd=self.root, env=self.env, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return json.loads(result.stdout)

    def rpc(self, method, params=None):
        messages = [
            {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}},
            {"jsonrpc": "2.0", "method": "notifications/initialized"},
            {"jsonrpc": "2.0", "id": 2, "method": method, "params": params or {}},
        ]
        result = subprocess.run([str(CLI), "--state", str(self.state), "mcp", "serve", "--transport", "stdio"],
                                cwd=self.root, env=self.env, input="".join(json.dumps(m) + "\n" for m in messages),
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        responses = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual(responses[0]["result"]["serverInfo"]["name"], "perch")
        return responses[1]["result"]

    def tool(self, name, arguments):
        return self.rpc("tools/call", {"name": name, "arguments": arguments})

    def approve_and_install(self, result):
        self.assertFalse(result["isError"], result)
        plan = result["structuredContent"]
        self.assertEqual(plan["status"], "awaiting-approval")
        denied = self.tool(plan["nextTool"], plan["nextArguments"])
        self.assertTrue(denied["isError"])
        self.assertEqual(denied["structuredContent"]["code"], "APPROVAL_REQUIRED")
        self.cli("approve", plan["planId"], "--digest", plan["digest"])
        applied = self.tool(plan["nextTool"], plan["nextArguments"])
        self.assertFalse(applied["isError"], applied)
        return applied

    def test_lists_searches_and_installs_selected_skills_then_preset(self):
        listed = self.rpc("tools/list")
        tools = {item["name"]: item for item in listed["tools"]}
        self.assertTrue({"presets_list", "skills_search", "skills_install", "presets_install"} <= tools.keys())
        self.assertFalse(tools["presets_install"]["annotations"]["readOnlyHint"])
        presets = self.tool("presets_list", {"query": "本机审查"})["structuredContent"]["presets"]
        self.assertEqual([p["id"] for p in presets], ["local-review"])
        found = self.tool("skills_search", {"query": "stc"})["structuredContent"]["skills"]
        self.assertEqual([s["id"] for s in found], ["stc"])
        first = self.tool("skills_install", {"projectPath": str(self.project), "skillIds": ["stc"]})
        self.assertEqual(list(self.project.iterdir()), [])
        self.approve_and_install(first)
        original = (self.project / ".agents/skills/stc/SKILL.md").read_bytes()
        second = self.tool("presets_install", {"projectId": self.project_id, "presetId": "local-review"})
        self.assertFalse((self.project / ".agents/skills/project-guide").exists())
        self.approve_and_install(second)
        self.assertEqual((self.project / ".agents/skills/stc/SKILL.md").read_bytes(), original)
        self.assertEqual((self.project / ".agents/skills/project-guide/SKILL.md").read_bytes(), (ROOT / "skills/project-guide/SKILL.md").read_bytes())
        self.assertIn("skillset:begin", (self.project / "AGENTS.md").read_text())
        self.assertIn("始终使用中文回复。", (self.project / "AGENTS.md").read_text())
        self.assertEqual({p.name for p in self.project.iterdir()}, {".agents", "AGENTS.md"})
        registration = json.loads((self.state / "projects.json").read_text())["projects"][0]
        key = hashlib.sha256(registration["canonicalPath"].encode()).hexdigest()
        manifest = json.loads((self.state / "project-state" / key / "skillset.json").read_text())
        self.assertEqual(manifest["skills"], ["project-guide", "stc"])

    def test_rejects_unregistered_target_ambiguous_target_and_unknown_preset(self):
        cases = [
            ("skills_install", {"projectPath": str(self.root), "skillIds": ["stc"]}, "PROJECT_NOT_REGISTERED"),
            ("skills_install", {"skillIds": ["stc"]}, "INVALID_ARGUMENTS"),
            ("skills_install", {"projectPath": str(self.project), "projectId": self.project_id, "skillIds": ["stc"]}, "INVALID_ARGUMENTS"),
            ("presets_install", {"projectId": self.project_id, "presetId": "missing"}, "PRESET_NOT_FOUND"),
        ]
        for name, arguments, code in cases:
            with self.subTest(code=code, arguments=arguments):
                response = self.tool(name, arguments)
                self.assertTrue(response["isError"], response)
                self.assertEqual(response["structuredContent"]["code"], code)
        self.assertEqual(list(self.project.iterdir()), [])
        self.assertEqual(self.tool("plans_pending", {})["structuredContent"]["plans"], [])


if __name__ == "__main__":
    unittest.main()
