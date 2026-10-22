#!/usr/bin/env python3
"""打包本机可信技能快照，不运行技能中的脚本。"""
import hashlib
import json
from pathlib import Path
import shutil
import sys


def package(repository, destination):
    repository = Path(repository).resolve()
    destination = Path(destination)
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    catalog = json.loads((repository / 'registry/catalog.json').read_text())
    for name in ['registry', 'presets', 'templates', 'objects']:
        shutil.copytree(repository / name, destination / name)
    for entry in catalog['entries']:
        if entry['integrity'] == 'blocked':
            continue
        relative = Path(entry['path'])
        source = (repository / relative).resolve()
        if relative.is_absolute() or '..' in relative.parts or not source.is_relative_to(repository):
            raise ValueError(f'技能路径越界：{relative}')
        target = destination / relative
        if source.is_dir() and not target.exists():
            shutil.copytree(source, target)
    digest = hashlib.sha256()
    for path in sorted(destination.rglob('*')):
        if path.is_file():
            digest.update(str(path.relative_to(destination)).encode())
            digest.update(path.read_bytes())
            digest.update(str(path.stat().st_mode & 0o111).encode())
    (destination / 'package-revision').write_text(digest.hexdigest())


if __name__ == '__main__':
    package(*sys.argv[1:])
