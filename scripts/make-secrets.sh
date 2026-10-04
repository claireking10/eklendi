#!/usr/bin/env bash
# Generates Config/Secrets.xcconfig from GoogleService-Info.plist (repo root).
# Run on the Mac before `xcodegen`, or let CI run it.
set -euo pipefail
cd "$(dirname "$0")/.."
PLIST=GoogleService-Info.plist
if [ ! -f "$PLIST" ]; then
  echo "Missing $PLIST in repo root. Ask Zach for it (never commit it)." >&2
  cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
  exit 0
fi
APP_ID=$(/usr/libexec/PlistBuddy -c "Print :GOOGLE_APP_ID" "$PLIST" 2>/dev/null || python3 -c "import plistlib;print(plistlib.load(open('$PLIST','rb'))['GOOGLE_APP_ID'])")
echo "ENCODED_APP_ID = ${APP_ID//:/-}" > Config/Secrets.xcconfig
echo "Wrote Config/Secrets.xcconfig"
