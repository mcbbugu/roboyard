#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p docs/assets Resources "$WORK/RoboYard.iconset"
# Compile the whole app (minus the @main entry, which Preview replaces)
# so this can never rot behind a stale file list again.
SRCS=(Sources/RoboYard/*.swift)
swiftc -O -parse-as-library -module-cache-path "$WORK/cache" \
  "${SRCS[@]/Sources\/RoboYard\/RoboYardApp.swift}" \
  scripts/Preview.swift -o "$WORK/render"
"$WORK/render" "$WORK/frames"
cp "$WORK/frames/world.gif" docs/assets/world.gif
cp "$WORK/frames/040.png" docs/assets/world.png
cp "$WORK/frames/icon.png" docs/assets/app-icon.png
cp "$WORK/frames/hero.png" docs/assets/hero.png
for n in 16 32 128 256 512; do
  sips -z "$n" "$n" "$WORK/frames/icon.png" --out "$WORK/RoboYard.iconset/icon_${n}x${n}.png" >/dev/null
  sips -z "$((n * 2))" "$((n * 2))" "$WORK/frames/icon.png" --out "$WORK/RoboYard.iconset/icon_${n}x${n}@2x.png" >/dev/null
done
iconutil -c icns "$WORK/RoboYard.iconset" -o Resources/AppIcon.icns
