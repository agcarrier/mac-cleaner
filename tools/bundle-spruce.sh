#!/bin/bash
# Builds Spruce.app. Everything is built under ~/Library/Caches: this repo lives in iCloud-synced Documents,
# where the file provider tags bundles with attributes that make codesign refuse them.
# `tools/bundle-spruce.sh --install` also copies it to /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="$HOME/Library/Caches/MacCleaner"
swift build -c release --scratch-path "$OUT/spm" --product Spruce
APP="$OUT/Spruce.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$OUT/spm/release/Spruce" "$APP/Contents/MacOS/Spruce"
[ -f art/Spruce.icns ] && cp art/Spruce.icns "$APP/Contents/Resources/Spruce.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Spruce</string>
    <key>CFBundleIconFile</key><string>Spruce</string>
    <key>CFBundleIdentifier</key><string>dev.andrewcarrier.spruce</string>
    <key>CFBundleName</key><string>Spruce</string>
    <key>CFBundleDisplayName</key><string>Spruce</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Full Disk Access is tied to the app's signature, and an ad-hoc signature changes on every build, which would
# silently drop the permission. So sign with this Mac's Apple Development certificate when there is one.
# Local use only: sharing needs a Developer ID certificate and notarization, which this script does not do.
IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)
xattr -cr "$APP"
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Built $APP (signed: ${IDENTITY:-ad-hoc})"

if [ "${1:-}" = "--install" ]; then
    rm -rf /Applications/Spruce.app
    ditto "$APP" /Applications/Spruce.app
    echo "Installed /Applications/Spruce.app"
fi
