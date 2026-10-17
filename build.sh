#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Keep the original bundle identifier below to preserve existing permissions and settings.
app="$PWD/dist/Glissando.app"
if pgrep -f "$app/Contents/MacOS/Glissando" >/dev/null 2>&1; then
    echo "Quit Glissando from its menu before rebuilding its bundle." >&2
    exit 1
fi
swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
mkdir -p dist
stage="$PWD/dist/.Glissando-$$.app"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/Contents/MacOS" "$stage/Contents/Resources"
cp "$bin_dir/Glissando" "$stage/Contents/MacOS/Glissando"
cat > "$stage/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleIdentifier</key><string>ch.nicolas.WindowDrag</string>
    <key>CFBundleName</key><string>Glissando</string>
    <key>CFBundleDisplayName</key><string>Glissando</string>
    <key>CFBundleExecutable</key><string>Glissando</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST

swift tools/make-icon.swift "$stage/Contents/Resources/AppIcon.icns"

# A stable local development identity avoids re-granting Accessibility on each
# rebuild. SIGNING_IDENTITY=- explicitly opts into temporary ad hoc signing.
identity="${SIGNING_IDENTITY:-}"
if [ -z "$identity" ]; then
    identity="$(security find-identity -v -p codesigning | awk '/"Apple Development:|"Developer ID Application:/ {print $2; exit}')"
fi
if [ -z "$identity" ]; then
    identity=-
    echo "No signing identity found; using ad hoc signing. Rebuilding may require a new Accessibility grant." >&2
fi
codesign --force --options runtime --sign "$identity" --identifier ch.nicolas.WindowDrag "$stage"
codesign --verify --deep --strict "$stage"
plutil -lint "$stage/Contents/Info.plist"

previous="$PWD/dist/.Glissando-previous.app"
if [ -e "$previous" ]; then
    echo "A previous build backup exists at $previous; inspect it before replacing the app." >&2
    exit 1
fi
if [ -e "$app" ]; then mv "$app" "$previous"; fi
if ! mv "$stage" "$app"; then
    if [ -e "$previous" ]; then mv "$previous" "$app"; fi
    exit 1
fi
if [ -e "$previous" ]; then rm -rf "$previous"; fi
echo "Built $app"
echo "Launch with: open '$app'"
