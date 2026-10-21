#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
APP_NAME="SkillSet"
APP_PRODUCT="SkillSetDesktop"
APP_BUNDLE="dist/栖集.app"
BRAND_ICONSET="assets/brand/Perch.appiconset"

pkill -x "$APP_NAME" 2>/dev/null || true
swift build --product "$APP_PRODUCT"
swift build --product "skillset"

BIN_PATH="$(swift build --show-bin-path)/${APP_PRODUCT}"
CLI_PATH="$(swift build --show-bin-path)/skillset"
# Dock 可能沿用包文件名；迁移旧产物后统一重建，避免保留两个同标识的应用。
if [[ -d "dist/${APP_NAME}.app" && ! -e "$APP_BUNDLE" ]]; then
    mv "dist/${APP_NAME}.app" "$APP_BUNDLE"
fi
rm -rf "$APP_BUNDLE"
mkdir -p dist
cp "$CLI_PATH" "dist/skillset"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp -R "$(swift build --show-bin-path)/SkillSet_SkillSetCore.bundle" "$APP_BUNDLE/Contents/Resources/"
cp -R "$(swift build --show-bin-path)/SkillSet_SkillSetApp.bundle" "$APP_BUNDLE/Contents/Resources/"
# 原生侧栏从主 bundle 读取强调色，与 SwiftUI 共用编译后的颜色资源。
cp "$(swift build --show-bin-path)/SkillSet_SkillSetApp.bundle/Contents/Resources/Assets.car" \
    "$APP_BUNDLE/Contents/Resources/Assets.car"

# 从 AppIcon 单一源生成 icns，避免 PNG 资源与打包图标各自漂移。
ICON_BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/perch-icon.XXXXXX")"
trap 'rm -rf "$ICON_BUILD_DIR"' EXIT
mkdir -p "$ICON_BUILD_DIR/Perch.iconset"
cp "$BRAND_ICONSET/perch-16.png" "$ICON_BUILD_DIR/Perch.iconset/icon_16x16.png"
cp "$BRAND_ICONSET/perch-32.png" "$ICON_BUILD_DIR/Perch.iconset/icon_16x16@2x.png"
cp "$BRAND_ICONSET/perch-32-1x.png" "$ICON_BUILD_DIR/Perch.iconset/icon_32x32.png"
cp "$BRAND_ICONSET/perch-64.png" "$ICON_BUILD_DIR/Perch.iconset/icon_32x32@2x.png"
cp "$BRAND_ICONSET/perch-128.png" "$ICON_BUILD_DIR/Perch.iconset/icon_128x128.png"
cp "$BRAND_ICONSET/perch-256.png" "$ICON_BUILD_DIR/Perch.iconset/icon_128x128@2x.png"
cp "$BRAND_ICONSET/perch-256-1x.png" "$ICON_BUILD_DIR/Perch.iconset/icon_256x256.png"
cp "$BRAND_ICONSET/perch-512.png" "$ICON_BUILD_DIR/Perch.iconset/icon_256x256@2x.png"
cp "$BRAND_ICONSET/perch-512-1x.png" "$ICON_BUILD_DIR/Perch.iconset/icon_512x512.png"
cp "$BRAND_ICONSET/perch-1024.png" "$ICON_BUILD_DIR/Perch.iconset/icon_512x512@2x.png"
iconutil -c icns "$ICON_BUILD_DIR/Perch.iconset" -o "$ICON_BUILD_DIR/Perch.icns"
cp "$ICON_BUILD_DIR/Perch.icns" "$APP_BUNDLE/Contents/Resources/Perch.icns"

cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>SkillSet</string>
    <key>CFBundleIdentifier</key>
    <string>com.brian.skillset</string>
    <key>CFBundleName</key>
    <string>栖集</string>
    <key>CFBundleDisplayName</key>
    <string>栖集</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>zh_CN</string>
        <string>en</string>
    </array>
    <key>CFBundleIconFile</key>
    <string>Perch.icns</string>
    <key>NSAccentColorName</key>
    <string>AccentColor</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# Dock 固定显示中文品牌名，英文应用名保留 Perch；不迁移技术标识和数据目录。
mkdir -p "$APP_BUNDLE/Contents/Resources/zh_CN.lproj" "$APP_BUNDLE/Contents/Resources/en.lproj"
cat > "$APP_BUNDLE/Contents/Resources/zh_CN.lproj/InfoPlist.strings" <<'STRINGS'
"CFBundleName" = "栖集";
"CFBundleDisplayName" = "栖集";
STRINGS
cat > "$APP_BUNDLE/Contents/Resources/en.lproj/InfoPlist.strings" <<'STRINGS'
"CFBundleName" = "Perch";
"CFBundleDisplayName" = "栖集";
STRINGS

# 同一路径重建后刷新 LaunchServices 缓存，避免 Dock 继续显示旧图标。
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$APP_BUNDLE" >/dev/null 2>&1 || true

/usr/bin/open -n "$APP_BUNDLE"

if [[ "${1:-}" == "--verify" ]]; then
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    echo "栖集 / Perch（栖集.app）已启动"
fi
