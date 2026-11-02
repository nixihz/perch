#!/usr/bin/env python3
"""共用发布凭据检查；用客户端公钥验签，避免误用其他应用的私钥。"""

import base64
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile


def capture(arguments, label, timeout=60):
    result = subprocess.run([str(value) for value in arguments], capture_output=True,
                            timeout=timeout, check=False)
    if result.returncode:
        # 签名工具的错误可能包含私钥原文，因此只报告步骤和退出码。
        raise ValueError(f"{label}失败（退出码 {result.returncode}）")
    return result.stdout.decode().strip()


def signer_options(account=None, ed_key_file=None):
    if account and ed_key_file:
        raise ValueError("--account 与 --ed-key-file 只能选择一个")
    if ed_key_file:
        key = Path(ed_key_file).expanduser()
        if key.is_symlink() or not key.is_file() or key.stat().st_mode & 0o077:
            raise ValueError("Sparkle 私钥必须是仅所有者可访问的普通文件（权限 0600）")
        return ["--ed-key-file", str(key.resolve())]
    return ["--account", account or "com.xiezhixin.perch"]


def verify_signature(archive, signature, public_key):
    public_bytes = base64.b64decode(public_key, validate=True)
    signature_bytes = base64.b64decode(signature, validate=True)
    if len(public_bytes) != 32 or len(signature_bytes) != 64:
        raise ValueError("Sparkle 公钥或签名长度无效")
    with tempfile.TemporaryDirectory(prefix="perch-verify-") as temporary:
        directory = Path(temporary)
        public_path = directory / "public.der"
        signature_path = directory / "signature.bin"
        public_path.write_bytes(bytes.fromhex("302a300506032b6570032100") + public_bytes)
        signature_path.write_bytes(signature_bytes)
        capture(["openssl", "pkeyutl", "-verify", "-pubin", "-inkey", public_path,
                 "-keyform", "DER", "-rawin", "-in", archive, "-sigfile", signature_path],
                "客户端公钥验签", timeout=120)


def check_sparkle(sparkle_bin, public_key, account=None, ed_key_file=None):
    for name in ("sign_update", "generate_appcast"):
        if not os.access(sparkle_bin / name, os.X_OK):
            raise ValueError(f"缺少 Sparkle 工具 {sparkle_bin / name}；先运行 swift package resolve")
    options = signer_options(account, ed_key_file)
    with tempfile.TemporaryDirectory(prefix="perch-signing-") as temporary:
        probe = Path(temporary) / "probe.bin"
        probe.write_bytes(b"Perch release preflight")
        signature = capture([sparkle_bin / "sign_update", *options, "-p", probe], "Sparkle 签名")
        verify_signature(probe, signature, public_key)
        capture([sparkle_bin / "sign_update", *options, "--verify", probe, signature],
                "Sparkle 官方工具验签")
    return options


def signing_identity(requested=None):
    output = capture(["security", "find-identity", "-v", "-p", "codesigning"], "签名证书检查")
    identities = [line.split('"')[1] for line in output.splitlines()
                  if '"Developer ID Application:' in line]
    if requested:
        if requested not in identities:
            raise ValueError("指定的 Developer ID Application 证书不可用")
        return requested
    if len(identities) != 1:
        raise ValueError("未找到唯一的 Developer ID Application 证书；请指定 --signing-identity")
    return identities[0]


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
