#!/usr/bin/env python3
"""离开仓库和构建目录，验证已打包命令能独立加载资源并完成 MCP 握手。"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def verify(executable):
    executable = Path(executable).resolve()
    with tempfile.TemporaryDirectory(prefix="perch-mcp-package-") as temporary:
        root = Path(temporary)
        packaged = root / "package with spaces"
        packaged.mkdir()
        shutil.copy2(executable, packaged / "skillset")
        shutil.copytree(executable.parent / "SkillSet_SkillSetCore.bundle", packaged / "SkillSet_SkillSetCore.bundle")
        library = executable.parent / "SkillSetLibrary"
        if not library.exists():
            library = executable.parent.parent / "Resources/SkillSetLibrary"
        shutil.copytree(library, packaged / "SkillSetLibrary")
        environment = os.environ.copy()
        for key in ("PACKAGE_RESOURCE_BUNDLE_PATH", "PACKAGE_RESOURCE_BUNDLE_URL", "SKILLSET_REPOSITORY_ROOT", "SKILLSET_REPOSITORY_LIBRARY"):
            environment.pop(key, None)
        # 技能库在状态目录的 skills/library。不隔离时会读到使用者的真实技能。
        environment["SKILLSET_HOME"] = str(root / "home")
        environment["CODEX_HOME"] = str(root / "home/.codex")
        environment["CLAUDE_CONFIG_DIR"] = str(root / "home/.claude")
        messages = [
            {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
                "protocolVersion": "2025-11-25", "capabilities": {},
                "clientInfo": {"name": "package-check", "version": "1"}}},
            {"jsonrpc": "2.0", "method": "notifications/initialized"},
            {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
        ]
        result = subprocess.run(
            [str(packaged / "skillset"), "--state", str(root / "state"), "mcp", "serve", "--transport", "stdio"],
            cwd=root, env=environment,
            input="".join(json.dumps(message) + "\n" for message in messages),
            text=True, capture_output=True, timeout=15,
        )
        if result.returncode:
            raise RuntimeError(f"MCP 启动失败（{result.returncode}）：{result.stderr[:500]}")
        responses = [json.loads(line) for line in result.stdout.splitlines()]
        if [response.get("id") for response in responses] != [1, 2]:
            raise RuntimeError("MCP 未按顺序返回握手与工具列表，或 stdout 混入其他输出")
        if responses[0].get("result", {}).get("protocolVersion") != "2025-11-25":
            raise RuntimeError("MCP 握手未返回预期协议")
        if responses[0].get("result", {}).get("serverInfo", {}).get("name") != "perch":
            raise RuntimeError("MCP 服务名称不是 perch")
        names = {tool["name"] for tool in responses[1].get("result", {}).get("tools", [])}
        if not {"presets_list", "skills_search", "skills_install", "presets_install", "projects_list", "deployment_plan", "deployment_apply", "skills_delete", "skills_update", "templates_create", "presets_apply_draft", "mcp_library_plan", "global_config_plan", "plugin_sources_delete"} <= names or "approve" in names:
            raise RuntimeError("MCP 未提供预期工具，或错误暴露批准入口")
        def cli(*arguments, expected=0):
            result = subprocess.run(
                [str(packaged / 'skillset'), '--state', str(root / 'state'), *arguments, '--json'],
                cwd=root, env=environment, text=True, capture_output=True, timeout=30,
            )
            if result.returncode != expected:
                raise RuntimeError(f'独立部署失败：{result.stdout[:500]} {result.stderr[:500]}')
            return json.loads(result.stdout)

        def mcp_tool(name, arguments):
            messages = [
                {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}},
                {"jsonrpc": "2.0", "method": "notifications/initialized"},
                {"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": name, "arguments": arguments}},
            ]
            result = subprocess.run(
                [str(packaged / 'skillset'), '--state', str(root / 'state'), 'mcp', 'serve', '--transport', 'stdio'],
                cwd=root, env=environment, input=''.join(json.dumps(message) + '\n' for message in messages),
                text=True, capture_output=True, timeout=30,
            )
            if result.returncode:
                raise RuntimeError(f'MCP 工具调用失败：{result.stderr[:500]}')
            responses = [json.loads(line) for line in result.stdout.splitlines()]
            response = next(item['result'] for item in responses if item.get('id') == 2)
            if response.get('isError'):
                raise RuntimeError(f'MCP 工具调用失败：{response}')
            return response['structuredContent']

        project = root / 'project'
        project.mkdir()
        registration = cli('projects', 'add', str(project))['project']
        # 新本机库从空开始；配置来源不会自动入库，这里显式导入测试用来源。
        source = root / 'fixture-skill'
        source.mkdir()
        document = '---\nname: package-fixture\ndescription: 独立打包验证技能\n---\n测试技能正文\n'
        (source / 'SKILL.md').write_text(document)
        preview = cli('sources', 'preview', str(source))
        candidate = next(item for item in preview['candidates'] if item['slug'] == 'package-fixture')
        mcp_tool('sources_import_skill', {
            'previewId': preview['id'], 'path': candidate['path'], 'slug': 'package-fixture', 'mode': 'copy',
        })
        found = mcp_tool('skills_search', {'query': 'package-fixture'})['skills']
        if len(found) != 1:
            raise RuntimeError('隔离本机库未检索到同步的打包测试技能')
        skill_id = found[0]['id']
        if mcp_tool('presets_list', {})['presets']:
            raise RuntimeError('正常首开不应注入程序自带预设')
        rules = '# 打包规则\n只使用本机保存的片段。'
        (root / 'state/templates.json').write_text(json.dumps({
            'schemaVersion': 1, 'deletedIDs': [], 'records': [{
                'id': 'package-rules', 'title': '我的打包规则', 'purpose': '', 'body': rules, 'isLocal': True,
            }],
        }))
        fixture = {
            'schemaVersion': 2, 'id': 'package-check', 'name': '打包验证', 'description': '',
            'revision': 1, 'skills': [skill_id], 'instructionFragments': ['package-rules'],
            'plugins': [], 'mcpServers': [], 'mergePolicy': 'explicit-selection', 'status': 'local',
        }
        (root / 'state/presets.json').write_text(json.dumps([fixture]))
        if not any(item['id'] == 'package-check' for item in mcp_tool('presets_list', {})['presets']):
            raise RuntimeError('MCP 未列出本机预设')
        plan = mcp_tool('presets_install', {'projectPath': str(project), 'presetId': 'package-check'})
        cli('apply', plan['planId'], '--digest', plan['digest'], expected=4)
        if list(project.iterdir()):
            raise RuntimeError('未批准的计划修改了项目')
        cli('approve', plan['planId'], '--digest', plan['digest'])
        cli('apply', plan['planId'], '--digest', plan['digest'])
        deployed = project / '.agents/skills/package-fixture/SKILL.md'
        if deployed.read_bytes() != document.encode():
            raise RuntimeError('技能部署内容与随包快照不一致')
        if rules not in (project / 'AGENTS.md').read_text():
            raise RuntimeError('规则片段未写入项目')
        cli('objects', 'verify', '--project', registration['id'])
        print(f"MCP 独立打包验证通过：{executable}（{len(names)} 个工具）")


if __name__ == "__main__":
    for argument in sys.argv[1:]:
        verify(argument)
