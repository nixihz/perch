import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
CLI = Path(os.environ.get("SKILLSET_CLI", ROOT / ".build/debug/skillset"))


class CLIIntegrationTests(unittest.TestCase):
    def run_cli(self, state, *args, check=True, extra_env=None):
        env = os.environ.copy()
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
        project = root / "project"
        project.mkdir()
        (project / "README.md").write_text("# fixture\n", encoding="utf-8")
        added = json.loads(
            self.run_cli(
                state, "projects", "add", str(project), "--name", "Fixture", "--json"
            ).stdout
        )
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
                    "workspace/stc",
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
                    "skillset.json",
                    "skillset.lock.json",
                },
            )
            self.assertTrue((project / ".agents/skills/stc/SKILL.md").is_file())
            self.assertIn("skillset:begin id=project-rules", (project / "AGENTS.md").read_text())
            manifest = json.loads((project / "skillset.json").read_text())
            lock = json.loads((project / "skillset.lock.json").read_text())
            self.assertEqual(manifest["skills"], ["workspace/stc"])
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
                    "projects_list",
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
                },
            )
            self.assertEqual(
                responses[2]["result"]["structuredContent"]["previews"], []
            )
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
                    "workspace/stc",
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
            lock = json.loads((project / "skillset.lock.json").read_text())
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
