# Husky Notes — iCloud (CloudKit) setup & sync runbook

> How to take CloudKit sync from "coded but staged" to "live", and verify it.
> **No server is involved** — sync uses each user's *own private* CloudKit
> database. Status: setup guide · Last updated: 2026‑06‑06.

The code is already complete: `PersistenceController` builds a
`.private(iCloud.com.huskynotes.app)` store when sync is enabled and an iCloud
identity is present, and the Settings → **iCloud Sync** toggle writes the flag.
What remains is Apple‑account / Dashboard / device configuration.

---

## 0. The signing team (done in code)

The Apple Developer team is now set in **one** place — `Config/Signing.xcconfig`
(`DEVELOPMENT_TEAM`) — and flows to every target. It currently defaults to
**`49D748N8ZR`** (the team whose signing cert is installed locally).

> ⚠️ **Container ownership gotcha.** A CloudKit container identifier is globally
> unique and owned by exactly one team. `iCloud.com.huskynotes.app` must be owned
> by the team in `Signing.xcconfig`. If that identifier was already registered
> under your *other* team (`Y769NRY4KQ`), team `49D748N8ZR` **cannot reuse it** —
> you must either:
> - set `DEVELOPMENT_TEAM = Y769NRY4KQ` (and install that team's cert), **or**
> - choose a new identifier owned by `49D748N8ZR` (e.g. `iCloud.HuskyNotes`) and
>   change it in **three** places: `Config/Signing.xcconfig` note,
>   both `HuskyNotes/App/HuskyNotes-*.entitlements` files, and
>   `PersistenceController.cloudKitContainerID`.

---

## 1. Create / own the container

1. Open the project in Xcode (`xcodegen generate && open HuskyNotes.xcodeproj`).
2. For **both** app targets (iOS, macOS) → Signing & Capabilities:
   - Confirm **Team** = the one in `Signing.xcconfig`.
   - Ensure the **iCloud** capability is on with **CloudKit** checked and the
     container `iCloud.com.huskynotes.app` ticked. If the container doesn't exist
     yet, Xcode offers to create it under the selected team (or create it in the
     Apple Developer portal → Identifiers → iCloud Containers).
3. The App Group (`group.com.huskynotes.*`, used by widgets/share‑extension) is
   local‑only and unrelated to sync — leave as is.

## 2. Create the schema (Development) and deploy it (Production)

SwiftData + CloudKit auto‑creates record types the **first time the app runs with
sync on**, in the CloudKit **Development** environment.

1. Run the app (Debug) on a device/sim signed into iCloud, with sync enabled
   (step 3). Create a note and an attachment so every record type + field is
   exercised — **including `Attachment.recognizedText`** (the OCR field added in
   v1.1). Tip: attach an image so OCR populates `recognizedText`.
2. Open the **CloudKit Dashboard** → your container → **Schema**. Confirm the
   record types exist: `CD_Note`, `CD_Tag`, `CD_Folder`, `CD_Attachment`
   (with `CD_recognizedText`), `CD_TodoItem`.
3. **Deploy Schema Changes to Production** before any public/TestFlight release.
   Re‑deploy whenever the model gains a property (the v1.1 `recognizedText`
   addition needs this).

> All `@Model` properties are defaulted and all relationships optional, so the
> schema is CloudKit‑safe and migrations are additive.

## 3. Enable sync and verify the cycle

1. In the app: **Settings → iCloud Sync → "Sync notes via iCloud"** → ON, then
   **relaunch** (the container is chosen at launch).
2. Settings should read *"Syncing via your private iCloud database."*
   (`PersistenceController.isSyncing == true`).
3. **Two‑device test:** sign both into the same iCloud account → create/edit on
   device A → it appears on device B within seconds.
4. **Offline → online test:** turn on Airplane Mode, edit on each device, go back
   online → changes reconcile without loss.
5. **Negative test:** sign out of iCloud or disable the toggle → the app falls
   back to a **local** store (no crash, no data loss) — this is the intended
   graceful degradation in `PersistenceController`.

## 4. Push & distribution

- CloudKit sync uses silent pushes via the **`aps-environment`** entitlement
  (present, `development`). It flips to `production` automatically through the
  provisioning profile on **TestFlight / App Store** builds.
- **Therefore a sync‑enabled build ships via the App Store / TestFlight, not the
  direct‑download `.dmg`.** A Developer‑ID direct‑download build can't carry
  `aps-environment` / iCloud, so for that channel you'd ship the local‑only
  variant (sync simply stays off). See `FEATURE_UPGRADE_PLAN.md` §0.

---

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Toggle on, but Settings still says local | Relaunch needed; or no iCloud identity (`ubiquityIdentityToken == nil`); or container not owned by the signing team |
| Records never appear in the Dashboard | Schema not deployed, or running against the wrong environment, or sync silently fell back to local |
| Build fails to sign | `DEVELOPMENT_TEAM` has no cert/profile, or the container isn't enabled for that team |
| New field doesn't sync | Re‑deploy the CloudKit schema to Production after the model change |

## What stays serverless / open‑source

There is **no backend**. Sync is the user's own iCloud; OCR/scanner/AI are
on‑device. A fork builds by setting its own `DEVELOPMENT_TEAM` (one line) and its
own container identifier — nothing points at any Husky‑operated service.
