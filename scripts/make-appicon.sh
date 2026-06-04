#!/usr/bin/env bash
#
# Generates the Husky Notes app-icon set (iOS + macOS sizes) from a single
# 1024×1024 source PNG, using macOS's built-in `sips`.
#
# Usage:
#   1. Save your icon artwork as a 1024×1024 PNG at:  scripts/husky-icon-source.png
#      (or pass a path:  scripts/make-appicon.sh /path/to/icon.png)
#   2. Run:  ./scripts/make-appicon.sh
#   3. xcodegen generate && build — the AppIcon set is now populated.
#
set -euo pipefail

SRC="${1:-scripts/husky-icon-source.png}"
SET="HuskyNotes/Resources/Assets.xcassets/AppIcon.appiconset"

if [ ! -f "$SRC" ]; then
  echo "❌ Source image not found: $SRC"
  echo "   Save your 1024×1024 PNG there (or pass a path as the first argument)."
  exit 1
fi

mkdir -p "$SET"

# iOS icons must be opaque (no alpha). Flatten the source onto a background
# (Blue Husky navy by default; override with $ICON_BG=RRGGBB) before resizing.
ICON_BG="${ICON_BG:-0A0D14}"
MASTER="$(mktemp -t husky-icon-master).png"
xcrun swift "$(dirname "$0")/flatten-icon.swift" "$SRC" "$MASTER" "$ICON_BG"

gen() { # gen <outfile> <pixelSize>
  sips -s format png -z "$2" "$2" "$MASTER" --out "$SET/$1" >/dev/null
}

echo "Generating icons from $SRC (background #$ICON_BG) …"
gen "icon-ios-1024.png" 1024
gen "icon-mac-16.png"     16
gen "icon-mac-32.png"     32
gen "icon-mac-64.png"     64
gen "icon-mac-128.png"   128
gen "icon-mac-256.png"   256
gen "icon-mac-512.png"   512
gen "icon-mac-1024.png" 1024

# Write the Contents.json with the generated filenames mapped to each slot.
cat > "$SET/Contents.json" <<'JSON'
{
  "images" : [
    { "filename" : "icon-ios-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    { "filename" : "icon-mac-16.png",   "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon-mac-32.png",   "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon-mac-32.png",   "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon-mac-64.png",   "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon-mac-128.png",  "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon-mac-256.png",  "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon-mac-256.png",  "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon-mac-512.png",  "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon-mac-512.png",  "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon-mac-1024.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

echo "✅ App icon generated into $SET"
echo "   Next:  xcodegen generate  (then build in Xcode)"
