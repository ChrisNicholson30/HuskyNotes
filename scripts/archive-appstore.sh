#!/usr/bin/env bash
#
# archive-appstore.sh — archive + export Husky Notes for App Store / TestFlight.
#
# This is the correct channel for the sync-enabled build: the iCloud + push
# (aps-environment) entitlements can't ride a Developer ID direct-download .dmg,
# so a build with sync goes through the App Store / TestFlight.
#
# PREREQUISITES (one-time):
#   • Apple DISTRIBUTION certificate — Xcode → Settings → Accounts → CN-DESIGN LTD
#     → Manage Certificates → "+" → "Apple Distribution".  (You currently have
#     only "Apple Development", which can ARCHIVE but NOT export for App Store.)
#   • An app record in App Store Connect for the bundle id (com.huskynotes.app or
#     com.huskynotes.app.mac), matching the platform you're shipping.
#
# Uses the same iCloud workarounds as build-signed.sh (strip xattrs + build
# outside the synced ~/Documents folder).
#
# Usage:
#   scripts/archive-appstore.sh [scheme]      # default HuskyNotes-macOS
#
set -euo pipefail

SCHEME="${1:-HuskyNotes-macOS}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${HUSKY_DIST_OUT:-${TMPDIR:-/tmp}/huskynotes-dist}"
ARCHIVE="$OUT/$SCHEME.xcarchive"
PLIST="$ROOT/Config/ExportOptions-AppStore.plist"

cd "$ROOT"
echo "▸ Scheme: $SCHEME"
echo "▸ Output: $OUT  (outside iCloud)"

xattr -cr HuskyNotes Shared ShareExtension Widgets 2>/dev/null || true
command -v xcodegen >/dev/null 2>&1 && xcodegen generate >/dev/null
rm -rf "HuskyNotes 2.xcodeproj" "$OUT"
mkdir -p "$OUT"

echo "▸ Archiving (Release)…"
xcodebuild -project HuskyNotes.xcodeproj -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$OUT/dd" -archivePath "$ARCHIVE" -allowProvisioningUpdates archive

echo "▸ Exporting for App Store Connect (requires the Apple Distribution cert)…"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$PLIST" -exportPath "$OUT/export" -allowProvisioningUpdates

echo "✓ Export ready in: $OUT/export"
echo "  Upload with the Transporter app, Xcode Organizer, or:"
echo "    xcrun altool --upload-app -t macos -f \"$OUT/export/\"*.pkg \\"
echo "      --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>"
