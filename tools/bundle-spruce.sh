#!/bin/bash
# Builds Spruce.app. Everything is built under ~/Library/Caches: this repo lives in iCloud-synced Documents,
# where the file provider tags bundles with attributes that make codesign refuse them.
# `tools/bundle-spruce.sh --install` also copies it to /Applications; `--share` makes a zip in dist/ (see the end).
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
    <key>CFBundleURLTypes</key>
    <array><dict>
        <key>CFBundleURLName</key><string>dev.andrewcarrier.spruce.unlock</string>
        <key>CFBundleURLSchemes</key><array><string>spruce</string></array>
    </dict></array>
</dict>
</plist>
PLIST

# Full Disk Access is tied to the app's signature, and an ad-hoc signature changes on every build, which would
# silently drop the permission. So sign with a real certificate when there is one: a Developer ID (for sharing; needs
# the paid Apple Developer Program) if present, else this Mac's Apple Development certificate (this Mac only).
# Switching certificates changes the signature once, so Full Disk Access has to be granted again after that switch.
CERTS=$(security find-identity -v -p codesigning)
IDENTITY=$(echo "$CERTS" | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)
[ -z "$IDENTITY" ] && IDENTITY=$(echo "$CERTS" | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)
xattr -cr "$APP"
# Hardened runtime: blocks code injection (DYLD_* variables, unsigned libraries). Notarization requires it.
SIGN=(--force --options runtime --sign "${IDENTITY:--}")
case "$IDENTITY" in "Developer ID"*) SIGN+=(--timestamp) ;; esac
codesign "${SIGN[@]}" "$APP"
echo "Built $APP (signed: ${IDENTITY:-ad-hoc}, hardened runtime)"

if [ "${1:-}" = "--install" ]; then
    rm -rf /Applications/Spruce.app
    ditto "$APP" /Applications/Spruce.app
    echo "Installed /Applications/Spruce.app"
fi

# `--share`: a zip in dist/ to hand out. With a Developer ID certificate and notary credentials saved once with
#   xcrun notarytool store-credentials spruce-notary --apple-id <you> --team-id <team>
# it's notarized and stapled, so it opens with no warning. Without them, people have to click Open Anyway once.
if [ "${1:-}" = "--share" ]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
    mkdir -p dist
    ZIP="dist/Spruce-$VERSION.zip"
    rm -f "$ZIP"
    case "$IDENTITY" in
        "Developer ID"*)
            ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
            xcrun notarytool submit "$OUT/notarize.zip" --keychain-profile "${NOTARY_PROFILE:-spruce-notary}" --wait
            xcrun stapler staple "$APP"
            rm -f "$OUT/notarize.zip"
            echo "Notarized and stapled." ;;
        *) echo "No Developer ID certificate: the zip isn't notarized, so people click Open Anyway once." ;;
    esac
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Shared build: $ZIP"
fi
