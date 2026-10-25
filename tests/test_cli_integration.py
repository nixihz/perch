import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
CLI = Path(os.environ.get("SKILLSET_CLI", ROOT / ".build/debug/skillset"))


def project_state(state, project):
    registrations = json.loads((state / "projects.json").read_text())["projects"]
    canonical = next(item["canonicalPath"] for item in registrations if os.path.samefile(item["canonicalPath"], project))
    key = hashlib.sha256(canonical.encode()).hexdigest()
    return state / "project-state" / key


class CLIIntegrationTests(unittest.TestCase):
    def run_cli(self, state, *args, check=True, extra_env=None):
        env = os.environ.copy()
        env.setdefault("SKILLSET_HOME", str(state.parent / "home"))
        env.update(extra_env or {})
        result = subprocess.run(
            [str(CLI), "--state", str(state), *args],
            cwd=ROOT,
            env=env,
            text=True,
            capture_output=True,
            timeout=30,
            check=False,
        )
        if check:
            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        return result

    def bootstrap_project(self, root):
        state = root / "state"
        state.mkdir()
        # 所需片段由场景自己创建，避免依赖应用是否附带默认内容。
        (state / "templates.json").write_text(json.dumps({
            "schemaVersion": 1,
            "records": [{
                "id": "base-zh", "title": "测试中文协作规则",
                "body": "始终使用中文回复。\n", "purpose": "CLI 安装测试", "isLocal": True,
            }],
            "deletedIDs": [],
        }), encoding="utf-8")
        project = root / "project"
        project.mkdir()
        (project / "README.md").write_text("# fixture\n", encoding="utf-8")
        added = json.loads(
            self.run_cli(
                state, "projects", "add", str(project), "--name", "Fixture", "--json"
            ).stdout
        )
        source = root / "home" / ".agents" / "skills" / "stc"
        source.mkdir(parents=True)
        (source / "SKILL.md").write_text("---\nname: stc\ndescription: CLI installation fixture\n---\nComplete skill body\n", encoding="utf-8")
        self.skill_id = json.loads(self.run_cli(state, "skills", "search", "stc", "--json").stdout)["skills"][0]["id"]
        return state, project, added["project"]["id"]

    def test_apply_requires_local_approval_then_writes_exact_files(self):
        with tempfile.TemporaryDirectory(prefix="skillset-cli-test-") as temporary:
            root = Path(temporary)
            state, project, project_id = self.bootstrap_project(root)
            planned = json.loads(
                self.run_cli(
                    state,
                    "plan",
                    project_id,
                    "--skills",
                    self.skill_id,
                    "--instructions",
                    "base-zh",
                    "--json",
                ).stdout
            )
            denied = self.run_cli(
                state,
                "apply",
                planned["planId"],
                "--digest",
                planned["digest"],
                "--json",
                check=False,
            )
            self.assertEqual(denied.returncode, 4)
            self.assertEqual(json.loads(denied.stdout)["error"]["code"], "APPROVAL_REQUIRED")
            self.assertFalse((project / ".agents/skills/stc").exists())

            self.run_cli(
                state,
                "approve",
                planned["planId"],
                "--digest",
                planned["digest"],
                "--json",
            )
            applied = json.loads(
                self.run_cli(
                    state,
                    "apply",
                    planned["planId"],
                    "--digest",
                    planned["digest"],
                    "--json",
                ).stdout
            )
            self.assertEqual(
                set(applied["changedPaths"]),
                {
                    ".agents/skills/stc",
                    "AGENTS.md",
                    str(project_state(state, project) / "skillset.json"),
                    str(project_state(state, project) / "skillset.lock.json"),
                },
            )
            self.assertTrue((project / ".agents/skills/stc/SKILL.md").is_file())
            self.assertIn("skillset:begin id=project-rules", (project / "AGENTS.md").read_text())
            self.assertIn("始终使用中文回复。", (project / "AGENTS.md").read_text())
            self.assertEqual({p.name for p in project.iterdir()}, {"README.md", ".agents", "AGENTS.md"})
            self.assertEqual((project / "README.md").read_text(), "# fixture\n")
            manifest = json.loads((project_state(state, project) / "skillset.json").read_text())
            lock = json.loads((project_state(state, project) / "skillset.lock.json").read_text())
            self.assertEqual(manifest["skills"], [self.skill_id])
            self.assertTrue(lock["manifestDigest"].startswith("sha256:"))
            self.assertTrue(lock["skills"][0]["files"])
            verified = json.loads(
                self.run_cli(
                    state,
                    "objects",
                    "verify",
                    "--project",
                    project_id,
                    "--json",
                ).stdout
            )
            self.assertGreaterEqual(verified["checkedObjects"], 2)

    def apply_selection(self, state, project_id, skill_ids):
        plan = json.loads(self.run_cli(
            state, "plan", project_id, "--skills", ",".join(skill_ids), "--json"
        ).stdout)
        self.run_cli(state, "approve", plan["planId"], "--digest", plan["digest"], "--json")
        return json.loads(self.run_cli(
            state, "apply", plan["planId"], "--digest", plan["digest"], "--json"
        ).stdout)

    def test_deselect_removes_only_managed_files_and_rollback_restores_them(self):
        with tempfile.TemporaryDirectory(prefix="skillset-cli-remove-") as temporary:
            root = Path(temporary)
            state, project, project_id = self.bootstrap_project(root)
            self.apply_selection(state, project_id, [self.skill_id])
            neighbor = project / ".agents/skills/personal/SKILL.md"
            neighbor.parent.mkdir()
            neighbor.write_text("项目自己的技能\n", encoding="utf-8")
            original = (project / ".agents/skills/stc/SKILL.md").read_bytes()
            inspected = json.loads(self.run_cli(state, "inspect", project_id, "--json").stdout)
            self.assertEqual(inspected["project"]["skillObservations"][0]["ownership"], "existing")
            managed = next(item for item in inspected["project"]["skillObservations"]
                           if item["relativePath"] == ".agents/skills/stc")
            self.assertEqual(managed["ownership"], "managed")
            removed = self.apply_selection(state, project_id, [])
            self.assertFalse((project / ".agents/skills/stc").exists())
            self.assertEqual(neighbor.read_text(), "项目自己的技能\n")
            self.assertEqual(json.loads((project_state(state, project) / "skillset.lock.json").read_text())["skills"], [])
            self.run_cli(state, "rollback", removed["operationID"], "--json")
            self.assertEqual((project / ".agents/skills/stc/SKILL.md").read_bytes(), original)
            self.assertEqual(neighbor.read_text(), "项目自己的技能\n")

    def test_unmanaged_collision_returns_a_conflict_without_writing(self):
        with tempfile.TemporaryDirectory(prefix="skillset-cli-collision-") as temporary:
            state, project, project_id = self.bootstrap_project(Path(temporary))
            skill = project / ".agents/skills/stc/SKILL.md"
            skill.parent.mkdir(parents=True)
            skill.write_text("项目原有的技能\n", encoding="utf-8")
            rejected = self.run_cli(
                state, "plan", project_id, "--skills", self.skill_id, "--json", check=False
            )
            self.assertEqual(rejected.returncode, 3)
            self.assertEqual(json.loads(rejected.stdout)["error"]["code"], "SKILL_TARGET_CONFLICT")
            self.assertEqual(skill.read_text(), "项目原有的技能\n")
            self.assertFalse((project / "skillset.json").exists())

    def test_mcp_stdio_returns_only_jsonrpc_messages(self):
        with tempfile.TemporaryDirectory(prefix="skillset-mcp-test-") as temporary:
            state = Path(temporary) / "state"
            messages = [
                {
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "initialize",
                    "params": {
                        "protocolVersion": "2025-11-25",
                        "capabilities": {},
                        "clientInfo": {"name": "integration-test", "version": "1"},
                    },
                },
                {"jsonrpc": "2.0", "method": "notifications/initialized"},
                {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
                {
                    "jsonrpc": "2.0",
                    "id": 3,
                    "method": "tools/call",
                    "params": {"name": "sources_list", "arguments": {}},
                },
            ]
            result = subprocess.run(
                [str(CLI), "--state", str(state), "mcp", "serve", "--transport", "stdio"],
                cwd=ROOT,
                input="\n".join(json.dumps(message) for message in messages) + "\n",
                text=True,
                capture_output=True,
                timeout=30,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            responses = [json.loads(line) for line in result.stdout.splitlines()]
            self.assertEqual([response["id"] for response in responses], [1, 2, 3])
            self.assertEqual(
                responses[0]["result"]["protocolVersion"], "2025-11-25"
            )
            self.assertEqual(
                {tool["name"] for tool in responses[1]["result"]["tools"]},
                {
                    "mcp_batch",
                    "projects_list",
                    "presets_list",
                    "skills_install",
                    "presets_install",
                    "skills_search",
                    "sources_list",
                    "sources_preview",
                    "projects_inspect",
                    "deployment_plan",
                    "deployment_apply",
                    "plans_pending",
                    "operations_get",
                    "objects_verify",
                    "mcp_servers_list",
                    "mcp_config_plan",
                    "plugins_list",
                    "plugin_lifecycle_plan",
                    "skills_get",
                    "skills_create",
                    "skills_update",
                    "skills_delete",
                    "skills_restore_hidden",
                    "templates_list",
                    "templates_get",
                    "templates_create",
                    "templates_update",
                    "templates_delete",
                    "presets_get",
                    "presets_create",
                    "presets_update",
                    "presets_delete",
                    "sources_get",
                    "sources_update",
                    "sources_delete",
                    "sources_import_skill",
                    "projects_create",
                    "projects_update",
                    "projects_delete",
                    "mcp_library_list",
                    "mcp_library_get",
                    "mcp_library_create",
                    "mcp_library_update",
                    "mcp_library_delete",
                    "mcp_library_selection_get",
                    "mcp_library_selection_set",
                    "mcp_library_plan",
                    "mcp_config_update_plan",
                    "mcp_config_delete_plan",
                    "global_config_get",
                    "global_config_plan",
                    "plugin_sources_list",
                    "plugin_sources_get",
                    "plugin_sources_create",
                    "plugin_sources_update",
                    "plugin_sources_delete",
                    "projects_draft_get",
                    "presets_apply_draft",
                    "deployment_harness_plan",
                    "templates_apply_plan",
                },
            )
            self.assertEqual(
                responses[2]["result"]["structuredContent"]["previews"], []
            )
            self.assertEqual(responses[0]["result"]["serverInfo"]["name"], "perch")
            tools = {
                tool["name"]: tool["annotations"]
                for tool in responses[1]["result"]["tools"]
            }
            self.assertTrue(tools["sources_preview"]["openWorldHint"])
            self.assertFalse(tools["sources_preview"]["destructiveHint"])
            self.assertFalse(tools["deployment_plan"]["readOnlyHint"])
            self.assertTrue(tools["deployment_apply"]["destructiveHint"])

    def test_plugins_list_merges_cached_manifest_with_install_index(self):
        with tempfile.TemporaryDirectory(prefix="skillset-plugin-test-") as temporary:
            root = Path(temporary)
            state = root / "state"
            home = root / "home"
            install_path = home / ".claude/plugins/cache/demo/sample/1.2.0"
            manifest_path = install_path / ".claude-plugin"
            manifest_path.mkdir(parents=True)
            (install_path / "hooks").mkdir()
            (install_path / ".mcp.json").write_text("{}\n", encoding="utf-8")
            (manifest_path / "plugin.json").write_text(
                json.dumps(
                    {
                        "name": "sample",
                        "version": "1.2.0",
                        "description": "fixture",
                        "license": "MIT",
                        "hooks": "./hooks/hooks.json",
                    }
                ),
                encoding="utf-8",
            )
            installed_index = home / ".claude/plugins/installed_plugins.json"
            installed_index.write_text(
                json.dumps(
                    {
                        "version": 2,
                        "plugins": {
                            "sample@demo": [
                                {
                                    "scope": "user",
                                    "installPath": str(install_path),
                                    "version": "1.2.0",
                                    "gitCommitSha": "a" * 40,
                                }
                            ]
                        },
                    }
                ),
                encoding="utf-8",
            )

            response = json.loads(
                self.run_cli(
                    state,
                    "plugins",
                    "list",
                    "--json",
                    extra_env={"SKILLSET_HOME": str(home)},
                ).stdout
            )
            self.assertEqual(len(response["plugins"]), 1)
            plugin = response["plugins"][0]
            self.assertEqual(plugin["pluginID"], "sample@demo")
            self.assertEqual(plugin["marketplaceID"], "demo")
            self.assertTrue(plugin["installed"])
            self.assertEqual(plugin["sourceRevision"], "a" * 40)
            self.assertIn("hooks", plugin["components"])
            self.assertIn("MCP", plugin["components"])
            self.assertIn("含 hook", plugin["risks"])

    def test_plugin_lifecycle_cli_requires_approval_and_invokes_fixed_host_command(self):
        with tempfile.TemporaryDirectory(prefix="skillset-plugin-lifecycle-cli-") as temporary:
            root = Path(temporary)
            state = root / "state"
            home = root / "home"
            install_path = home / ".claude/plugins/cache/demo/sample/1.2.0"
            manifest_path = install_path / ".claude-plugin"
            manifest_path.mkdir(parents=True)
            (manifest_path / "plugin.json").write_text(
                json.dumps({"name": "sample", "version": "1.2.0"}),
                encoding="utf-8",
            )
            (home / ".claude/plugins/installed_plugins.json").write_text(
                json.dumps(
                    {
                        "version": 2,
                        "plugins": {
                            "sample@demo": [
                                {
                                    "scope": "user",
                                    "installPath": str(install_path),
                                    "version": "1.2.0",
                                    "gitCommitSha": "c" * 40,
                                }
                            ]
                        },
                    }
                ),
                encoding="utf-8",
            )
            (home / ".claude/settings.json").write_text(
                json.dumps({"enabledPlugins": {"sample@demo": False}}),
                encoding="utf-8",
            )
            fake_claude = root / "bin/claude"
            fake_claude.parent.mkdir()
            fake_claude.write_text(
                "#!/bin/sh\n"
                "printf '%s\\n' \"$@\" > \"$HOME/plugin-invocation.txt\"\n"
                "exit 0\n",
                encoding="utf-8",
            )
            fake_claude.chmod(0o755)
            extra_env = {
                "SKILLSET_HOME": str(home),
                "SKILLSET_CLAUDE_BIN": str(fake_claude),
            }

            planned = json.loads(
                self.run_cli(
                    state,
                    "plugins",
                    "plan",
                    "--host",
                    "claude-code",
                    "--plugin",
                    "sample@demo",
                    "--action",
                    "enable",
                    "--scope",
                    "user",
                    "--json",
                    extra_env=extra_env,
                ).stdout
            )
            self.assertEqual(planned["metadata"]["planType"], "plugin-lifecycle")
            self.assertEqual(planned["approvalState"], "pending")
            self.assertFalse((home / "plugin-invocation.txt").exists())

            denied = self.run_cli(
                state,
                "apply",
                planned["planId"],
                "--digest",
                planned["digest"],
                "--json",
                check=False,
                extra_env=extra_env,
            )
            self.assertEqual(denied.returncode, 4)
            self.assertFalse((home / "plugin-invocation.txt").exists())

            self.run_cli(
                state,
                "approve",
                planned["planId"],
                "--digest",
                planned["digest"],
                "--json",
                extra_env=extra_env,
            )
            applied = json.loads(
                self.run_cli(
                    state,
                    "apply",
                    planned["planId"],
                    "--digest",
                    planned["digest"],
                    "--json",
                    extra_env=extra_env,
                ).stdout
            )
            self.assertEqual(
                (home / "plugin-invocation.txt").read_text().splitlines(),
                ["plugin", "enable", "sample@demo", "--scope", "user", "--json"],
            )
            operation = json.loads(
                self.run_cli(
                    state,
                    "operations",
                    "get",
                    applied["operationID"],
                    "--json",
                    extra_env=extra_env,
                ).stdout
            )
            self.assertEqual(operation["kind"], "plugin-lifecycle")
            self.assertEqual(operation["state"], "applied-verification-pending")
            self.assertEqual(operation["plugin"]["pluginID"], "sample@demo")
            self.assertFalse(operation["plugin"]["timedOut"])

    def test_plan_can_target_codex_and_claude_with_one_lock(self):
        with tempfile.TemporaryDirectory(prefix="skillset-dual-host-") as temporary:
            root = Path(temporary)
            state, project, project_id = self.bootstrap_project(root)
            planned = json.loads(
                self.run_cli(
                    state,
                    "plan",
                    project_id,
                    "--skills",
                    self.skill_id,
                    "--instructions",
                    "base-zh",
                    "--agents",
                    "codex,claude-code",
                    "--json",
                ).stdout
            )
            self.run_cli(state, "approve", planned["planId"], "--json")
            self.run_cli(state, "apply", planned["planId"], "--json")
            self.assertTrue((project / ".agents/skills/stc/SKILL.md").is_file())
            self.assertTrue((project / ".claude/skills/stc/SKILL.md").is_file())
            self.assertIn("skillset:begin id=project-rules", (project / "CLAUDE.md").read_text())
            self.assertIn("始终使用中文回复。", (project / "CLAUDE.md").read_text())
            lock = json.loads((project_state(state, project) / "skillset.lock.json").read_text())
            self.assertEqual(
                {target["agent"] for target in lock["targets"]},
                {"codex", "claude-code"},
            )

    def test_mcp_config_plan_writes_only_after_approval_and_records_ownership(self):
        with tempfile.TemporaryDirectory(prefix="skillset-mcp-config-") as temporary:
            root = Path(temporary)
            state, project, project_id = self.bootstrap_project(root)
            planned = json.loads(
                self.run_cli(
                    state,
                    "mcp",
                    "plan",
                    "--project",
                    project_id,
                    "--host",
                    "claude-code",
                    "--scope",
                    "project",
                    "--name",
                    "skillset-local",
                    "--transport",
                    "stdio",
                    "--command",
                    "skillset",
                    "--arg",
                    "mcp",
                    "--arg",
                    "serve",
                    "--env",
                    "SKILLSET_TOKEN",
                    "--json",
                ).stdout
            )
            self.assertEqual(planned["metadata"]["planType"], "mcp-configuration")
            self.assertFalse((project / ".mcp.json").exists())

            self.run_cli(state, "approve", planned["planId"], "--json")
            self.run_cli(state, "apply", planned["planId"], "--json")
            config = json.loads((project / ".mcp.json").read_text())
            server = config["mcpServers"]["skillset-local"]
            self.assertEqual(server["env"]["SKILLSET_TOKEN"], "${SKILLSET_TOKEN}")

            inspected = json.loads(
                self.run_cli(
                    state,
                    "mcp",
                    "servers",
                    "--project",
                    project_id,
                    "--json",
                ).stdout
            )
            project_config = next(
                item
                for item in inspected["configurations"]
                if item["host"] == "claude-code" and item["scope"] == "project"
            )
            self.assertEqual(project_config["servers"][0]["name"], "skillset-local")
            self.assertTrue(project_config["servers"][0]["managed"])

    def test_sources_list_and_credential_rejection_are_structured(self):
        with tempfile.TemporaryDirectory(prefix="skillset-source-cli-") as temporary:
            state = Path(temporary) / "state"
            listed = self.run_cli(state, "sources", "list", "--json")
            self.assertEqual(json.loads(listed.stdout), {"previews": []})

            rejected = self.run_cli(
                state,
                "sources",
                "preview",
                "https://user:token@github.com/example/repository",
                "--json",
                check=False,
            )
            self.assertEqual(rejected.returncode, 2)
            self.assertEqual(
                json.loads(rejected.stdout)["error"]["code"],
                "SOURCE_CREDENTIALS_REJECTED",
            )

            bad_ref = self.run_cli(
                state,
                "sources",
                "preview",
                "https://github.com/example/repository",
                "--ref",
                "--upload-pack=evil",
                "--json",
                check=False,
            )
            self.assertEqual(bad_ref.returncode, 2)
            self.assertEqual(
                json.loads(bad_ref.stdout)["error"]["code"],
                "SOURCE_INVALID_REF",
            )


if __name__ == "__main__":
    unittest.main()
