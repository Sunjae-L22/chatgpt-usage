#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build.sh
app="dist/ChatGPT Usage.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/direct/ChatGPTUsage "$app/Contents/MacOS/ChatGPTUsage"
swift scripts/icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ChatGPTUsage</string>
<key>CFBundleIdentifier</key><string>io.github.sunjae-l22.chatgpt-usage</string>
<key>CFBundleName</key><string>ChatGPT Usage</string>
<key>CFBundleDisplayName</key><string>ChatGPT Usage</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Copyright 2026 Sunjae-L22. MIT License.</string>
</dict></plist>
PLIST
codesign --force --sign "${CODE_SIGN_IDENTITY:--}" --timestamp=none "$app"
printf 'App: %s\n' "$app"
