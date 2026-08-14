#!/bin/bash
# Build Debug, replace /Applications/MM.app, and relaunch it.
# One command: scripts/deploy-debug.sh
set -euo pipefail
cd "$(dirname "$0")/.."

SETTINGS=$(xcodebuild -project MM.xcodeproj -scheme MM \
    -configuration Debug -destination 'platform=macOS' -showBuildSettings)
PRODUCTS_DIR=$(echo "$SETTINGS" | awk '/^[[:space:]]*BUILT_PRODUCTS_DIR =/{print $3; exit}')
PRODUCT_NAME=$(echo "$SETTINGS" | awk '/^[[:space:]]*FULL_PRODUCT_NAME =/{print $3; exit}')
BUILD_APP="$PRODUCTS_DIR/$PRODUCT_NAME"
TARGET_APP="/Applications/MM.app"

xcodebuild -project MM.xcodeproj -scheme MM \
    -configuration Debug -destination 'platform=macOS' build

pkill -f "$TARGET_APP/Contents/MacOS" 2>/dev/null || true
for _ in 1 2 3 4 5 6; do
    pgrep -f "$TARGET_APP/Contents/MacOS" >/dev/null || break
    sleep 0.5
done
pkill -9 -f "$TARGET_APP/Contents/MacOS" 2>/dev/null || true
sleep 0.5
rm -rf "$TARGET_APP"
cp -R "$BUILD_APP" "$TARGET_APP"
open "$TARGET_APP"
sleep 1
pgrep -fl "$TARGET_APP/Contents/MacOS" | head -1
echo "Deployed: $TARGET_APP"
