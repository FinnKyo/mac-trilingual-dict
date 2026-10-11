#!/bin/bash
# 生成 README 用的演示 GIF 和截图（docs/hero-*.gif、docs/shot-*.png）。
# 用调试版 App 自己的窗口逐帧截图，不需要屏幕录制权限；需要联网（查询结果是实时的）。
# 用法: scripts/demo/make_demo.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
WORK="$(mktemp -d)"
trap 'pkill -x DictTranslator 2>/dev/null || true; rm -rf "$WORK"' EXIT

swift build >/dev/null
swiftc -O scripts/demo/send.swift -o "$WORK/send"
swiftc -O scripts/demo/mkgif.swift -o "$WORK/mkgif"
SEND="$WORK/send"

pkill -x DictTranslator 2>/dev/null || true; sleep 1
.build/debug/DictTranslator >/dev/null 2>&1 &
sleep 3

capture() {   # capture light|dark
  local mode=$1 out="$WORK/$1" n=0 f=""
  mkdir -p "$out"; : > "$out/frames.txt"
  shot() { n=$((n+1)); f=$(printf "%s/f%02d.png" "$out" $n); "$SEND" "shot:$f"; sleep 0.35; echo "$f $1" >> "$out/frames.txt"; }
  query() {   # query 名称 停留毫秒 逐段输入的文字...
    local name=$1 hold=$2; shift 2
    "$SEND" "inputcmd:a"; sleep 0.3
    for chunk in "$@"; do "$SEND" "inputtype:$chunk"; sleep 0.3; shot 260; done
    sleep 6.5; shot "$hold"; cp "$f" "$out/result_$name.png"
  }
  "$SEND" "appearance:$mode"; "$SEND" "hide"; sleep 0.5; "$SEND" "hotkey"; sleep 1.5
  "$SEND" "inputcmd:a"; "$SEND" "inputtype:$(printf '\b')"; sleep 0.8
  shot 900
  query ja 2800 "食" "べ" "た"
  query en 2600 "r" "u" "n"
  query zh 2600 "学" "习"
  query sentence 3200 "我今天去东京" "，吃了很好吃的" "寿司。"
  "$SEND" "hide"
}

capture light
capture dark
"$WORK/mkgif" "$WORK/light/frames.txt" docs/hero-light.gif EBEBEF 640
"$WORK/mkgif" "$WORK/dark/frames.txt" docs/hero-dark.gif 151517 640
for mode in light dark; do
  for k in ja en zh sentence; do
    sips --resampleWidth 640 "$WORK/$mode/result_$k.png" --out "docs/shot-$k-$mode.png" >/dev/null
  done
done
echo "==> docs/ 已更新"
