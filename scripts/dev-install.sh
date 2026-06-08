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
TEAM_ID="HA3AN589MD"
IDENTITY_HASH=$(security find-certificate -a -c "Apple Development" -Z | awk -v team="$TEAM_ID" '/^SHA-1 hash:/ { hash = $3 } /subj/ { if ($0 ~ team) print hash }' | head -n 1 || true)
KEYCHAIN=""

# Check if official Apple Development identity for the specific Team ID is available.
if [ -z "$IDENTITY_HASH" ]; then
    echo "⚠️  Apple Development identity for Team ID $TEAM_ID not found in keychain."
    echo "⚠️  Falling back to local self-signed dev identity"
    IDENTITY="Pop Dev Self Signed"
    KEYCHAIN="$HOME/Library/Keychains/pop-signing.keychain-db"
else
    IDENTITY="$IDENTITY_HASH"
    echo "✓ Found official Apple Development identity SHA-1: $IDENTITY"
fi

APP=".build/Build/Products/$CONFIG/Pop.app"

# Regenerate the project if needed (new files in project.yml).
if [ ! -d Pop.xcodeproj ] || [ project.yml -nt Pop.xcodeproj ]; then
    echo "▸ xcodegen generate"
    xcodegen generate
fi

echo "▸ xcodebuild ($CONFIG)"
xcodebuild -project Pop.xcodeproj -scheme Pop -configuration "$CONFIG" \
    -derivedDataPath .build CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build | tail -3

echo "▸ re-sign with stable identity: $IDENTITY"
if [ -n "$KEYCHAIN" ]; then
    security unlock-keychain -p pop "$KEYCHAIN" 2>/dev/null || true
fi

# Sign nested Mach-O (e.g. Pop.debug.dylib, frameworks) FIRST, otherwise dyld rejects them
# for having a different signing identity than the re-signed main executable.
find "$APP/Contents" \( -name "*.dylib" -o -name "*.framework" \) -print0 2>/dev/null \
  | while IFS= read -r -d '' item; do
        if [ -n "$KEYCHAIN" ]; then
            codesign --force --options runtime --sign "$IDENTITY" --keychain "$KEYCHAIN" "$item"
        else
            codesign --force --options runtime --sign "$IDENTITY" "$item"
        fi
    done

if [ -n "$KEYCHAIN" ]; then
    codesign --force --options runtime \
        --entitlements App/Pop.entitlements \
        --sign "$IDENTITY" --keychain "$KEYCHAIN" \
        "$APP"
else
    codesign --force --options runtime \
        --entitlements App/Pop.entitlements \
        --sign "$IDENTITY" \
        "$APP"
fi
codesign -d -r- "$APP" 2>&1 | grep designated || true

echo "▸ install to /Applications"
osascript -e 'quit app "Pop"' 2>/dev/null || true
pkill -f "Pop.app/Contents/MacOS/Pop" 2>/dev/null || true
sleep 0.6
rm -rf /Applications/Pop.app
cp -R "$APP" /Applications/Pop.app
open /Applications/Pop.app
echo "✓ Installed & launched: /Applications/Pop.app"
