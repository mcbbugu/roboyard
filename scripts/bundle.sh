#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build -c release --product RoboYard
BIN="$(swift build -c release --show-bin-path)/RoboYard"
APP="$ROOT/dist/RoboYard.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/RoboYard"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "$APP"
