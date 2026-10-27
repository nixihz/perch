"""通过真实 stdio 服务验证管理操作、实时读取和审批边界，全部使用隔离目录。"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CLI = Path(os.environ.get("SKILLSET_CLI", ROOT / ".build/debug/skillset"))


class MCPManagementTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="perch-management-", dir=ROOT)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.state = self.root / "state"
        self.project = self.root / "project"
        self.project.mkdir()
        (self.root / "codex").mkdir()
        self.env = dict(os.environ, SKILLSET_HOME=str(self.root), CODEX_HOME=str(self.root / "codex"))
        self.env.pop("SKILLSET_REPOSITORY_LIBRARY", None)
        self.process = subprocess.Popen([str(CLI), "--state", str(self.state), "mcp", "serve", "--transport", "stdio"],
            cwd=self.root, env=self.env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.addCleanup(self.close)
        self.sequence = 0
        self.rpc("initialize")

    def close(self):
        self.process.stdin.close()
        self.process.wait(timeout=10)
        self.process.stdout.close()
        self.process.stderr.close()

    def rpc(self, method, params=None):
        self.sequence += 1
        self.process.stdin.write(json.dumps({"jsonrpc": "2.0", "id": self.sequence, "method": method, "params": params or {}}) + "\n")
        self.process.stdin.flush()
        line = self.process.stdout.readline()
        self.assertTrue(line, "服务意外退出")
        response = json.loads(line)
        self.assertEqual(response["id"], self.sequence)
        return response["result"]

    def tool(self, name, arguments=None, error=None):
        result = self.rpc("tools/call", {"name": name, "arguments": arguments or {}})
        self.assertEqual(result["isError"], error is not None, result)
        value = result["structuredContent"]
        if error:
            self.assertEqual(value["code"], error, result)
        return value

    def document(self, name="sample", body="执行检查。"):
        return f"---\nname: {name}\ndescription: 管理测试\n---\n\n# 技能\n\n{body}\n"

    def approve_apply(self, plan):
        self.tool("deployment_apply", {"planId": plan["planId"], "planDigest": plan["digest"]}, error="APPROVAL_REQUIRED")
        approved = subprocess.run([str(CLI), "--state", str(self.state), "approve", plan["planId"], "--digest", plan["digest"], "--json"],
            env=self.env, capture_output=True, text=True, timeout=30)
        self.assertEqual(approved.returncode, 0, approved.stdout + approved.stderr)
        self.tool("deployment_apply", {"planId": plan["planId"], "planDigest": plan["digest"]})

    def test_skill_crud_is_live_and_deletion_retains_installed_version(self):
        skill = self.tool("skills_create", {"slug": "sample", "document": self.document()})["skill"]
        self.tool("skills_create", {"slug": "sample", "document": self.document()}, error="LIBRARY_DUPLICATE")
        self.tool("skills_update", {"skillId": skill["id"], "document": "invalid"}, error="LIBRARY_DOCUMENT_INVALID")
        self.assertEqual(self.tool("skills_get", {"skillId": skill["id"]})["document"], self.document())
        edited = self.document(body="检查新的行为。")
        saved = self.tool("skills_update", {"skillId": skill["id"], "document": edited})["skill"]
        self.assertNotEqual(saved["contentHash"], skill["contentHash"])
        project = self.tool("projects_create", {"projectPath": str(self.project), "agents": ["codex"]})["project"]
        plan = self.tool("deployment_plan", {"projectId": project["id"], "skillIds": [skill["id"]], "agents": ["codex"], "installMethod": "copy"})
        self.assertEqual(list(self.project.iterdir()), [])
        self.approve_apply(plan)
        installed = self.project / ".agents/skills/sample/SKILL.md"
        self.assertEqual(installed.read_text(), edited)
        self.tool("skills_delete", {"skillId": skill["id"]})
        self.assertEqual(self.tool("skills_search", {"query": "sample"})["skills"], [])
        self.tool("skills_get", {"skillId": skill["id"]}, error="RESOURCE_NOT_FOUND")
        self.tool("skills_delete", {"skillId": skill["id"]}, error="RESOURCE_NOT_FOUND")
        self.assertEqual(installed.read_text(), edited)
        self.assertFalse((self.state / "sources" / saved["path"]).exists())

    def test_skill_mutations_report_effects_on_live_project_links(self):
        skill = self.tool("skills_create", {"slug": "sample", "document": self.document()})["skill"]
        project = self.tool("projects_create", {"projectPath": str(self.project)})["project"]
        plan = self.tool("skills_install", {"projectId": project["id"], "skillIds": [skill["id"]]})
        self.approve_apply(plan)
        installed = self.project / ".agents/skills/sample/SKILL.md"
        edited = self.document(body="软链立即跟随编辑。")
        updated = self.rpc("tools/call", {"name": "skills_update", "arguments": {"skillId": skill["id"], "document": edited}})
        self.assertFalse(updated["isError"])
        self.assertEqual(installed.read_text(), edited)
        self.assertIn("软链部署立即跟随", " ".join(updated["structuredContent"]["warnings"]))
        deleted = self.rpc("tools/call", {"name": "skills_delete", "arguments": {"skillId": skill["id"]}})
        self.assertFalse(deleted["isError"])
        self.assertIn("软链部署会失效", " ".join(deleted["structuredContent"]["warnings"]))
        self.assertTrue(installed.parent.is_symlink())
        self.assertFalse(installed.exists())
        self.assertNotIn("已部署内容和引用保留", deleted["content"][0]["text"])

    def test_create_from_skill_copies_complete_package_and_rejects_overwrite(self):
        source = self.root / "source"
        (source / "scripts").mkdir(parents=True)
        (source / "SKILL.md").write_text(self.document(body="运行 scripts/check.sh。"))
        script = source / "scripts/check.sh"
        script.write_text("#!/bin/sh\nexit 0\n")
        script.chmod(0o755)
        (source / "LICENSE").write_text("测试许可原文")
        preview = self.tool("sources_preview", {"url": str(source)})
        original = self.tool("sources_import_skill", {"previewId": preview["id"], "path": preview["candidates"][0]["path"], "slug": "sample", "mode": "symlink"})["skill"]
        edited = self.document(body="复制后仍运行 scripts/check.sh。")
        self.tool("skills_create", {"sourceSkillId": original["id"], "slug": "sample", "document": edited}, error="LIBRARY_DUPLICATE")
        self.tool("skills_create", {"sourceSkillId": "missing", "slug": "new", "document": edited}, error="RESOURCE_NOT_FOUND")
        copied = self.tool("skills_create", {"sourceSkillId": original["id"], "slug": "sample-copy", "document": edited})["skill"]
        destination = self.state / "sources/custom/sample-copy"
        self.assertEqual((destination / "scripts/check.sh").read_bytes(), script.read_bytes())
        self.assertTrue((destination / "scripts/check.sh").stat().st_mode & 0o111)
        self.assertEqual((destination / "LICENSE").read_text(), "测试许可原文")
        self.assertEqual((destination / "SKILL.md").read_text(), edited)
        metadata = json.loads((self.state / "skill-categories.json").read_text())
        self.assertEqual(metadata["origins"][copied["id"]], metadata["origins"][original["id"]])
        self.tool("skills_create", {"sourceSkillId": copied["id"], "slug": copied["id"], "document": self.document()}, error="LIBRARY_DUPLICATE")
        self.assertEqual((destination / "SKILL.md").read_text(), edited)
        self.assertNotEqual((source / "SKILL.md").read_text(), edited)
        self.assertEqual(self.tool("skills_get", {"skillId": original["id"]})["document"], self.document(body="运行 scripts/check.sh。"))
        self.tool("sources_delete", {"previewId": preview["id"]})
        self.assertEqual(self.tool("skills_get", {"skillId": copied["id"]})["document"], edited)
        self.assertTrue((destination / "scripts/check.sh").exists())

    def test_cached_skill_package_detects_nested_edits_additions_removal_and_permissions(self):
        self.tool("skills_create", {"slug": "sample", "document": self.document()})
        package = self.state / "sources/custom/sample"
        (package / "scripts").mkdir()
        script = package / "scripts/check.sh"
        script.write_text("exit 0\n")
        previous = self.tool("skills_get", {"skillId": "sample"})["skill"]["contentHash"]
        def edit_preserving_mtime():
            before = script.stat()
            script.write_text("exit 1\n")
            os.utime(script, ns=(before.st_atime_ns, before.st_mtime_ns))
        for change in [
            edit_preserving_mtime,
            lambda: script.chmod(0o755),
            lambda: (package / "scripts/extra.txt").write_text("新文件"),
            lambda: (package / "scripts/extra.txt").rename(package / "scripts/renamed.txt"),
            lambda: (package / "scripts/renamed.txt").unlink(),
        ]:
            change()
            current = self.tool("skills_search", {"query": "sample"})["skills"][0]["contentHash"]
            self.assertNotEqual(current, previous)
            previous = current
        project = self.tool("projects_create", {"projectPath": str(self.project)})["project"]
        plan = self.tool("deployment_plan", {"projectId": project["id"], "skillIds": ["sample"], "agents": ["codex"], "installMethod": "copy"})
        self.approve_apply(plan)
        self.assertEqual((self.project / ".agents/skills/sample/scripts/check.sh").read_text(), "exit 1\n")

    def test_package_cache_handles_internal_links_and_rejects_escaping_and_cyclic_links(self):
        self.tool("skills_create", {"slug": "sample", "document": self.document()})
        package = self.state / "sources/custom/sample"
        (package / "scripts").mkdir()
        script = package / "scripts/check.sh"
        script.write_text("exit 0\n")
        (package / "alias").symlink_to("scripts", target_is_directory=True)
        first = self.tool("skills_get", {"skillId": "sample"})["skill"]
        script.write_text("exit 1\n")
        self.assertNotEqual(self.tool("skills_get", {"skillId": "sample"})["skill"]["contentHash"], first["contentHash"])
        unsafe = package / "unsafe"
        for destination in [str(self.root), "."]:
            unsafe.symlink_to(destination, target_is_directory=True)
            self.assertEqual(self.tool("skills_search", {"query": "sample"})["skills"][0]["integrity"], "blocked")
            unsafe.unlink()
            self.assertEqual(self.tool("skills_get", {"skillId": "sample"})["skill"]["integrity"], "snapshotted")

    def test_incomplete_package_scan_does_not_reuse_stale_cache(self):
        self.tool("skills_create", {"slug": "sample", "document": self.document()})
        directory = self.state / "sources/custom/sample"
        for _ in range(66):
            directory /= "d"
        directory.mkdir(parents=True)
        script = directory / "check.sh"
        script.write_text("exit 0\n")
        first = self.tool("skills_get", {"skillId": "sample"})["skill"]["contentHash"]
        script.write_text("exit 1\n")
        self.assertNotEqual(self.tool("skills_get", {"skillId": "sample"})["skill"]["contentHash"], first)

    def test_template_preset_crud_and_live_deployment(self):
        template = self.tool("templates_create", {"title": "协作", "body": "使用中文。", "purpose": "测试"})["template"]
        preset = self.tool("presets_create", {"name": "协作预设", "instructionIds": [template["id"]]})["preset"]
        self.tool("templates_update", {"templateId": template["id"], "body": "保留用户改动。"})
        self.tool("presets_update", {"presetId": preset["id"], "description": "更新说明"})
        loaded = self.tool("presets_get", {"presetId": preset["id"]})["preset"]
        self.assertEqual(loaded["instructionFragments"], [template["id"]])
        self.assertEqual(loaded["revision"], 2)
        project = self.tool("projects_create", {"projectPath": str(self.project), "agents": ["codex"]})["project"]
        plan = self.tool("presets_install", {"projectId": project["id"], "presetId": preset["id"]})
        self.approve_apply(plan)
        self.assertIn("保留用户改动。", (self.project / "AGENTS.md").read_text())
        self.tool("templates_delete", {"templateId": template["id"]})
        self.assertEqual(self.tool("templates_list")["templates"], [])
        self.tool("presets_install", {"projectId": project["id"], "presetId": preset["id"]}, error="INSTRUCTION_NOT_FOUND")
        self.tool("presets_delete", {"presetId": preset["id"]})
        self.assertEqual(self.tool("presets_list")["presets"], [])
        self.assertIn("保留用户改动。", (self.project / "AGENTS.md").read_text())

    def test_source_update_hide_restore_import_and_delete(self):
        source = self.root / "source"
        source.mkdir()
        (source / "SKILL.md").write_text(self.document())
        (source / "helper.txt").write_text("附属文件")
        preview = self.tool("sources_preview", {"url": str(source)})
        self.assertEqual(self.tool("skills_search", {"query": "sample"})["skills"], [])
        entry = self.tool("sources_import_skill", {"previewId": preview["id"], "path": preview["candidates"][0]["path"], "slug": "sample", "mode": "symlink"})["skill"]
        self.tool("skills_update", {"skillId": entry["id"], "document": self.document()}, error="LIBRARY_READ_ONLY_SOURCE")
        self.tool("skills_delete", {"skillId": entry["id"]})
        self.assertEqual(self.tool("skills_search", {"query": "sample"})["skills"], [])
        personal = self.tool("sources_import_skill", {"previewId": preview["id"], "path": preview["candidates"][0]["path"], "slug": "copy", "mode": "copy"})["skill"]
        self.assertEqual((self.state / "sources" / personal["path"] / "helper.txt").read_text(), "附属文件")
        self.tool("sources_import_skill", {"previewId": preview["id"], "path": "../escape"}, error="SOURCE_IMPORT_UNAVAILABLE")
        updated = self.tool("sources_update", {"previewId": preview["id"]})["preview"]
        self.assertNotEqual(updated["id"], preview["id"])
        self.tool("sources_delete", {"previewId": updated["id"]})
        self.assertEqual(self.tool("sources_list")["previews"], [])
        self.assertEqual([e["id"] for e in self.tool("skills_search", {"query": ""})["skills"]], [personal["id"]])

    def test_mcp_library_selection_apply_edit_and_remove(self):
        entry = self.tool("mcp_library_create", {"name": "example", "transport": "stdio", "commandOrURL": "/usr/bin/true", "args": ["one"]})["entry"]
        self.tool("mcp_library_update", {"entryId": entry["id"], "args": ["two"]})
        self.tool("mcp_library_selection_set", {"host": "codex", "entryIds": [entry["id"]]})
        plan = self.tool("mcp_library_plan", {"host": "codex"})
        target = self.root / "codex/config.toml"
        self.assertFalse(target.exists())
        self.approve_apply(plan)
        self.assertIn('"two"', target.read_text())
        update = self.tool("mcp_config_update_plan", {"host": "codex", "scope": "user", "name": "example", "args": ["three"]})
        self.approve_apply(update)
        self.assertIn('"three"', target.read_text())
        remove = self.tool("mcp_config_delete_plan", {"host": "codex", "scope": "user", "name": "example"})
        self.approve_apply(remove)
        self.assertNotIn("mcp_servers.example", target.read_text())
        self.tool("mcp_library_delete", {"entryId": entry["id"]})
        self.assertEqual(self.tool("mcp_library_list")["entries"], [])
        self.tool("mcp_library_plan", {"host": "codex"}, error="MCP_LIBRARY_SELECTION_MISSING")
        self.tool("mcp_library_selection_set", {"host": "codex", "entryIds": []})
        self.assertEqual(self.tool("mcp_library_selection_get", {"host": "codex"})["entryIds"], [])

    def test_agents_global_target_is_independent_and_rejects_non_skill_resources(self):
        skill = self.tool("skills_create", {"slug": "sample", "document": self.document()})["skill"]
        shared = self.tool("global_config_get", {"host": "agents"})
        self.assertEqual(shared["skillsPath"], str(self.root / ".agents/skills"))
        self.assertEqual(shared["rulesPath"], "")
        plan = self.tool("global_config_plan", {
            "host": "agents", "skillIds": [skill["id"]], "instructionIds": [], "installMethod": "copy",
        })
        shared_file = self.root / ".agents/skills/sample/SKILL.md"
        self.assertFalse(shared_file.exists())
        self.approve_apply(plan)
        self.assertEqual(shared_file.read_text(), self.document())
        self.assertEqual(self.tool("global_config_get", {"host": "agents"})["selection"]["skillIDs"], [skill["id"]])
        self.assertFalse((self.root / "codex/skills").exists())
        self.assertFalse((self.root / ".agents/AGENTS.md").exists())
        self.tool("global_config_plan", {
            "host": "agents", "skillIds": [], "instructionIds": ["unsupported"],
        }, error="GLOBAL_STATE_CORRUPT")
        self.tool("mcp_library_selection_get", {"host": "agents"}, error="INVALID_ARGUMENTS")
        remove = self.tool("global_config_plan", {"host": "agents", "skillIds": [], "instructionIds": []})
        self.approve_apply(remove)
        self.assertFalse(shared_file.exists())

    def test_global_application_and_project_metadata(self):
        template = self.tool("templates_create", {"title": "全局", "body": "执行后核验。"})["template"]
        plan = self.tool("global_config_plan", {"host": "codex", "skillIds": [], "instructionIds": [template["id"]]})
        self.approve_apply(plan)
        self.assertIn("执行后核验。", (self.root / "codex/AGENTS.md").read_text())
        self.assertEqual(self.tool("global_config_get", {"host": "codex"})["selection"]["instructionIDs"], [template["id"]])
        remove = self.tool("global_config_plan", {"host": "codex", "skillIds": [], "instructionIds": []})
        self.approve_apply(remove)
        project = self.tool("projects_create", {"projectPath": str(self.project)})["project"]
        self.tool("projects_update", {"projectId": project["id"], "name": "新名称", "agents": ["claude-code"]})
        listed = self.tool("projects_list")["projects"]
        self.assertEqual(listed[0]["name"], "新名称")
        self.tool("projects_delete", {"projectId": project["id"]})
        self.assertEqual(self.tool("projects_list")["projects"], [])
        self.assertTrue(self.project.exists())

    def test_mixed_preset_draft_and_fragment_application_preserve_other_host(self):
        project = self.tool("projects_create", {"projectPath": str(self.project)})["project"]
        self.assertIsNone(self.tool("projects_draft_get", {"projectId": project["id"]})["draft"])
        template = self.tool("templates_create", {"title": "规则", "body": "检查可观察结果。"})["template"]
        connection = {"name": "example", "host": "codex", "scope": "project", "transport": "stdio", "commandOrURL": "/usr/bin/true", "args": [], "envKeys": []}
        preset = self.tool("presets_create", {"name": "混合", "instructionIds": [template["id"]], "mcpServers": [connection]})["preset"]
        applied = self.tool("presets_apply_draft", {"projectId": project["id"], "presetId": preset["id"], "host": "claude-code"})
        self.assertEqual(applied["status"], "draft-only")
        draft = self.tool("projects_draft_get", {"projectId": project["id"]})["draft"]
        self.assertEqual(draft["mcpServers"], [connection])
        self.assertEqual(draft["harnessSelections"]["claude-code"]["instructionIDs"], [template["id"]])
        self.assertEqual(list(self.project.iterdir()), [])
        first = self.tool("templates_apply_plan", {"projectId": project["id"], "host": "codex", "instructionIds": [template["id"]]})
        self.approve_apply(first)
        second = self.tool("deployment_harness_plan", {"projectId": project["id"], "host": "claude-code", "skillIds": [], "instructionIds": [template["id"]]})
        self.approve_apply(second)
        self.assertIn("检查可观察结果。", (self.project / "AGENTS.md").read_text())
        self.assertIn("检查可观察结果。", (self.project / "CLAUDE.md").read_text())
        remove = self.tool("deployment_harness_plan", {"projectId": project["id"], "host": "codex", "skillIds": [], "instructionIds": []})
        self.approve_apply(remove)
        self.assertIn("检查可观察结果。", (self.project / "CLAUDE.md").read_text())
        self.assertFalse((self.project / ".codex/config.toml").exists())

    def test_plugin_source_crud_preserves_previous_snapshot_on_failed_update(self):
        source = self.root / "plugin"
        (source / ".claude-plugin").mkdir(parents=True)
        manifest = source / ".claude-plugin/plugin.json"
        manifest.write_text(json.dumps({"name": "example", "version": "1.0"}))
        saved = self.tool("plugin_sources_create", {"url": str(source)})["source"]
        fetched = self.tool("plugin_sources_get", {"sourceId": saved["id"]})
        self.assertEqual(fetched["inventory"]["records"][0]["name"], "example")
        failure = self.rpc("tools/call", {"name": "plugin_sources_update", "arguments": {"sourceId": saved["id"], "url": str(self.root / "missing")}})
        self.assertTrue(failure["isError"])
        self.assertEqual(self.tool("plugin_sources_list")["sources"][0]["id"], saved["id"])
        manifest.write_text(json.dumps({"name": "example", "version": "2.0"}))
        updated = self.tool("plugin_sources_update", {"sourceId": saved["id"], "url": str(source)})["source"]
        self.assertNotEqual(updated["resolvedCommit"], saved["resolvedCommit"])
        self.tool("plugin_sources_delete", {"sourceId": updated["id"]})
        self.assertEqual(self.tool("plugin_sources_list")["sources"], [])
        self.assertTrue(manifest.exists())

    def test_schema_rejects_unknown_fields_bad_types_and_nested_fields(self):
        def filesystem_snapshot():
            return {
                str(path.relative_to(self.root)): os.readlink(path) if path.is_symlink() else path.read_bytes() if path.is_file() else None
                for path in self.root.rglob("*")
            }
        baseline = filesystem_snapshot()
        cases = [
            ("skills_delete", {"skillId": "personal/example", "confirmed": True}),
            ("skills_create", {"slug": 9, "document": self.document()}),
            ("skills_create", {"slug": "new", "document": self.document(), "sourceSkillId": True}),
            ("skills_search", {"query": "", "limit": True}),
            ("skills_search", {"query": "", "limit": 201}),
            ("projects_create", {"projectPath": str(self.project), "agents": ["unknown"]}),
            ("mcp_library_delete", {"entryId": "invalid"}),
            ("presets_create", {"name": "错误", "mcpServers": [{"name": "x", "secret": "reject"}]}),
        ]
        for name, args in cases:
            with self.subTest(name=name, args=args):
                self.tool(name, args, error="INVALID_ARGUMENTS")
        self.assertEqual(filesystem_snapshot(), baseline)

    def test_batch_annotations_cover_destructive_and_external_operations(self):
        tools = {tool["name"]: tool for tool in self.rpc("tools/list")["tools"]}
        self.assertTrue(tools["mcp_batch"]["annotations"]["destructiveHint"])
        self.assertTrue(tools["mcp_batch"]["annotations"]["openWorldHint"])
        self.assertTrue(tools["skills_update"]["annotations"]["destructiveHint"])
        self.assertFalse(tools["sources_update"]["annotations"]["idempotentHint"])
        self.tool("skills_create", {"slug": "sample", "document": self.document()})
        batch = self.tool("mcp_batch", {"operations": [
            {"name": "skills_delete", "arguments": {"skillId": "sample"}},
            {"name": "skills_search", "arguments": {"query": "sample"}},
        ]})
        self.assertEqual(batch["succeeded"], 2)
        self.assertEqual(batch["results"][1]["result"]["structuredContent"]["skills"], [])

    def test_mcp_batch_reuses_state_and_returns_partial_failures(self):
        response = self.rpc("tools/call", {"name": "mcp_batch", "arguments": {"operations": [
            {"name": "skills_create", "arguments": {"slug": "batch-skill", "document": self.document()}},
            {"name": "skills_search", "arguments": {"query": "batch-skill"}},
            {"name": "skills_create", "arguments": {"slug": "batch-skill", "document": self.document()}},
            {"name": "mcp_library_list", "arguments": {}},
        ]}})
        self.assertTrue(response["isError"])
        batch = response["structuredContent"]
        self.assertEqual(batch["count"], 4)
        self.assertEqual(batch["succeeded"], 3)
        self.assertEqual(batch["failed"], 1)
        self.assertEqual(batch["results"][1]["result"]["structuredContent"]["count"], 1)
        self.assertEqual(batch["results"][2]["result"]["structuredContent"]["code"], "LIBRARY_DUPLICATE")

    def test_cached_reads_see_library_writes_and_external_edits(self):
        created = self.tool("skills_create", {"slug": "cached-skill", "document": self.document(name="cached-skill")})
        self.assertEqual(self.tool("skills_search", {"query": "cached-skill"})["count"], 1)
        self.assertEqual(created["skill"]["id"], "cached-skill")
        self.assertEqual(self.tool("templates_list")["templates"], [])
        document = {
            "schemaVersion": 1,
            "records": [{
                "id": "external-rule",
                "title": "外部",
                "body": "外部写入。",
                "purpose": "缓存失效",
                "isLocal": True,
            }],
            "deletedIDs": [],
        }
        path = self.state / "templates.json"
        path.write_text(json.dumps(document), encoding="utf-8")
        self.assertEqual(self.tool("templates_get", {"templateId": "external-rule"})["template"]["body"], "外部写入。")
        document["records"][0]["body"] = "再次写入。"
        path.write_text(json.dumps(document), encoding="utf-8")
        self.assertEqual(self.tool("templates_get", {"templateId": "external-rule"})["template"]["body"], "再次写入。")

    def test_batch_reads_follow_the_write_in_the_same_request(self):
        operations = [{"name": "skills_create", "arguments": {"slug": "batch-read", "document": self.document(name="batch-read")}}]
        operations.extend({"name": "skills_search", "arguments": {"query": "batch-read"}} for _ in range(10))
        batch = self.rpc("tools/call", {"name": "mcp_batch", "arguments": {"operations": operations}})["structuredContent"]
        self.assertEqual(batch["failed"], 0)
        self.assertEqual(batch["succeeded"], 11)
        for item in batch["results"][1:]:
            self.assertEqual(item["result"]["structuredContent"]["count"], 1)

    def test_json_rpc_array_sees_the_earlier_write(self):
        messages = [
            {"jsonrpc": "2.0", "id": 30, "method": "tools/call", "params": {
                "name": "skills_create", "arguments": {"slug": "array-skill", "document": self.document(name="array-skill")}
            }},
            {"jsonrpc": "2.0", "id": 31, "method": "tools/call", "params": {
                "name": "skills_search", "arguments": {"query": "array-skill"}
            }},
        ]
        self.process.stdin.write(json.dumps(messages) + "\n")
        self.process.stdin.flush()
        response = json.loads(self.process.stdout.readline())
        self.assertEqual([item["id"] for item in response], [30, 31])
        self.assertFalse(response[0]["result"]["isError"])
        self.assertEqual(response[1]["result"]["structuredContent"]["count"], 1)

    def test_json_rpc_array_returns_one_batch_response(self):
        messages = [
            {"jsonrpc": "2.0", "id": 10, "method": "ping", "params": {}},
            {"jsonrpc": "2.0", "id": 11, "method": "tools/list", "params": {}},
        ]
        self.process.stdin.write(json.dumps(messages) + "\n")
        self.process.stdin.flush()
        response = json.loads(self.process.stdout.readline())
        self.assertEqual([item["id"] for item in response], [10, 11])


if __name__ == "__main__":
    unittest.main()
