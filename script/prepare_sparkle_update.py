#!/usr/bin/env python3
"""从已公证 DMG 生成栖集 appcast；不上传，也不覆盖已有发布目录。"""

import argparse
import base64
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
from urllib.parse import urljoin, urlsplit
import xml.etree.ElementTree as ET

from configure_updates import load_configuration

ROOT = Path(__file__).resolve().parents[1]
SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
BUNDLE_ID = "com.xiezhixin.perch"


def validate_info(info, config):
    if info.get("CFBundleIdentifier") != BUNDLE_ID:
        raise ValueError("DMG 必须包含 com.xiezhixin.perch 应用")
    for key, field in [("CFBundleShortVersionString", "version"), ("CFBundleVersion", "build"),
                       ("SUFeedURL", "feedURL"), ("SUPublicEDKey", "publicEDKey")]:
        if not config[field] or info.get(key) != config[field]:
            raise ValueError(f"应用的 {key} 与发布配置不一致或未配置")
    if info.get("SUVerifyUpdateBeforeExtraction") is not True:
        raise ValueError("必须启用解压前验签")
    if info.get("SUAllowsAutomaticUpdates") is not False:
        raise ValueError("必须关闭静默安装")


def validate_appcast(path, config, archive):
    root = ET.parse(path).getroot()
    if root.tag != "rss":
        raise ValueError("更新清单必须是 RSS XML")
    items = root.findall("./channel/item")
    if len(items) != 1:
        raise ValueError("本次发布清单必须恰好包含一个版本")
    item = items[0]
    enclosure = item.find("enclosure")
    if enclosure is None:
        raise ValueError("更新清单缺少下载包")
    feed = config["feedURL"]
    expected_url = feed.rsplit("/", 1)[0] + "/" + archive.name
    if enclosure.get("url") != expected_url:
        raise ValueError("更新包 URL 不匹配")
    if enclosure.get("length") != str(archive.stat().st_size):
        raise ValueError("更新包长度不匹配")
    for field, value in [("version", config["build"]), ("shortVersionString", config["version"]),
                         ("minimumSystemVersion", "14.0")]:
        actual = item.findtext(f"{{{SPARKLE_NS}}}{field}") or enclosure.get(f"{{{SPARKLE_NS}}}{field}")
        if actual != value:
            raise ValueError(f"更新清单 {field} 不匹配")
    signature = enclosure.get(f"{{{SPARKLE_NS}}}edSignature", "")
    try:
        signature_bytes = base64.b64decode(signature, validate=True)
    except ValueError as error:
        raise ValueError("更新签名无效") from error
    if len(signature_bytes) != 64:
        raise ValueError("更新签名必须是 64 字节 Ed25519 签名")
    return signature


def run(*arguments):
    subprocess.run([str(arg) for arg in arguments], check=True)


def prepare(dmg, output, config, sparkle_bin):
    if output.exists():
        raise ValueError("输出目录已存在，拒绝覆盖已发布内容")
    if not config["feedURL"] or not urlsplit(config["feedURL"]).path.endswith("/appcast.xml"):
        raise ValueError("请先配置 HTTPS appcast.xml 地址及公钥")
    public_key = subprocess.check_output([
        str(sparkle_bin / "generate_keys"), "--account", BUNDLE_ID, "-p"
    ], text=True).strip()
    if public_key != config["publicEDKey"]:
        raise ValueError("发布机签名公钥与客户端公钥不同")
    run("codesign", "--verify", "--strict", dmg)
    run("xcrun", "stapler", "validate", dmg)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="perch-update-", dir=output.parent) as temporary:
        stage = Path(temporary)
        mount = stage / "mount"
        mount.mkdir()
        run("hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", mount, dmg)
        try:
            apps = list(mount.glob("*.app"))
            if len(apps) != 1:
                raise ValueError("DMG 必须只包含一个应用")
            app = apps[0]
            validate_info(plistlib.loads((app / "Contents/Info.plist").read_bytes()), config)
            run("codesign", "--verify", "--deep", "--strict", app)
            run("xcrun", "stapler", "validate", app)
            run("spctl", "--assess", "--type", "execute", "--verbose=2", app)
        finally:
            run("hdiutil", "detach", mount)
        release = stage / "release"
        release.mkdir()
        archive = release / f"Perch-{config['version']}-{config['build']}-universal.dmg"
        shutil.copy2(dmg, archive)
        run(sparkle_bin / "generate_appcast", "--account", BUNDLE_ID,
            "--download-url-prefix", config["feedURL"].rsplit("/", 1)[0] + "/",
            "--link", urljoin(config["feedURL"], "../../"),
            "--maximum-deltas", "0", release)
        signature = validate_appcast(release / "appcast.xml", config, archive)
        run(sparkle_bin / "sign_update", "--account", BUNDLE_ID, "--verify", archive, signature)
        release.rename(output)
    print(f"更新包与签名清单已生成：{output}；尚未上传")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dmg", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--config", type=Path, default=ROOT / "config/updates.json")
    parser.add_argument("--sparkle-bin", type=Path, default=ROOT / ".build/artifacts/sparkle/Sparkle/bin")
    args = parser.parse_args()
    try:
        prepare(args.dmg.resolve(), args.output.resolve(), load_configuration(args.config), args.sparkle_bin.resolve())
    except (ValueError, OSError, subprocess.CalledProcessError, ET.ParseError) as error:
        parser.exit(1, f"准备 Sparkle 更新失败：{error}\n")


if __name__ == "__main__":
    main()
