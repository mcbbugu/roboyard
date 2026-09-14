#!/bin/sh
# 4.0 shipping: notarize dist/RoboYard.app with notarytool, then staple.
# Needs: APPLE_ID, APP_PASSWORD (app-specific), TEAM_ID in the environment.
# Without them this script prints what to do and exits 2 (never blocks CI).
set -u
cd "$(dirname "$0")/.."

if [ -z "${APPLE_ID:-}" ] || [ -z "${APP_PASSWORD:-}" ] || [ -z "${TEAM_ID:-}" ]; then
  echo "notarize: set APPLE_ID, APP_PASSWORD, TEAM_ID first." >&2
  echo "Then: APPLE_ID=you@x.com APP_PASSWORD=xxxx TEAM_ID=YYYYYYYYYY scripts/notarize.sh" >&2
  exit 2
fi

APP="${1:-dist/RoboYard.app}"
ZIP="dist/RoboYard-notarize.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --apple-id "$APPLE_ID" --password "$APP_PASSWORD" --team-id "$TEAM_ID" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
