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
RESOURCE_BUNDLE="$APP_BUNDLE/Contents/Helpers/SkillSet_SkillSetCore.bundle"
RESOURCE_PLIST="$RESOURCE_BUNDLE/Contents/Info.plist"
# 不同 SwiftPM 版本生成的资源 bundle 元数据不完整时，codesign --deep 会拒绝整个应用。
mkdir -p "$RESOURCE_BUNDLE/Contents/Resources"
if [[ ! -f "$RESOURCE_PLIST" ]]; then
    cat > "$RESOURCE_PLIST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>perch.SkillSetCore.resources</string>
<key>CFBundlePackageType</key><string>BNDL</string>
<key>CFBundleVersion</key><string>1</string>
</dict></plist>
PLIST
else
    /usr/libexec/PlistBuddy -c "Set :CFBundlePackageType BNDL" "$RESOURCE_PLIST"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string perch.SkillSetCore.resources" "$RESOURCE_PLIST" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1" "$RESOURCE_PLIST" 2>/dev/null || true
fi
codesign "${SIGN_ARGS[@]}" "$RESOURCE_BUNDLE"
codesign "${SIGN_ARGS[@]}" "$APP_BUNDLE/Contents/Helpers/skillset"
codesign "${SIGN_ARGS[@]}" "$APP_BUNDLE"
# Xcode 16.4 对 SwiftPM 资源 bundle 的 --deep 校验不稳定，逐个校验仍能覆盖所有嵌套代码。
codesign --verify --strict --verbose=2 "$FRAMEWORK"
codesign --verify --strict --verbose=2 "$RESOURCE_BUNDLE"
codesign --verify --strict --verbose=2 "$APP_BUNDLE/Contents/Helpers/skillset"
codesign --verify --strict --verbose=2 "$APP_BUNDLE"
