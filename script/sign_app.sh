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
normalize_resource_bundle() {
    local resource_bundle="$1"
    local identifier="$2"
    local resource_plist="$resource_bundle/Contents/Info.plist"
    [[ -d "$resource_bundle" ]] || return 0

    # Xcode 16.4 可能把资源直接放在 bundle 根目录，先整理成标准 bundle 结构。
    mkdir -p "$resource_bundle/Contents/Resources"
    for child in "$resource_bundle"/*; do
        [[ -e "$child" ]] || continue
        case "$(basename "$child")" in
            Contents) ;;
            Info.plist)
                if [[ ! -f "$resource_plist" ]]; then
                    mv "$child" "$resource_plist"
                else
                    rm -f "$child"
                fi
                ;;
            _CodeSignature)
                rm -rf "$child"
                ;;
            *)
                mv "$child" "$resource_bundle/Contents/Resources/"
                ;;
        esac
    done

    if [[ ! -f "$resource_plist" ]]; then
        cat > "$resource_plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$identifier</string>
<key>CFBundlePackageType</key><string>BNDL</string>
<key>CFBundleVersion</key><string>1</string>
</dict></plist>
PLIST
    else
        /usr/libexec/PlistBuddy -c "Set :CFBundlePackageType BNDL" "$resource_plist"
        /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $identifier" "$resource_plist" 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1" "$resource_plist" 2>/dev/null || true
    fi
    codesign "${SIGN_ARGS[@]}" "$resource_bundle"
}

RESOURCE_BUNDLE="$APP_BUNDLE/Contents/Helpers/SkillSet_SkillSetCore.bundle"
normalize_resource_bundle "$RESOURCE_BUNDLE" "perch.SkillSetCore.resources"
normalize_resource_bundle "$APP_BUNDLE/Contents/Resources/SkillSet_SkillSetCore.bundle" "perch.SkillSetCore.resources.main"
normalize_resource_bundle "$APP_BUNDLE/Contents/Resources/SkillSet_SkillSetApp.bundle" "perch.SkillSetApp.resources"
codesign "${SIGN_ARGS[@]}" "$APP_BUNDLE/Contents/Helpers/skillset"
codesign "${SIGN_ARGS[@]}" "$APP_BUNDLE"
if [[ -d "$APP_BUNDLE/Contents/Resources/SkillSet_SkillSetCore.bundle" ]]; then
    codesign --verify --strict --verbose=2 "$APP_BUNDLE/Contents/Resources/SkillSet_SkillSetCore.bundle"
fi
if [[ -d "$APP_BUNDLE/Contents/Resources/SkillSet_SkillSetApp.bundle" ]]; then
    codesign --verify --strict --verbose=2 "$APP_BUNDLE/Contents/Resources/SkillSet_SkillSetApp.bundle"
fi
# Xcode 16.4 对 SwiftPM 资源 bundle 的 --deep 校验不稳定，逐个校验仍能覆盖所有嵌套代码。
codesign --verify --strict --verbose=2 "$FRAMEWORK"
codesign --verify --strict --verbose=2 "$RESOURCE_BUNDLE"
codesign --verify --strict --verbose=2 "$APP_BUNDLE/Contents/Helpers/skillset"
codesign --verify --strict --verbose=2 "$APP_BUNDLE"
