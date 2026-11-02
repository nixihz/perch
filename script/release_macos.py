#!/usr/bin/env python3
"""栖集 macOS 发版：预检、构建公证、准备平台包，以及显式发布后的公网核验。"""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import socket
import subprocess
from urllib.parse import urlsplit
from urllib.request import Request, urlopen
from urllib.error import HTTPError
import xml.etree.ElementTree as ET

from configure_updates import ENV_KEYS, load_configuration
from mac_release_support import capture, check_sparkle, sha256, signing_identity, verify_signature
from prepare_sparkle_update import BUNDLE_ID, ROOT, SPARKLE_NS, prepare, validate_appcast, validate_info

PLATFORM_SERVER = "https://app.u1.fan"


def run(*arguments, env=None):
    subprocess.run([str(value) for value in arguments], cwd=ROOT, env=env, check=True)


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def public_request(url, method="GET", headers=None):
    response = urlopen(Request(url, method=method, headers=headers or {}), timeout=30)
    if urlsplit(response.url).scheme != "https":
        response.close()
        raise ValueError("公网请求跳转到了非 HTTPS 地址")
    return response


def read_feed(data):
    root = ET.fromstring(data)
    items = root.findall("./channel/item")
    if root.tag != "rss" or not items:
        raise ValueError("线上清单不是有效的 RSS 更新清单，可能返回了登录页或首页")
    releases = []
    for item in items:
        enclosure = item.find("enclosure")
        if enclosure is None:
            raise ValueError("线上清单缺少 enclosure")
        build = item.findtext(f"{{{SPARKLE_NS}}}version") or enclosure.get(f"{{{SPARKLE_NS}}}version", "")
        url = enclosure.get("url", "")
        parsed = urlsplit(url)
        if (not re.fullmatch(r"[1-9][0-9]*", build) or parsed.scheme != "https"
                or not parsed.hostname or parsed.username or parsed.password or parsed.fragment):
            raise ValueError("线上清单的构建号或下载地址无效")
        releases.append({"build": int(build), "url": url})
    return max(releases, key=lambda release: release["build"])


def online_release(config):
    with public_request(config["feedURL"]) as response:
        data = response.read(1024 * 1024 + 1)
        if response.status != 200 or len(data) > 1024 * 1024:
            raise ValueError("线上更新清单状态或大小无效")
    return read_feed(data), data


def source_snapshot():
    if capture(["git", "status", "--porcelain", "--untracked-files=normal"], "源码状态检查"):
        raise ValueError("正式发版要求干净工作区；请先提交源码和发布脚本")
    paths = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).split(b"\0")
    files = []
    for raw_path in paths:
        if not raw_path:
            continue
        relative = os.fsdecode(raw_path)
        path = ROOT / relative
        contents = os.readlink(path).encode() if path.is_symlink() else path.read_bytes()
        files.append({"path": relative, "sha256": hashlib.sha256(contents).hexdigest(),
                      "mode": path.lstat().st_mode})
    return {"commit": capture(["git", "rev-parse", "HEAD"], "源码提交检查"), "files": files}


def check_source(snapshot):
    if source_snapshot() != snapshot:
        raise ValueError("检查或构建期间源码发生变化；请使用新发布目录重新执行")


def preflight(args, config):
    if BUNDLE_ID != "com.xiezhixin.perch":
        raise ValueError("正式发版必须沿用 com.xiezhixin.perch，请移除 PERCH_BUNDLE_ID 覆盖")
    if config["feedURL"] != PLATFORM_SERVER + "/x/perch/updates/macos/appcast.xml":
        raise ValueError("正式发版必须沿用 app.u1.fan 的栖集更新地址")
    for command in ("swift", "codesign", "security", "xcrun", "spctl", "hdiutil", "ditto", "openssl", "task", "app-platform"):
        if shutil.which(command) is None:
            raise ValueError(f"找不到发布工具：{command}")
    identity = signing_identity(args.signing_identity)
    try:
        capture(["xcrun", "notarytool", "history", "--keychain-profile", args.notary_profile], "Apple 公证凭据检查")
    except ValueError as error:
        raise ValueError(f"无法使用公证 profile {args.notary_profile}；请先在已解锁会话执行 "
                         f"xcrun notarytool history --keychain-profile {args.notary_profile} 核对") from error
    check_sparkle(args.sparkle_bin, config["publicEDKey"], args.account, args.ed_key_file)
    print(f"发布凭据预检通过；签名身份：{identity}", flush=True)
    return identity


def notarize(path, profile, log_path):
    with log_path.open("w") as log:
        subprocess.run(["xcrun", "notarytool", "submit", str(path), "--keychain-profile", profile,
                        "--wait", "--output-format", "json"], stdout=log, check=True)
    result = json.loads(log_path.read_text())
    if result.get("status") != "Accepted":
        raise ValueError(f"Apple 公证未通过；详见 {log_path}")
    return {"id": result["id"], "status": result["status"]}


def validate_app(app, config):
    validate_info(plistlib.loads((app / "Contents/Info.plist").read_bytes()), config)
    run("codesign", "--verify", "--deep", "--strict", app)
    details = subprocess.run(["codesign", "-dv", "--verbose=4", str(app)], capture_output=True,
                             text=True, check=True).stderr
    if "Authority=Developer ID Application:" not in details or "runtime" not in details:
        raise ValueError("应用必须使用 Developer ID 和 hardened runtime")
    for binary in (app / "Contents/MacOS/SkillSet", app / "Contents/Helpers/skillset"):
        architectures = capture(["lipo", "-archs", binary], "通用架构检查").split()
        if set(architectures) != {"arm64", "x86_64"}:
            raise ValueError(f"应用与内置 CLI 均须为通用架构：{binary}")


def stage_platform(output, config):
    platform = output / "platform"
    downloads = platform / "dist/updates/macos"
    downloads.mkdir(parents=True)
    for path in (output / "sparkle").iterdir():
        if path.name == "appcast.xml" or path.suffix == ".dmg":
            shutil.copy2(path, downloads / path.name)
    manifest = (ROOT / "website/perch/apps.yaml").read_text()
    manifest, count = re.subn(r"(?m)^version: .+$", f"version: {config['version']}", manifest)
    if count != 1:
        raise ValueError("平台 manifest 缺少唯一版本字段")
    (platform / "apps.yaml").write_text(manifest)
    html = (ROOT / "website/perch/index.html").read_text()
    html, count = re.subn(r"Perch-[0-9.]+-[0-9]+-universal\.dmg",
                         f"Perch-{config['version']}-{config['build']}-universal.dmg", html)
    if count != 2:
        raise ValueError("官网预期包含两个 DMG 下载入口，请先核对模板")
    html = re.sub(r"v[0-9]+\.[0-9]+\.[0-9]+(?: \([0-9]+\))?",
                  lambda match: f"v{config['version']} ({config['build']})" if "(" in match[0]
                  else f"v{config['version']}", html)
    (platform / "dist/index.html").write_text(html)
    (platform / "dist/assets").mkdir()
    shutil.copy2(ROOT / "assets/brand/perch-primary.png", platform / "dist/assets/perch.png")
    run("app-platform", "package", platform, "--output", output / "platform.zip",
        "--report", output / "platform-package.json")
    return {str(path.relative_to(platform)): sha256(path)
            for path in sorted(platform.rglob("*")) if path.is_file()}


def prepare_release(args, config):
    online, _ = online_release(config)
    config = config | {"version": args.version or config["version"],
                       "build": args.build or str(max(int(config["build"]), online["build"]) + 1)}
    # 与打包入口使用同一校验器，拒绝通过命令行带入无效版本。
    config = load_configuration(args.config, {ENV_KEYS[key]: value for key, value in config.items() if key in ENV_KEYS})
    if int(config["build"]) <= online["build"]:
        raise ValueError(f"构建号必须高于线上 {online['build']}")
    output = (args.output or ROOT / f"dist/release-v{config['version']}-{config['build']}").absolute()
    if output.exists() or output.is_symlink():
        raise ValueError(f"发布目录已存在，拒绝覆盖：{output}")
    snapshot = source_snapshot()
    identity = preflight(args, config)
    output.mkdir(parents=True)
    config_path = output / "updates.json"
    write_json(config_path, config)
    write_json(output / "source-before.json", snapshot)
    print(f"准备栖集 {config['version']} ({config['build']})：{output}", flush=True)
    run("task", "check")
    check_source(snapshot)
    environment = os.environ | {ENV_KEYS[key]: value for key, value in config.items() if key in ENV_KEYS}
    environment.update(PERCH_SIGNING_IDENTITY=identity, PERCH_DIST_DIR=str(output / "app"),
                       PERCH_UPDATE_CONFIG=str(config_path))
    run(ROOT / "script/build_and_run.sh", "--release", "--universal", "--no-open", env=environment)
    check_source(snapshot)
    app = output / "app/栖集.app"
    validate_app(app, config)
    submission = output / "notarization.zip"
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, submission)
    app_notary = notarize(submission, args.notary_profile, output / "app-notary.json")
    run("xcrun", "stapler", "staple", app)
    run("xcrun", "stapler", "validate", app)
    run("spctl", "--assess", "--type", "execute", "--verbose=2", app)
    validate_app(app, config)
    staging = output / "dmg-stage"
    staging.mkdir()
    run("ditto", app, staging / app.name)
    (staging / "Applications").symlink_to("/Applications")
    dmg = output / f"Perch-{config['version']}-{config['build']}-universal.dmg"
    run("hdiutil", "create", "-volname", "栖集", "-srcfolder", staging, "-format", "UDZO", dmg)
    run("codesign", "--force", "--sign", identity, "--timestamp", dmg)
    dmg_notary = notarize(dmg, args.notary_profile, output / "dmg-notary.json")
    run("xcrun", "stapler", "staple", dmg)
    prepare(dmg, output / "sparkle", config, args.sparkle_bin, args.account, args.ed_key_file)
    platform_files = stage_platform(output, config)
    check_source(snapshot)
    write_json(output / "release.json", {
        "status": "prepared", "config": config, "createdAt": datetime.now(timezone.utc).isoformat(),
        "machine": socket.gethostname(), "commit": snapshot["commit"],
        "sourceSHA256": sha256(output / "source-before.json"), "signingIdentity": identity,
        "notaryProfile": args.notary_profile, "appNotary": app_notary, "dmgNotary": dmg_notary,
        "platformFiles": platform_files, "archiveBytes": dmg.stat().st_size,
        "archiveSHA256": sha256(dmg), "appcastSHA256": sha256(output / "sparkle/appcast.xml"),
        "clientUpgrade": "pending", "unpublishedComponents": ["独立 CLI", "本地离线 ZIP"],
    })
    print(f"已准备并验证平台发布包：{output}\n"
          f"发布到 {PLATFORM_SERVER}：task macos:publish -- {output}")


def verify_public(config, archive, appcast):
    _, feed_data = online_release(config)
    if feed_data != appcast.read_bytes():
        raise ValueError("公网 appcast 与本地字节不一致；请核对平台发布结果")
    signature = validate_appcast(appcast, config, archive)
    url = config["feedURL"].rsplit("/", 1)[0] + "/" + archive.name
    with public_request(url, method="HEAD") as response:
        if response.status != 200:
            raise ValueError("公网安装包 HEAD 未返回 200")
        head = dict(response.headers)
    digest = hashlib.sha256()
    length = 0
    with public_request(url) as response:
        if response.status != 200:
            raise ValueError("公网安装包 GET 未返回 200")
        for chunk in iter(lambda: response.read(1024 * 1024), b""):
            digest.update(chunk)
            length += len(chunk)
    if length != archive.stat().st_size or digest.hexdigest() != sha256(archive):
        raise ValueError("公网完整安装包的长度或 SHA-256 不一致")
    verify_signature(archive, signature, config["publicEDKey"])
    with public_request(url, headers={"Range": "bytes=0-1023"}) as response:
        range_status = response.status
        first_bytes = response.read(1024)
        with archive.open("rb") as source:
            expected_bytes = source.read(1024)
        if first_bytes != expected_bytes:
            raise ValueError("公网 Range 返回的内容不一致")
    return {"status": "public-verified", "archiveSHA256": digest.hexdigest(), "archiveBytes": length,
            "head": head, "rangeStatus": range_status, "rangeSupported": range_status == 206,
            "clientUpgrade": "pending"}


def publish_release(args):
    output = args.release_dir.resolve()
    report = json.loads((output / "release.json").read_text())
    config = load_configuration(output / "updates.json", {})
    if config["feedURL"] != PLATFORM_SERVER + "/x/perch/updates/macos/appcast.xml":
        raise ValueError("正式发布必须使用 app.u1.fan 的栖集更新地址")
    if report.get("status") != "prepared" or config != report["config"]:
        raise ValueError("发布记录与配置不一致，必须使用完整准备成功的目录")
    platform = output / "platform"
    actual_files = {str(path.relative_to(platform)): sha256(path)
                    for path in sorted(platform.rglob("*")) if path.is_file()}
    if actual_files != report["platformFiles"]:
        raise ValueError("平台发布目录在准备完成后发生变化，拒绝发布")
    archive = platform / f"dist/updates/macos/Perch-{config['version']}-{config['build']}-universal.dmg"
    appcast = archive.parent / "appcast.xml"
    signature = validate_appcast(appcast, config, archive)
    verify_signature(archive, signature, config["publicEDKey"])
    online, previous_feed = online_release(config)
    if online["build"] >= int(config["build"]):
        if previous_feed != appcast.read_bytes():
            raise ValueError("线上已有相同或更高构建号，拒绝覆盖或降级")
    backup = output / "previous-appcast.xml"
    if not backup.exists():
        backup.write_bytes(previous_feed)
    if online["build"] < int(config["build"]):
        command = ["app-platform", "--server", PLATFORM_SERVER]
        if args.client_data:
            command += ["--client-data", args.client_data.expanduser().resolve()]
        run(*command, "publish", "--update", platform)
    previous = read_feed(backup.read_bytes())
    write_json(output / "publication.json", {
        "status": "platform-published", "server": PLATFORM_SERVER,
        "previousAppcastBackup": str(backup), "publicVerification": "pending",
    })
    verification = verify_public(config, archive, appcast)
    if previous["url"] != config["feedURL"].rsplit("/", 1)[0] + "/" + archive.name:
        try:
            with public_request(previous["url"], method="HEAD") as response:
                verification["previousArchiveAvailable"] = response.status == 200
        except HTTPError as error:
            verification["previousArchiveAvailable"] = False
            verification["previousArchiveHTTPStatus"] = error.code
    write_json(output / "public-verification.json", verification)
    print(f"已发布并完成公网字节校验：{output / 'public-verification.json'}")
    if not verification["rangeSupported"]:
        print("当前服务器未返回 206，分段续传尚未通过验收。")
    if verification.get("previousArchiveAvailable") is False:
        print("平台未保留前一版公开下载地址，正在下载旧包的客户端可能需要重新检查更新。")
    print("仍需从旧客户端实际完成检查更新、安装和重启。")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subcommands = parser.add_subparsers(dest="command", required=True)
    for name in ("preflight", "prepare"):
        command = subcommands.add_parser(name)
        command.add_argument("--config", type=Path, default=ROOT / "config/updates.json")
        command.add_argument("--sparkle-bin", type=Path,
                             default=ROOT / ".build/artifacts/sparkle/Sparkle/bin")
        command.add_argument("--notary-profile", default="APP-Notary-2026")
        command.add_argument("--signing-identity", default=os.environ.get("PERCH_SIGNING_IDENTITY"))
        source = command.add_mutually_exclusive_group()
        source.add_argument("--account")
        source.add_argument("--ed-key-file", type=Path)
        if name == "prepare":
            command.add_argument("--version")
            command.add_argument("--build")
            command.add_argument("--output", type=Path)
    publish = subcommands.add_parser("publish")
    publish.add_argument("release_dir", type=Path)
    publish.add_argument("--client-data", type=Path, help="app.u1.fan 的现有 CLI 登录目录")
    args = parser.parse_args()
    os.chdir(ROOT)
    try:
        if args.command == "publish":
            publish_release(args)
        else:
            args.sparkle_bin = args.sparkle_bin.expanduser().resolve()
            config = load_configuration(args.config)
            if not config["publicEDKey"] or not config["feedURL"].endswith("/appcast.xml"):
                raise ValueError("请先配置有效的 Sparkle 公钥和 appcast.xml 地址")
            if args.command == "preflight":
                preflight(args, config)
            else:
                prepare_release(args, config)
    except (ValueError, OSError, subprocess.SubprocessError, ET.ParseError) as error:
        parser.exit(1, f"macOS 发版失败：{error}\n")


if __name__ == "__main__":
    main()
