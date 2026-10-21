#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
SOURCE="assets/brand/perch-primary.png"
ICONSET="assets/brand/Perch.appiconset"

command -v ffmpeg >/dev/null || {
    echo "需要 ffmpeg 才能重新生成 Perch 图标。" >&2
    exit 1
}
command -v rsvg-convert >/dev/null || {
    echo "需要 rsvg-convert 才能重新生成 Perch 图标。" >&2
    exit 1
}

# 仅裁掉透明边距，不改动猫头鹰、羽毛阴影和档案夹本身。
ffmpeg -loglevel error -y -i "$SOURCE" \
    -vf "crop=758:1194:258:32,format=rgba" \
    -frames:v 1 "assets/brand/perch-appicon-art.png"

rsvg-convert -w 1024 -h 1024 \
    "assets/brand/perch-appicon.svg" \
    -o "assets/brand/perch-appicon-1024.png"

while read -r name size; do
    ffmpeg -loglevel error -y -i "assets/brand/perch-appicon-1024.png" \
        -vf "scale=${size}:${size}:flags=lanczos,format=rgba" \
        -frames:v 1 "${ICONSET}/${name}"
done <<'EOF'
perch-16.png 16
perch-32.png 32
perch-32-1x.png 32
perch-64.png 64
perch-128.png 128
perch-256.png 256
perch-256-1x.png 256
perch-512.png 512
perch-512-1x.png 512
perch-1024.png 1024
EOF

# 界面和 Dock 从同一主标生成，避免只更新其中一处后品牌配色漂移。
UI_ASSET="Sources/SkillSetApp/Resources/Theme.xcassets/PerchLogo.imageset"
mkdir -p "$UI_ASSET"
cp "${ICONSET}/perch-128.png" "${UI_ASSET}/perch-128.png"
cp "${ICONSET}/perch-256.png" "${UI_ASSET}/perch-256.png"

echo "Perch 图标已生成：${ICONSET}"
