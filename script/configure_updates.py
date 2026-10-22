#!/usr/bin/env python3
"""校验公开的发布配置，并写入应用元数据；不创建或读取私钥。"""

import argparse
import base64
import json
import os
from pathlib import Path
import plistlib
import re
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
ENV_KEYS = {
    "version": "PERCH_VERSION",
    "build": "PERCH_BUILD_NUMBER",
    "feedURL": "PERCH_SPARKLE_FEED_URL",
    "publicEDKey": "PERCH_SPARKLE_PUBLIC_KEY",
}


def load_configuration(path, environ=None):
    environ = os.environ if environ is None else environ
    config = json.loads(Path(path).read_text())
    if not isinstance(config, dict):
        raise ValueError("发布配置必须是 JSON 对象")
    for key, env_key in ENV_KEYS.items():
        if env_key in environ:
            config[key] = environ[env_key]
    if any(not isinstance(config.get(key), str) for key in ENV_KEYS):
        raise ValueError("版本、构建号、更新地址和公钥必须都是字符串")
    if not re.fullmatch(r"\d+\.\d+\.\d+", config["version"]):
        raise ValueError("版本必须采用 major.minor.patch 格式")
    if not re.fullmatch(r"[1-9]\d*", config["build"]):
        raise ValueError("构建号必须是递增的正整数")
    feed, key = config["feedURL"], config["publicEDKey"]
    if bool(feed) != bool(key):
        raise ValueError("更新地址和公钥必须同时配置或同时留空")
    if feed:
        url = urlsplit(feed)
        if (url.scheme != "https" or not url.hostname or url.username is not None
                or url.password is not None or "#" in feed or "$" in feed
                or any(char.isspace() for char in feed)):
            raise ValueError("更新地址必须是无凭据、无片段的 HTTPS URL")
        try:
            valid_key = len(base64.b64decode(key, validate=True)) == 32
        except ValueError:
            valid_key = False
        if not valid_key:
            raise ValueError("Sparkle 公钥必须是 Base64 编码的 32 字节 Ed25519 公钥")
    return config


def apply_configuration(plist_path, config):
    path = Path(plist_path)
    info = plistlib.loads(path.read_bytes())
    info["CFBundleShortVersionString"] = config["version"]
    info["CFBundleVersion"] = config["build"]
    # 不允许静默安装，更新包必须先通过 EdDSA 验签再解压。
    info["SUAutomaticallyUpdate"] = False
    info["SUAllowsAutomaticUpdates"] = False
    info["SUVerifyUpdateBeforeExtraction"] = True
    for key in ("SUFeedURL", "SUPublicEDKey"):
        info.pop(key, None)
    if config["feedURL"]:
        info["SUFeedURL"] = config["feedURL"]
        info["SUPublicEDKey"] = config["publicEDKey"]
    path.write_bytes(plistlib.dumps(info, sort_keys=False))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=ROOT / "config/updates.json")
    parser.add_argument("--plist", type=Path)
    args = parser.parse_args()
    try:
        config = load_configuration(args.config)
        if args.plist:
            apply_configuration(args.plist, config)
    except (ValueError, OSError) as error:
        parser.exit(1, f"更新配置无效：{error}\n")
    state = "已配置" if config["feedURL"] else "尚未配置"
    print(f"Perch {config['version']} ({config['build']})；在线更新{state}")


if __name__ == "__main__":
    main()
