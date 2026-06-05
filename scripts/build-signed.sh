#!/usr/bin/env bash
#
# build-signed.sh — produce a properly code-signed local build of Husky Notes.
#
# Works around two problems caused by the repo living in an iCloud-synced folder
# (~/Documents):
#   1. iCloud stamps build products with extended attributes that `codesign`
#      rejects ("resource fork, Finder information, or similar detritus not
#      allowed"). We strip xattrs from the sources and build OUTSIDE the synced
#      folder so the products stay clean.
#   2. iCloud conflict copies like "HuskyNotes 2.xcodeproj" confuse `xcodebuild`
#      (it sees two projects). We remove the stray copy.
#
# Usage:
#   scripts/build-signed.sh [scheme] [configuration]
#   scripts/build-signed.sh                         # HuskyNotes-macOS, Debug
#   scripts/build-signed.sh HuskyNotes-macOS Release
#
# Env:
#   HUSKY_DERIVED_DATA   override the (non-synced) DerivedData path.
#
set -euo pipefail

SCHEME="${1:-HuskyNotes-macOS}"
CONFIG="${2:-Debug}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="${HUSKY_DERIVED_DATA:-${TMPDIR:-/tmp}/huskynotes-build}"

cd "$ROOT"
echo "▸ Repo:        $ROOT"
echo "▸ Scheme:      $SCHEME ($CONFIG)"
echo "▸ DerivedData: $DERIVED  (outside iCloud)"

# 1. Strip iCloud/Finder extended attributes that break codesign.
echo "▸ Stripping extended attributes from sources…"
xattr -cr HuskyNotes Shared ShareExtension Widgets 2>/dev/null || true

# 2. Regenerate the project + drop any iCloud conflict copy.
if command -v xcodegen >/dev/null 2>&1; then
  echo "▸ Regenerating project (xcodegen)…"
  xcodegen generate >/dev/null
fi
rm -rf "HuskyNotes 2.xcodeproj"

# 3. Signed build to the non-synced DerivedData.
echo "▸ Building (signed)…"
xcodebuild -project HuskyNotes.xcodeproj -scheme "$SCHEME" -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" -allowProvisioningUpdates build

# 4. Verify the signature (macOS .app products).
APP="$(/usr/bin/find "$DERIVED/Build/Products/$CONFIG" -maxdepth 1 -name '*.app' 2>/dev/null | head -1)"
if [[ -n "${APP:-}" ]]; then
  echo "▸ Built: $APP"
  echo "▸ Verifying signature…"
  codesign --verify --deep --strict --verbose=1 "$APP" || true
  codesign -dvv "$APP" 2>&1 | grep -iE 'Authority=Apple|TeamIdentifier|Identifier=' || true
fi
echo "✓ Done."
