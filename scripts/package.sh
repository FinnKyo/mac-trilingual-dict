#!/bin/bash
# 打包 Release 用的 DMG：scripts/package.sh → build/DictTranslator-<版本>.dmg
# 打开后是「App + 应用程序文件夹」的安装窗口，背景上有拖动箭头和分步安装引导（直接把 DMG 发给别人也知道怎么装）。
# 窗口布局通过 Finder 的 AppleScript 设置；首次运行时系统可能询问是否允许终端控制 Finder，拒绝也能出包（只是没有布局）
set -euo pipefail
cd "$(dirname "$0")/.."
NO_INSTALL=1 ./build.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
NAME="中日英辞典"
DMG="build/DictTranslator-${VERSION}.dmg"
WORK="$(mktemp -d)"
MOUNT=""
cleanup() {
  [ -n "$MOUNT" ] && hdiutil detach "$MOUNT" -quiet -force 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

# 背景图：1x + 2x 合成一个 TIFF，Retina 屏上也清晰
swiftc -O scripts/dmg/background.swift -o "$WORK/background"
"$WORK/background" "$WORK"
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$WORK/background.tiff" >/dev/null

STAGE="$WORK/stage"
mkdir -p "$STAGE/.background"
ditto build/DictTranslator.app "$STAGE/DictTranslator.app"
ln -s /Applications "$STAGE/Applications"
cp "$WORK/background.tiff" "$STAGE/.background/background.tiff"

# 先做可写镜像，挂载后设置窗口布局，再压缩成只读镜像
hdiutil create -quiet -srcfolder "$STAGE" -volname "$NAME" -fs HFS+ -format UDRW -ov "$WORK/rw.dmg"
MOUNT=$(hdiutil attach "$WORK/rw.dmg" -readwrite -noverify -noautoopen | awk -F'\t' '/\/Volumes\//{print $NF}')
VOLUME=$(basename "$MOUNT")

if ! osascript <<EOF
tell application "Finder"
  tell disk "$VOLUME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 100, 840, 648}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 100
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "DictTranslator.app" of container window to {170, 130}
    set position of item "Applications" of container window to {470, 130}
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF
then
  echo "!! 未能设置 DMG 窗口布局（Finder 自动化未授权），继续打包"
fi

rm -rf "$MOUNT/.fseventsd"
sync
hdiutil detach "$MOUNT" -quiet
MOUNT=""
rm -f "$DMG"
hdiutil convert -quiet "$WORK/rw.dmg" -format ULFO -o "$DMG"
echo "==> $DMG ($(du -h "$DMG" | cut -f1))"
