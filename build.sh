#!/bin/bash
# Builds Framecast.app into ./build. Usage: ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release 2>&1 | grep -v "warning:" | grep -v "^ *|" | grep -v "^ *\`-" | grep -v "^$" || true
BIN="$(swift build -c release --show-bin-path)/Framecast"
[ -x "$BIN" ] || { echo "Build failed"; exit 1; }

APP="build/Framecast.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Framecast"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
[ -d Resources/skill ] && cp -R Resources/skill "$APP/Contents/Resources/skill"

# Sign with a stable local identity when one exists so macOS remembers the
# camera / microphone / screen-recording permissions between rebuilds.
LOCAL_ID="Framecast Local Signing"
if [ -n "${FRAMECAST_SIGN_IDENTITY:-}" ]; then IDENTITY="$FRAMECAST_SIGN_IDENTITY"
elif security find-identity -p codesigning 2>/dev/null | grep -q "$LOCAL_ID"; then IDENTITY="$LOCAL_ID"
else IDENTITY="-"; fi
codesign --force --sign "$IDENTITY" --identifier local.framecast.app "$APP"
echo "Built $APP"
