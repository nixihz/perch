#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE="${1:?请传入 .app 路径}"
SIGNING_IDENTITY="${PERCH_SIGNING_IDENTITY:--}"
FRAMEWORK="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
SIGN_ARGS=(--force --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    SIGN_ARGS+=(--options runtime --timestamp)
fi

# 嵌套组件从内向外签名，避免用 --deep 签名掩盖遗漏的嵌套可执行文件。
codesign "${SIGN_ARGS[@]}" "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
codesign "${SIGN_ARGS[@]}" "$FRAMEWORK/Versions/B/XPCServices/Installer.xpc"
codesign "${SIGN_ARGS[@]}" "$FRAMEWORK/Versions/B/Autoupdate"
codesign "${SIGN_ARGS[@]}" "$FRAMEWORK/Versions/B/Updater.app"
codesign "${SIGN_ARGS[@]}" "$FRAMEWORK"
# Helpers 属于嵌套代码目录，Release 的纯资源 bundle 也必须独立签名。
codesign "${SIGN_ARGS[@]}" "$APP_BUNDLE/Contents/Helpers/SkillSet_SkillSetCore.bundle"
codesign "${SIGN_ARGS[@]}" "$APP_BUNDLE/Contents/Helpers/skillset"
codesign "${SIGN_ARGS[@]}" "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
