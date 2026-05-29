#!/bin/bash
# 用 xcodebuild 构建 Pop.app，并可选直接运行。
# 工程由 XcodeGen 从 project.yml 生成（首次/改了 project.yml 后跑一次 xcodegen generate）。
# 用法：scripts/make-app.sh [Debug|Release] [--run]
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-Debug}"
RUN=false
for arg in "$@"; do
    [ "$arg" = "--run" ] && RUN=true
done

# 没有工程，或 project.yml 比工程新，则重新生成
if [ ! -d Pop.xcodeproj ] || [ project.yml -nt Pop.xcodeproj ]; then
    echo "▸ xcodegen generate"
    xcodegen generate
fi

echo "▸ xcodebuild ($CONFIG)"
xcodebuild -project Pop.xcodeproj -scheme Pop -configuration "$CONFIG" \
    -derivedDataPath .build build | tail -5

APP=".build/Build/Products/$CONFIG/Pop.app"
echo "✓ 打包完成：$APP"

if $RUN; then
    pkill -f "Pop.app/Contents/MacOS/Pop" 2>/dev/null || true
    sleep 0.5
    echo "▸ 启动 Pop…（菜单栏右上角找相机图标）"
    open "$APP"
fi
