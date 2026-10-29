#!/usr/bin/env bash
set -euo pipefail

SOURCE_APP="${1:?请传入构建产物 .app 路径}"
INSTALL_DIR="${2:?请传入安装目录}"
APP_NAME="$(basename "$SOURCE_APP")"
DEST_APP="$INSTALL_DIR/$APP_NAME"
TEMP_APP="$INSTALL_DIR/.${APP_NAME}.installing.$$"
BACKUP_APP="$INSTALL_DIR/.${APP_NAME}.backup.$$"
BACKUP_ACTIVE=false

if [[ ! -d "$INSTALL_DIR" ]]; then
    echo "安装目录不存在：$INSTALL_DIR" >&2
    exit 2
fi

SOURCE_DIR="$(cd "$(dirname "$SOURCE_APP")" && pwd -P)"
SOURCE_APP="$SOURCE_DIR/$APP_NAME"
DEST_DIR="$(cd "$INSTALL_DIR" && pwd -P)"
if [[ "$SOURCE_DIR" == "$DEST_DIR" ]]; then
    echo "安装目录不能与构建产物目录相同：$DEST_DIR" >&2
    exit 2
fi

cleanup() {
    rm -rf "$TEMP_APP"
    if [[ "$BACKUP_ACTIVE" == true && ! -e "$DEST_APP" && ! -L "$DEST_APP" && ( -e "$BACKUP_APP" || -L "$BACKUP_APP" ) ]]; then
        mv "$BACKUP_APP" "$DEST_APP" || true
    fi
}
trap cleanup EXIT

# 先完整复制并验签，避免安装过程中留下半成品。
ditto "$SOURCE_APP" "$TEMP_APP"
codesign --verify --deep --strict "$TEMP_APP"

# 整包替换可避开已签名文件和 Sparkle 符号链接的原地更新时间限制。
if [[ -e "$DEST_APP" || -L "$DEST_APP" ]]; then
    mv "$DEST_APP" "$BACKUP_APP"
    BACKUP_ACTIVE=true
fi
if ! mv "$TEMP_APP" "$DEST_APP"; then
    if [[ -e "$BACKUP_APP" || -L "$BACKUP_APP" ]]; then
        mv "$BACKUP_APP" "$DEST_APP"
        BACKUP_ACTIVE=false
    fi
    exit 1
fi

if ! codesign --verify --deep --strict "$DEST_APP"; then
    rm -rf "$DEST_APP"
    if [[ -e "$BACKUP_APP" || -L "$BACKUP_APP" ]]; then
        mv "$BACKUP_APP" "$DEST_APP"
        BACKUP_ACTIVE=false
    fi
    echo "安装后的应用验签失败，已恢复旧版本：$DEST_APP" >&2
    exit 1
fi

rm -rf "$BACKUP_APP"
BACKUP_ACTIVE=false
trap - EXIT
echo "应用已安装：$DEST_APP"
