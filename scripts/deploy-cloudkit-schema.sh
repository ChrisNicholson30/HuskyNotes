#!/usr/bin/env bash
#
# deploy-cloudkit-schema.sh — inspect Husky Notes' CloudKit **Development** schema
# and check it's complete before you promote it to **Production**.
#
# IMPORTANT: `cktool` can read/validate/import the *Development* schema, but it
# CANNOT promote to Production — that is a CloudKit **Dashboard** action
# ("Deploy Schema Changes to Production"). So this script verifies Development;
# the final deploy is one click in the Dashboard (instructions printed at the end).
#
# The Development schema is created at RUNTIME: run the app (Debug) on a device or
# simulator signed into iCloud with sync ON, and create one of EVERY record type:
#   • a note with a #tag       → CD_Note, CD_Tag
#   • + an image attachment    → CD_Attachment (+ recognizedText)
#   • a folder                 → CD_Folder
#   • a to-do                  → CD_TodoItem
# Until that happens, CloudKit only has the default "Users" type and nothing syncs.
#
# Auth: save a CloudKit MANAGEMENT token to your keychain first (never committed):
#   xcrun cktool save-token --type management
#
set -euo pipefail

TEAM_ID="Y769NRY4KQ"
CONTAINER_ID="iCloud.com.huskynotes.app"
SCHEMA="${TMPDIR:-/tmp}/huskynotes-cloudkit-schema.ckdb"

echo "▸ Exporting the DEVELOPMENT schema for $CONTAINER_ID …"
xcrun cktool export-schema \
  --team-id "$TEAM_ID" --container-id "$CONTAINER_ID" \
  --environment development --output-file "$SCHEMA"

echo "▸ Record types in Development:"
grep -iE "RECORD TYPE" "$SCHEMA" | sed 's/^/    /' | sort -u

missing=0
for type in CD_Note CD_Tag CD_Folder CD_Attachment CD_TodoItem; do
  if ! grep -qi "RECORD TYPE $type" "$SCHEMA"; then
    echo "    ⚠️  MISSING: $type"
    missing=1
  fi
done

echo
if [[ "$missing" -eq 1 ]]; then
  echo "✗ The Development schema is INCOMPLETE."
  echo "  Run the app (Debug) signed into iCloud with sync ON and create one of"
  echo "  every record type (note +#tag +image attachment, folder, to-do), then"
  echo "  re-run this script. Nothing will sync until these types exist."
  exit 1
fi

echo "✓ All Husky Notes record types are present in Development."
echo
echo "Now promote to Production (cktool can't — do this in the Dashboard):"
echo "  1. https://icloud.developer.apple.com → container $CONTAINER_ID → Schema"
echo "  2. Deploy Schema Changes → Production"
echo "  3. Test cross-device sync on a TestFlight / App Store build."
