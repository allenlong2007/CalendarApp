#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BRIDGE_APP="$PWD/build/ShivanCalendarBridge.app"
mkdir -p "$BRIDGE_APP/Contents/MacOS"
cat > "$BRIDGE_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.footsoregnu3115.shivan-calendar-bridge</string>
<key>CFBundleName</key><string>Shivan Calendar Bridge</string>
<key>CFBundleExecutable</key><string>ShivanCalendarBridge</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
<key>NSCalendarsFullAccessUsageDescription</key><string>Shivan uses your calendars to add confirmed events from your Grok bots and manage their Important flag.</string>
<key>NSCalendarsUsageDescription</key><string>Shivan uses your calendars to manage confirmed events.</string>
</dict></plist>
PLIST
xcrun swiftc -swift-version 6 -parse-as-library \
  CalendarApp/EventKitLayer/EventImportance.swift \
  CalendarApp/EventKitLayer/CalendarBridgeRequest.swift \
  scripts/shivan-bridge/Main.swift \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$BRIDGE_APP/Contents/Info.plist" \
  -o "$BRIDGE_APP/Contents/MacOS/ShivanCalendarBridge"
codesign --force --sign "${SHIVAN_SIGN_IDENTITY:-Apple Development: footsoregnu3115@gmail.com (2RD5UYGAB4)}" "$BRIDGE_APP"
printf '%s\n' "$BRIDGE_APP/Contents/MacOS/ShivanCalendarBridge"
