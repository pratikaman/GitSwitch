#!/bin/zsh
# Builds GitSwitch.app. Run with "install" to also copy it to ~/Applications and launch it:
#   ./build.sh install
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="GitSwitch"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

rm -rf "$BUILD_DIR"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -swift-version 5 -parse-as-library \
  -target arm64-apple-macos13.0 \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/$APP_NAME"

cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
  pkill -x "$APP_NAME" 2>/dev/null || true
  sleep 0.5
  mkdir -p ~/Applications
  rm -rf ~/Applications/"$APP_NAME".app
  cp -R "$APP" ~/Applications/
  open ~/Applications/"$APP_NAME".app
  echo "Installed to ~/Applications/$APP_NAME.app and launched."
fi
