#!/bin/bash
# Build Pop.app with xcodebuild, and optionally run it directly.
# Project is generated from project.yml by XcodeGen (run 'xcodegen generate' once initially or after changing project.yml).
# Usage: scripts/make-app.sh [Debug|Release] [--run]
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-Debug}"
RUN=false
for arg in "$@"; do
    [ "$arg" = "--run" ] && RUN=true
done

# If the project doesn't exist, or project.yml is newer than the project, regenerate it.
if [ ! -d Pop.xcodeproj ] || [ project.yml -nt Pop.xcodeproj ]; then
    echo "▸ xcodegen generate"
    xcodegen generate
fi

echo "▸ xcodebuild ($CONFIG)"
xcodebuild -project Pop.xcodeproj -scheme Pop -configuration "$CONFIG" \
    -derivedDataPath .build build | tail -5

APP=".build/Build/Products/$CONFIG/Pop.app"
echo "✓ Build complete: $APP"

if $RUN; then
    pkill -f "Pop.app/Contents/MacOS/Pop" 2>/dev/null || true
    sleep 0.5
    echo "▸ Launching Pop... (look for the camera icon in the top right menu bar)"
    open "$APP"
fi
