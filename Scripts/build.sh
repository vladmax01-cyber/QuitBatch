#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
build_dir="${TMPDIR:-/private/tmp/}AppCloserBuild"
app_dir="$build_dir/QuitBatch.app"

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
iconset="$build_dir/AppCloser.iconset"
mkdir -p "$iconset"
xcrun swift "$project_dir/Scripts/make_icon.swift" "$build_dir/icon-1024.png"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$build_dir/icon-1024.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$build_dir/icon-1024.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app_dir/Contents/Resources/AppCloser.icns"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>QuitBatch</string>
  <key>CFBundleDisplayName</key><string>QuitBatch</string>
  <key>CFBundleIdentifier</key><string>com.vladikmartinez.appcloser</string>
  <key>CFBundleExecutable</key><string>QuitBatch</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>AppCloser</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

xcrun swiftc -O -target arm64-apple-macosx14.0 \
  -framework AppKit -framework SwiftUI -framework Carbon -framework ServiceManagement \
  "$project_dir"/Sources/*.swift -o "$app_dir/Contents/MacOS/QuitBatch"
xattr -cr "$app_dir"
codesign --force --deep --sign - "$app_dir"
echo "$app_dir"
