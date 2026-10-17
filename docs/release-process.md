# Release process

Releases are built and uploaded by Codemagic — no more manual Play Console uploads.

## One-time setup (already done)

- Codemagic app connected to this repo
- Upload keystore stored in Codemagic → Code signing identities → Android keystores,
  reference name `lynk_upload_keystore`
- Env group `lynk_config` — the `.env` values (API_BASE_URL, DEV_CONFIG_KEY, PRIVACY_POLICY_URL, DEEP_LINK_BASE_URL)
- Env group `google_play` — `GOOGLE_PLAY_SERVICE_ACCOUNT_CREDENTIALS` (service account JSON key)
- Google Play service account invited in Play Console with "Releases to testing tracks" for Lynk

## Cut a release

1. (Optional) Bump `version:` in `pubspec.yaml` if you want a new versionName (e.g. `0.1.1+4`).
   The build number after `+` is irrelevant for CI releases — Codemagic sets it automatically.
2. Push your changes to `main`.
3. Codemagic → `lynk-client` → **Start new build** → workflow `lynk-android-release` → branch `main`.
4. Watch the build. On success the AAB is uploaded to Google Play closed testing
   automatically; testers receive the update once Google processes the release.

## How versioning works

- versionCode = `100 + Codemagic PROJECT_BUILD_NUMBER` (first CI build → 101, then 102, 103 …).
  This is always higher than the manual `+N` uploads, so Play never rejects a reused code.
- versionName still comes from `pubspec.yaml` (the part before `+`).

## Notes

- The workflow runs `flutter analyze` and `flutter test` first — a failing test blocks the release.
- `android/app/upload-keystore.jks` locally is the backup copy of the keystore.
  Codemagic cannot return an uploaded keystore, so back this file up somewhere safe too.
- To publish to a different track: edit `track:` in `codemagic.yaml`, or start a build with
  the `GOOGLE_PLAY_TRACK` environment variable set (e.g. `internal`, `beta`, `production`).
- CI runs on the free plan's Mac mini M2 machine (`instance_type: mac_mini_m2`, `java: 21`
  pinned). Linux machines (`linux_x2`) are not available on the free plan — the build is
  rejected with "selected instance type is not available with the current billing plan".
  Leave the machine type as is unless the Codemagic billing plan changes.
