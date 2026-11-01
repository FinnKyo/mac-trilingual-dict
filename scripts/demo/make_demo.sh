#!/bin/bash
# 生成 README 用的演示动画和截图（docs/demo-*.gif、docs/shot-*.png）。
#
# 只截调试版 App 自己的窗口（不需要屏幕录制权限，也不会拍到桌面），
# 再放进 scene.swift 画的示意场景里（虚构的阅读窗口、鼠标、选区、截图框）。需要联网，查询结果是实时的。
# 用法: scripts/demo/make_demo.sh（GIF 编码需要 ffmpeg：brew install ffmpeg）
set -euo pipefail
cd "$(dirname "$0")/../.."
WORK="$(mktemp -d)"
trap 'pkill -x DictTranslator 2>/dev/null || true; rm -rf "$WORK"' EXIT

swift build >/dev/null
swiftc -O scripts/demo/send.swift -o "$WORK/send"
swiftc -O scripts/demo/scene.swift -o "$WORK/scene"
SEND="$WORK/send"

pkill -x DictTranslator 2>/dev/null || true; sleep 1
.build/debug/DictTranslator >/dev/null 2>&1 &
sleep 3
"$WORK/scene" bubble "$WORK/bubble.png"
# 预热：App 刚启动时第一次文字识别要加载模型，要十几秒，晚到的结果会盖掉后面的画面
"$SEND" "ocr:$WORK/bubble.png"; sleep 15

shot() { "$SEND" "shot:$1"; sleep 0.35; }
fresh() {   # 收起窗口并清空输入框
  "$SEND" "hide"; sleep 0.4
  "$SEND" "hotkey"; sleep 1.2
  "$SEND" "inputcmd:a"; "$SEND" "inputtype:$(printf '\b')"; sleep 0.8
  "$SEND" "hide"; sleep 0.4
}

# ---- 演示动画（浅色）----
"$SEND" "appearance:light"
SCN="$WORK/scene_frames"; mkdir -p "$SCN"

# 直接输入：⌥A 后输入「手纸」，展示中日同形异义提醒（日语的「手紙」是信件）
fresh
"$SEND" "hotkey"; sleep 1.2
shot "$SCN/input_0.png"
"$SEND" "inputtype:手"; sleep 0.25; shot "$SCN/input_1.png"
"$SEND" "inputtype:纸"; sleep 0.25; shot "$SCN/input_2.png"
sleep 9; shot "$SCN/input_result.png"

# 划词：屏幕上的位置决定窗口高度（下方留约 520pt，和示意场景一致）
fresh
"$SEND" "select:640,560:勉強"; sleep 0.3
shot "$SCN/sel_loading.png"
sleep 9; shot "$SCN/sel_result.png"

# 截图：对示意图里的对话气泡做真实的文字识别和翻译
fresh
"$SEND" "ocr:$WORK/bubble.png"; sleep 0.1
shot "$SCN/ocr_status.png"
sleep 9; shot "$SCN/ocr_result.png"
"$SEND" "hide"

"$WORK/scene" compose "$SCN" docs

# ---- 静态截图（浅色 / 深色）----
for mode in light dark; do
  "$SEND" "appearance:$mode"
  for pair in "ja:風車" "en:run" "zh:手纸" "sentence:今日は一日中雨でしたが、夜には星がきれいに見えました。"; do
    key=${pair%%:*}; q=${pair#*:}
    fresh
    "$SEND" "hotkey"; sleep 1.2
    "$SEND" "inputtype:$q"; sleep 9
    shot "$WORK/shot.png"
    sips --resampleWidth 640 "$WORK/shot.png" --out "docs/shot-$key-$mode.png" >/dev/null
  done
done
"$SEND" "hide"
echo "==> docs/ 已更新"
