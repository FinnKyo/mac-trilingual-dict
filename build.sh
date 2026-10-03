#!/bin/bash
# 编译并打包为 .app，签名后安装到 /Applications
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="DictTranslator"
APP_DIR="build/${APP_NAME}.app"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"

# 默认编译通用二进制（Apple 芯片 + Intel），可用 ARCHS="arm64" 只编译本机架构
read -r -a ARCH_LIST <<< "${ARCHS:-arm64 x86_64}"
ARCH_FLAGS=()
for a in "${ARCH_LIST[@]}"; do ARCH_FLAGS+=(--arch "$a"); done

echo "==> 编译 (release: ${ARCH_LIST[*]})"
mkdir -p build
if ! swift build -c release "${ARCH_FLAGS[@]}" > build/build.log 2>&1; then
  cat build/build.log; echo "编译失败"; exit 1
fi
grep -v "x86_64 architecture is deprecated" build/build.log | tail -1
BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

echo "==> 打包 ${APP_DIR}"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/"
cp Resources/Info.plist "$APP_DIR/Contents/"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/"
for b in "$BIN_DIR"/*.bundle; do
  [ -e "$b" ] && cp -R "$b" "$APP_DIR/Contents/Resources/"
done

echo "==> 签名"
# 优先使用开发者证书（重新编译后系统权限不会失效），没有则用临时签名
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
if [ -n "$IDENTITY" ]; then
  echo "    使用证书: $IDENTITY"
  codesign --force --deep --options runtime --timestamp=none --sign "$IDENTITY" "$APP_DIR"
else
  echo "    未找到开发者证书，使用 ad-hoc 签名（每次重新编译后需要重新授权辅助功能）"
  codesign --force --deep --sign - "$APP_DIR"
fi
codesign --verify --deep --strict "$APP_DIR"

if [ "${NO_INSTALL:-0}" != "1" ]; then
  echo "==> 安装到 ${INSTALL_DIR}"
  pkill -x "$APP_NAME" 2>/dev/null || true
  sleep 0.5
  rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
  cp -R "$APP_DIR" "${INSTALL_DIR}/"
  echo "==> 完成：open \"${INSTALL_DIR}/${APP_NAME}.app\""
fi
