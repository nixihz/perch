#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
APP_NAME="SkillSet"
APP_PRODUCT="SkillSetDesktop"
DIST_DIR="${PERCH_DIST_DIR:-dist}"
APP_BUNDLE="$DIST_DIR/栖集.app"
BRAND_ICONSET="assets/brand/Perch.appiconset"
BUILD_ARGS=(-c debug)
OPEN_APP=true
VERIFY_APP=false
for argument in "$@"; do
    case "$argument" in
        --release) BUILD_ARGS[1]=release ;;
        --universal) BUILD_ARGS+=(--arch arm64 --arch x86_64) ;;
        --no-open) OPEN_APP=false ;;
        --verify) VERIFY_APP=true ;;
        *) echo "未知参数：$argument" >&2; exit 2 ;;
    esac
done
if [[ -n "${PERCH_BUILD_PATH:-}" ]]; then
    BUILD_ARGS+=(--scratch-path "$PERCH_BUILD_PATH")
fi
UPDATE_CONFIG="${PERCH_UPDATE_CONFIG:-config/updates.json}"
python3 script/configure_updates.py --config "$UPDATE_CONFIG"

swift build "${BUILD_ARGS[@]}" --product "$APP_PRODUCT"
swift build "${BUILD_ARGS[@]}" --product "skillset"

BUILD_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
BIN_PATH="$BUILD_DIR/${APP_PRODUCT}"
CLI_PATH="$BUILD_DIR/skillset"
# Dock 可能沿用包文件名；迁移旧产物后统一重建，避免保留两个同标识的应用。
if [[ -d "$DIST_DIR/${APP_NAME}.app" && ! -e "$APP_BUNDLE" ]]; then
    mv "$DIST_DIR/${APP_NAME}.app" "$APP_BUNDLE"
fi
rm -rf "$APP_BUNDLE"
mkdir -p "$DIST_DIR"
cp "$CLI_PATH" "$DIST_DIR/skillset"
# CLI 需要同目录的 SwiftPM 资源；独立命令不能只复制 Mach-O 本体。
rm -rf "$DIST_DIR/SkillSet_SkillSetCore.bundle"
cp -R "$BUILD_DIR/SkillSet_SkillSetCore.bundle" "$DIST_DIR/"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$APP_BUNDLE/Contents/Helpers"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
# Helpers 使用独立目录，避免大小写不敏感文件系统覆盖 GUI 的 SkillSet。
cp "$CLI_PATH" "$APP_BUNDLE/Contents/Helpers/skillset"
cp -R "$BUILD_DIR/SkillSet_SkillSetCore.bundle" "$APP_BUNDLE/Contents/Helpers/"
cp -R "$BUILD_DIR/SkillSet_SkillSetCore.bundle" "$APP_BUNDLE/Contents/Resources/"
cp -R "$BUILD_DIR/SkillSet_SkillSetApp.bundle" "$APP_BUNDLE/Contents/Resources/"
python3 script/package_library.py . "$APP_BUNDLE/Contents/Resources/SkillSetLibrary"
rm -rf "$DIST_DIR/SkillSetLibrary"
cp -R "$APP_BUNDLE/Contents/Resources/SkillSetLibrary" "$DIST_DIR/SkillSetLibrary"
# 原生侧栏从主 bundle 读取强调色，与 SwiftUI 共用编译后的颜色资源。
cp "$BUILD_DIR/SkillSet_SkillSetApp.bundle/Contents/Resources/Assets.car" \
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
    <string>com.xiezhixin.perch</string>
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
python3 script/configure_updates.py --config "$UPDATE_CONFIG" --plist "$APP_BUNDLE/Contents/Info.plist"

# 保留 Sparkle 的版本软链、XPC 服务和可执行位，搬出构建目录后仍能运行。
mkdir -p "$APP_BUNDLE/Contents/Frameworks"
SPARKLE_FRAMEWORK="${PERCH_BUILD_PATH:-.build}/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
ditto "$SPARKLE_FRAMEWORK" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"

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
bash script/sign_app.sh "$APP_BUNDLE"
python3 script/verify_mcp_package.py "$APP_BUNDLE/Contents/Helpers/skillset" "$DIST_DIR/skillset"
echo "应用已打包：$APP_BUNDLE"
if [[ "$OPEN_APP" == false ]]; then
    exit 0
fi
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$APP_BUNDLE" >/dev/null 2>&1 || true

pkill -x "$APP_NAME" 2>/dev/null || true
/usr/bin/open -n "$APP_BUNDLE"

if [[ "$VERIFY_APP" == true ]]; then
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    echo "栖集 / Perch（栖集.app）已启动"
fi
