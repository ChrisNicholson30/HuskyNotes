# Husky Notes — distribution runbook

> How to ship Husky Notes. There are **two channels**, and which one you use is
> decided by **whether sync is on**. Status: guide · Last updated: 2026‑06‑06.
> Current version: **0.2.0 (build 2)** — set in `Config/Signing.xcconfig`'s
> sibling settings (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml`).

All builds sign under **CN‑DESIGN LTD (`Y769NRY4KQ`)** — the team that owns the
identifiers + CloudKit container. Because the repo lives in iCloud‑synced
`~/Documents`, both scripts strip extended attributes and build outside the
synced folder (see [[icloud notes]] / `scripts/build-signed.sh`).

---

## Which channel?

| | **App Store / TestFlight** | **Developer ID + notarization** |
|---|---|---|
| Use when | the build has **iCloud sync** (push/iCloud entitlements) | a **local‑only** build (sync off), direct `.dmg` download |
| Cert needed | **Apple Distribution** | **Developer ID Application** |
| Entitlements | iCloud + `aps-environment` OK | **must drop** iCloud + `aps-environment` |
| Gatekeeper | handled by the store | requires **notarization + staple** |

> The current entitlements include iCloud + `aps-environment`, so the **default
> shippable build is App Store / TestFlight**. A direct‑download `.dmg` would need
> a separate local‑only entitlements variant.

---

## A. App Store / TestFlight  (recommended — matches the sync build)

**One‑time setup**
1. **Apple Distribution certificate:** Xcode → Settings → Accounts → CN‑DESIGN LTD
   → Manage Certificates → **+ → Apple Distribution**. (You currently have only
   *Apple Development*, which can archive but not export here.)
2. **App Store Connect record:** create the app for bundle id `com.huskynotes.app`
   (iOS) / `com.huskynotes.app.mac` (macOS) at appstoreconnect.apple.com.

**Build & upload**
```bash
scripts/archive-appstore.sh HuskyNotes-macOS    # or HuskyNotes-iOS
```
This archives Release and exports to App Store Connect format using
`Config/ExportOptions-AppStore.plist`. ✅ *Archiving is verified working*; the
**export** step needs the Apple Distribution cert from step 1.

Then upload the artifact in `…/export`:
- **Transporter** app (simplest), or **Xcode → Organizer → Distribute**, or
- `xcrun altool --upload-app -t macos -f …/export/*.pkg --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>`
  (an App Store Connect API key under Users and Access → Integrations → App Store Connect API).

Then in App Store Connect: add the build to **TestFlight** for beta, or submit for
review for public release.

---

## B. Developer ID + notarization  (only for a local‑only direct `.dmg`)

For a download‑from‑your‑site `.dmg`, **sync must be off** for that build (Developer
ID can't carry iCloud/push). You'd:
1. Make a **local‑only entitlements** variant (drop `icloud-*`, `aps-environment`;
   keep `app-sandbox`, `files.user-selected`, `print`).
2. **Developer ID Application** cert (Xcode → Manage Certificates → + → Developer ID).
3. Archive → export with `method: developer-id` (a separate ExportOptions).
4. Build the `.dmg` (see the earlier `build/HuskyNotes-0.2.0.dmg` packaging).
5. **Notarize + staple:**
   ```bash
   xcrun notarytool submit HuskyNotes-0.2.0.dmg \
     --apple-id contact@huskynotes.com --team-id Y769NRY4KQ --password <app-specific-pw> --wait
   xcrun stapler staple HuskyNotes-0.2.0.dmg
   ```

Ask before building this variant — it's a separate signing/entitlements setup
from the App Store path.

---

## Local signed build (testing, not distribution)

For a normal signed build to test on your Mac (incl. live CloudKit sync), use:
```bash
scripts/build-signed.sh                 # HuskyNotes-macOS, Debug
scripts/build-signed.sh HuskyNotes-macOS Release
```
It signs with your **Apple Development** cert and verifies the signature.

---

## Pre‑submission checklist
- [ ] Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml` if needed.
- [ ] CloudKit schema **deployed to Production** (`resources/CLOUDKIT_SETUP.md`).
- [ ] On‑device QA of v1.1 capture features (OCR, scanner, Siri/Shortcuts).
- [ ] App Store Connect: screenshots, privacy nutrition label (note: **no tracking,
      no third‑party data collection** — all on‑device + the user's own iCloud).
- [ ] Confirm the welcome/demo note reads well on a fresh install.
