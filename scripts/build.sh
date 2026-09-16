#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
uv sync
swift build -c release
mkdir -p "build/Audible Dictionary.app/Contents/MacOS" "build/Audible Dictionary.app/Contents/Resources"
ditto .build/release/AudibleDictionary "build/Audible Dictionary.app/Contents/MacOS/AudibleDictionary"
ditto .build/release/GRDB_GRDB.bundle "build/Audible Dictionary.app/Contents/Resources/GRDB_GRDB.bundle"
ditto .build/checkouts/GRDB.swift/LICENSE "build/Audible Dictionary.app/Contents/Resources/GRDB-LICENSE.txt"
cat > "build/Audible Dictionary.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>AudibleDictionary</string>
    <key>CFBundleIdentifier</key><string>local.audible-dictionary</string>
    <key>CFBundleName</key><string>Audible Dictionary</string>
    <key>CFBundleDisplayName</key><string>Audible Dictionary</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Add :FallbackUV string $(command -v uv)" \
    "build/Audible Dictionary.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :FallbackProject string $(pwd)" \
    "build/Audible Dictionary.app/Contents/Info.plist"
codesign --force --sign - "build/Audible Dictionary.app"
echo 'Built build/Audible Dictionary.app'
