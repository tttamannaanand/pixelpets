#!/bin/zsh
# Builds Pixel Pets.app from the sprites and app/main.swift.
set -e
cd "$(dirname "$0")"
[ -d .venv ] || { python3 -m venv .venv && .venv/bin/pip -q install pillow; }
.venv/bin/python sprites.py >/dev/null
APP="build/Pixel Pets.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 app/main.swift -o "$APP/Contents/MacOS/PixelPets" -framework AppKit -framework ServiceManagement
cp -R sprites "$APP/Contents/Resources/sprites"
rm -f "$APP/Contents/Resources/sprites/preview.png"
.venv/bin/python make_icon.py "$APP/Contents/Resources"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Pixel Pets</string>
  <key>CFBundleDisplayName</key><string>Pixel Pets</string>
  <key>CFBundleIdentifier</key><string>com.tamannaanand.pixelpets</string>
  <key>CFBundleExecutable</key><string>PixelPets</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep -s - "$APP" >/dev/null 2>&1
echo "built $APP"
