"""为本地技能建立可核验的实体快照，不修改来源或 agent 的发现目录。"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import tempfile


EXCLUDED = {
    ".git", ".DS_Store", "node_modules", "__pycache__", ".venv", "venv",
    ".cache", ".pytest_cache", "dist", "build", "target",
}
SECRET_PATTERNS = {
    "private-key": re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    "github-token": re.compile(rb"(?:ghp_|github_pat_)[A-Za-z0-9_]{25,}"),
    "api-key": re.compile(rb"\bsk-(?:proj-)?[A-Za-z0-9_-]{25,}"),
    "aws-access-key": re.compile(rb"\bAKIA[A-Z0-9]{16}\b"),
}
SENSITIVE_NAME = re.compile(r"(^\.env($|\.)|\.(pem|key|p12|pfx)$|^credentials$|^auth\.json$)", re.I)
MAX_FILE = 16 * 1024 * 1024
MAX_SKILL = 128 * 1024 * 1024


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def tree_hash(files):
    payload = [{"path": f["path"], "sha256": f["sha256"], "executable": f["executable"]} for f in files]
    return sha256(json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode())


def metadata(path):
    text = path.read_text(encoding="utf-8")
    header = re.match(r"^---\r?\n(.*?)\r?\n---(?:\r?\n|$)", text, re.S)
    if not header:
        return {"name": path.parent.name, "description": "", "metadataReview": "missing-frontmatter"}
    values = {}
    for key in ("name", "description", "version"):
        match = re.search(rf"^{key}:\s*([^\n]*)", header[1], re.M)
        value = match[1].strip().strip("\"'") if match else ""
        values[key] = value
    if values["description"] in ("", ">", "|", ">-", "|-"):
        match = re.search(r"^description:\s*[>|]-?\s*\n((?:[ \t]+[^\n]*\n?)*)", header[1], re.M)
        values["description"] = " ".join(match[1].split()) if match else ""
    values["name"] = values["name"] or path.parent.name
    # 这里只提取显示字段；完整 YAML/Agent Skills 合规性留给专用校验器。
    values["metadataReview"] = "not-schema-validated"
    return values


def snapshot(directory, allowed_roots, excluded_paths=()):
    directory = Path(directory)
    roots = [Path(p).resolve() for p in allowed_roots]
    files, issues, links, excluded = [], [], [], []
    total = 0

    def walk(path, relative, ancestors):
        nonlocal total
        relative_name = relative.as_posix()
        if (path.name in EXCLUDED or path.name.endswith((".pyc", ".swp"))
                or any(relative_name == item or relative_name.startswith(item + "/") for item in excluded_paths)):
            excluded.append(relative.as_posix())
            return
        try:
            resolved = path.resolve(strict=True)
        except (OSError, RuntimeError):
            issues.append({"path": relative.as_posix(), "reason": "broken-or-cyclic-link"})
            return
        if not any(resolved.is_relative_to(root) for root in roots):
            issues.append({"path": relative.as_posix(), "reason": "outside-approved-root"})
            return
        if path.is_symlink():
            links.append({"path": relative.as_posix(), "target": os.readlink(path), "resolved": str(resolved)})
        if resolved in ancestors:
            issues.append({"path": relative.as_posix(), "reason": "cyclic-link"})
            return
        mode = resolved.stat().st_mode
        if stat.S_ISDIR(mode):
            for child in sorted(path.iterdir()):
                walk(child, relative / child.name, ancestors | {resolved})
        elif stat.S_ISREG(mode):
            if SENSITIVE_NAME.search(path.name):
                issues.append({"path": relative.as_posix(), "reason": "sensitive-filename"})
                return
            size = resolved.stat().st_size
            if size > MAX_FILE or total + size > MAX_SKILL:
                issues.append({"path": relative.as_posix(), "reason": "size-limit"})
                return
            content = resolved.read_bytes()
            matches = [name for name, pattern in SECRET_PATTERNS.items() if pattern.search(content)]
            if matches:
                issues.append({"path": relative.as_posix(), "reason": "secret-pattern", "rules": matches})
                return
            total += len(content)
            files.append({
                "path": relative.as_posix(), "sha256": sha256(content),
                "size": len(content), "executable": bool(mode & 0o111),
            })
        else:
            issues.append({"path": relative.as_posix(), "reason": "unsupported-file-type"})

    walk(directory, Path("."), set())
    files.sort(key=lambda f: f["path"])
    return {
        "files": files, "contentHash": tree_hash(files), "bytes": total,
        "links": links, "issues": issues, "excluded": excluded,
    }


def materialize(source, destination, expected, allowed_roots):
    source, destination = Path(source), Path(destination)
    if destination.is_symlink():
        raise ValueError(f"目标不能是软链：{destination}")
    if destination.exists():
        actual = snapshot(destination, [destination])
        if actual["issues"] or actual["files"] != expected["files"]:
            raise ValueError(f"目标已有不同内容，拒绝覆盖：{destination}")
        return "unchanged"
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".skill-import-", dir=destination.parent) as temporary:
        staged = Path(temporary) / "content"
        staged.mkdir()
        for item in expected["files"]:
            origin = source / item["path"]
            resolved = origin.resolve(strict=True)
            if not any(resolved.is_relative_to(Path(root).resolve()) for root in allowed_roots):
                raise ValueError(f"来源链接在复制期间发生变化：{origin}")
            content = resolved.read_bytes()
            if sha256(content) != item["sha256"]:
                raise ValueError(f"来源内容在复制期间发生变化：{origin}")
            target = staged / item["path"]
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
            target.chmod(0o755 if item["executable"] else 0o644)
        actual = snapshot(staged, [staged])
        if actual["files"] != expected["files"]:
            raise ValueError(f"复制结果与清单不一致：{source}")
        staged.rename(destination)
    return "copied"


def git_info(root):
    def run(*args):
        result = subprocess.run(["git", "-C", str(root), *args], text=True, capture_output=True, check=False)
        return result.stdout.strip() if result.returncode == 0 else None
    return {
        "commit": run("rev-parse", "HEAD"),
        "dirty": bool(run("status", "--porcelain")),
    }


def build_catalog(repo, source, allowed_roots, copy=False):
    repo, source = Path(repo).resolve(), Path(source).resolve()
    catalog = {"schemaVersion": 1, "hashAlgorithm": "sha256:path-content-executable:v1", "entries": []}
    report = {
        "schemaVersion": 1, "sourceRoot": str(source), "sourceGit": git_info(source),
        "approvedRoots": [str(Path(root).resolve()) for root in allowed_roots],
        "entries": [], "notes": [
            "内容快照不是安装；未修改任何全局或项目发现目录。",
            "指纹包含相对路径、文件内容和可执行位；不包含 mtime。",
            "正则扫描不能证明没有秘密；发布前仍须人工审核来源和许可。",
        ],
    }
    for namespace, parent, destination_parent in (
        ("workspace", repo / "skills", repo / "skills"),
        ("local-brian", source, repo / "vendor" / "local-brian"),
    ):
        roots = [repo / "skills"] if namespace == "workspace" else allowed_roots
        for directory in sorted(parent.iterdir()):
            if directory.name.startswith(".") or not (directory / "SKILL.md").is_file():
                continue
            ignored = []
            if namespace == "workspace":
                result = subprocess.run(
                    ["git", "-C", str(repo), "ls-files", "--others", "--ignored",
                     "--exclude-standard", "--directory", "--", str(directory)],
                    text=True, capture_output=True, check=False,
                )
                if result.returncode == 0:
                    prefix = directory.relative_to(repo).as_posix() + "/"
                    ignored = [line.removeprefix(prefix).rstrip("/") for line in result.stdout.splitlines()
                               if line.startswith(prefix)]
            info = snapshot(directory, roots, ignored)
            if not any(f["path"] == "SKILL.md" for f in info["files"]):
                raise ValueError(f"入口文件未通过安全检查：{directory}")
            destination = destination_parent / directory.name
            meta = metadata(directory / "SKILL.md")
            action = "workspace"
            if namespace == "local-brian":
                action = materialize(directory, destination, info, roots) if copy else "planned"
                report["entries"].append({
                    "id": f"{namespace}/{directory.name}", "sourcePath": str(directory),
                    "resolvedSourcePath": str(directory.resolve()), "wasSymlink": directory.is_symlink(),
                    "destination": destination.relative_to(repo).as_posix(), **info,
                })
            catalog["entries"].append({
                "id": f"{namespace}/{directory.name}", "slug": directory.name,
                "declaredName": meta["name"], "description": meta["description"],
                "declaredVersion": meta.get("version") or None,
                "metadataReview": meta["metadataReview"], "sourceId": namespace,
                "path": destination.relative_to(repo).as_posix(), "contentHash": info["contentHash"],
                "fileCount": len(info["files"]), "bytes": info["bytes"],
                "wasSymlink": directory.is_symlink(), "integrity": "blocked" if info["issues"] else "snapshotted",
                "issues": info["issues"], "licenseReview": "required",
                "excludedPaths": ignored,
            })
    return catalog, report


def write_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False, encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
        temporary = Path(handle.name)
    temporary.replace(path)


def verify(repo):
    repo = Path(repo).resolve()
    catalog = json.loads((repo / "registry" / "catalog.json").read_text())
    failures = []
    for entry in catalog["entries"]:
        path = repo / entry["path"]
        if path.is_symlink() or not path.resolve().is_relative_to(repo):
            failures.append(f'{entry["id"]}: 内容入口不是仓库内实体目录')
            continue
        actual = snapshot(path, [repo], entry.get("excludedPaths", []))
        if actual["issues"] or actual["contentHash"] != entry["contentHash"]:
            failures.append(f'{entry["id"]}: 内容或可执行位与清单不符')
        if actual["links"]:
            failures.append(f'{entry["id"]}: 实体快照内仍存在软链')
    report = json.loads((repo / "registry" / "local-import.json").read_text())
    by_id = {entry["id"]: entry for entry in catalog["entries"]}
    for item in report["entries"]:
        entry = by_id.get(item["id"])
        if not entry or item["contentHash"] != entry["contentHash"] or item["issues"] != entry["issues"]:
            failures.append(f'{item["id"]}: 导入报告与目录清单不一致')
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("inventory", "import", "verify"))
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--source", type=Path, default=Path("/opt/case/brian/skills"))
    parser.add_argument("--allow-linked-root", action="append", type=Path, default=[])
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.command == "verify":
        failures = verify(args.repo)
        for failure in failures:
            print(failure)
        if failures:
            raise SystemExit(1)
        print("目录指纹核验通过；未验证许可证、运行依赖或模型行为。")
        return
    roots = [args.source, *args.allow_linked_root]
    catalog, report = build_catalog(args.repo, args.source, roots, copy=args.command == "import")
    if args.command == "import":
        write_json(args.repo / "registry" / "catalog.json", catalog)
        write_json(args.repo / "registry" / "local-import.json", report)
    elif args.output:
        write_json(args.output, report)
    print(json.dumps({
        "catalogEntries": len(catalog["entries"]), "externalSkills": len(report["entries"]),
        "topLevelSymlinks": sum(item["wasSymlink"] for item in report["entries"]),
        "issues": sum(len(item["issues"]) for item in report["entries"]),
        "blockedSkills": [entry["id"] for entry in catalog["entries"] if entry["integrity"] == "blocked"],
        "copiedBytes": sum(item["bytes"] for item in report["entries"]),
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
