#!/bin/zsh
# 本机构建并安装 Veil.app（release，优先用 Developer ID 签名）
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Veil.app"
swift build -c release --arch arm64

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Veil "$APP/Contents/MacOS/Veil"

# 图标统一用仓库里的 Resources/AppIcon.icns，和 CI 打包用的是同一份。
# 要改图标时用 Scripts/make-icon.swift 重新生成它（见 README「从源码构建」）
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# 构建号：VEIL_BUILD 优先，否则取提交数；不在 git 仓库里（如源码 zip）时退回 1
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD="${VEIL_BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
sed -e "s/@VERSION@/$VERSION/" -e "s/@BUILD@/$BUILD/" Resources/Info.plist.in > "$APP/Contents/Info.plist"

# 用固定证书签名：辅助功能权限绑定签名，ad-hoc 签名每次构建都会变，授权会失效
# 没有证书时 grep 失败，不能让 pipefail 中断构建，要退回 ad-hoc
SIGN_ID="${VEIL_SIGN_ID:-$(security find-identity -v -p codesigning | grep -m1 "Developer ID Application" | awk '{print $2}' || true)}"
codesign --force --deep --options runtime --sign "${SIGN_ID:--}" "$APP"
echo "✓ 已生成 $APP"

# 安装到 /Applications：系统权限、登录项都以固定位置的应用为准
if [[ "${VEIL_NO_INSTALL:-}" != "1" ]]; then
  pkill -x Veil 2>/dev/null || true
  rm -rf /Applications/Veil.app
  ditto "$APP" /Applications/Veil.app
  echo "✓ 已安装到 /Applications/Veil.app"
fi
