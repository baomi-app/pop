#!/bin/bash
# Build Pop, re-sign with the stable self-signed dev identity, and install to /Applications.
# Signing with a STABLE identity (not the default ad-hoc) keeps the app's designated
# requirement constant across rebuilds, so macOS does NOT reset Screen Recording (TCC)
# permission every time you rebuild. Grant the permission once; it then persists.
#
# One-time setup of the identity lives in scripts/setup-signing.sh.
# Usage: scripts/dev-install.sh [Debug|Release]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-Debug}"
IDENTITY="Pop Dev Self Signed"
KEYCHAIN="$HOME/Library/Keychains/pop-signing.keychain-db"
APP=".build/Build/Products/$CONFIG/Pop.app"

# Regenerate the project if needed (new files in project.yml).
if [ ! -d Pop.xcodeproj ] || [ project.yml -nt Pop.xcodeproj ]; then
    echo "▸ xcodegen generate"
    xcodegen generate
fi

echo "▸ xcodebuild ($CONFIG)"
xcodebuild -project Pop.xcodeproj -scheme Pop -configuration "$CONFIG" \
    -derivedDataPath .build build | tail -3

echo "▸ re-sign with stable identity: $IDENTITY"
security unlock-keychain -p pop "$KEYCHAIN" 2>/dev/null || true
# Sign nested Mach-O (e.g. Pop.debug.dylib, frameworks) FIRST, otherwise dyld rejects them
# for having a different signing identity than the re-signed main executable.
find "$APP/Contents" \( -name "*.dylib" -o -name "*.framework" \) -print0 2>/dev/null \
  | while IFS= read -r -d '' item; do
        codesign --force --options runtime --sign "$IDENTITY" --keychain "$KEYCHAIN" "$item"
    done
codesign --force --options runtime \
    --entitlements App/Pop.entitlements \
    --sign "$IDENTITY" --keychain "$KEYCHAIN" \
    "$APP"
codesign -d -r- "$APP" 2>&1 | grep designated || true

echo "▸ install to /Applications"
osascript -e 'quit app "Pop"' 2>/dev/null || true
pkill -f "Pop.app/Contents/MacOS/Pop" 2>/dev/null || true
sleep 0.6
rm -rf /Applications/Pop.app
cp -R "$APP" /Applications/Pop.app
open /Applications/Pop.app
echo "✓ Installed & launched: /Applications/Pop.app"
