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
        for key in ("PACKAGE_RESOURCE_BUNDLE_PATH", "PACKAGE_RESOURCE_BUNDLE_URL", "SKILLSET_REPOSITORY_ROOT"):
            environment.pop(key, None)
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
        names = {tool["name"] for tool in responses[1].get("result", {}).get("tools", [])}
        if not {"skills_search", "projects_list", "deployment_plan", "deployment_apply"} <= names or "approve" in names:
            raise RuntimeError("MCP 未提供预期工具，或错误暴露批准入口")
        def cli(*arguments, expected=0):
            result = subprocess.run(
                [str(packaged / 'skillset'), '--state', str(root / 'state'), *arguments, '--json'],
                cwd=root, env=environment, text=True, capture_output=True, timeout=30,
            )
            if result.returncode != expected:
                raise RuntimeError(f'独立部署失败：{result.stdout[:500]} {result.stderr[:500]}')
            return json.loads(result.stdout)

        project = root / 'project'
        project.mkdir()
        registration = cli('projects', 'add', str(project))['project']
        plan = cli('plan', registration['id'], '--skills', 'workspace/stc', '--instructions', 'base-zh')
        cli('apply', plan['planId'], '--digest', plan['digest'], expected=4)
        if list(project.iterdir()):
            raise RuntimeError('未批准的计划修改了项目')
        cli('approve', plan['planId'], '--digest', plan['digest'])
        cli('apply', plan['planId'], '--digest', plan['digest'])
        deployed = project / '.agents/skills/stc/SKILL.md'
        if deployed.read_bytes() != (library / 'skills/stc/SKILL.md').read_bytes():
            raise RuntimeError('技能部署内容与随包快照不一致')
        if 'skillset:begin id=project-rules' not in (project / 'AGENTS.md').read_text():
            raise RuntimeError('规则片段未写入项目')
        cli('objects', 'verify', '--project', registration['id'])
        print(f"MCP 独立打包验证通过：{executable}（{len(names)} 个工具）")


if __name__ == "__main__":
    for argument in sys.argv[1:]:
        verify(argument)
