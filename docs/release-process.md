# Release process

Releases are built and uploaded by Codemagic — no more manual Play Console uploads.

## One-time setup (already done)

- Codemagic app connected to this repo
- Upload keystore stored in Codemagic → Code signing identities → Android keystores,
  reference name `lynk_upload_keystore`
- Env group `lynk_config` — the `.env` values:
  `API_BASE_URL`, `PRIVACY_POLICY_URL`, `DEEP_LINK_BASE_URL`,
  and the five AdMob ids `ADMOB_APP_ID`, `ADMOB_BANNER_ID`,
  `ADMOB_INTERSTITIAL_ID`, `ADMOB_REWARDED_ID`,
  `ADMOB_REWARDED_INTERSTITIAL_ID` (optional — see below)
- Env group `google_play` — `GOOGLE_PLAY_SERVICE_ACCOUNT_CREDENTIALS` (service account JSON key)
- Google Play service account invited in Play Console with "Releases to testing tracks" for Lynk

> **The AdMob ids are optional, but all five or none of them.**
>
> With none of them set, the pipeline falls back to Google's public **test**
> ids: the build succeeds, the app is published, and it serves test ads and
> earns nothing. The pipeline prints a warning on every run, so the state is
> never silent. With a real AdMob account, set all five and they are used
> as-is. Setting only some of them fails the build, because a half-configured
> release would ship with ads silently half-enabled.
>
> The Gradle build enforces the same rule from the other side: a release build
> with **no** app id always fails, and one with Google's public test id fails
> unless it was asked for (`ALLOW_TEST_ADMOB_IDS=true`, which the pipeline sets
> when it falls back). The final step unzips the packaged AAB and checks that
> the manifest carries the configured id.
>
> The four ad unit ids are what the app requests at runtime; when any of them
> is missing the app shows no ads at all rather than test ads.
>
> There is deliberately **no** `DEV_CONFIG_KEY` in the env group any more. The
> ad bypass used to be a value in `.env`, which meant the key shipped inside
> every APK. It is now a compile-time define
> (`--dart-define=LYNK_DEBUG_BYPASS_KEY=…`) that only exists in a local
> debug build.

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
- Failed or cancelled builds still consume a `PROJECT_BUILD_NUMBER`, so shipped versionCodes
  can skip a number — expected, not a problem.
- versionName still comes from `pubspec.yaml` (the part before `+`).

## Notes

- The workflow runs `flutter analyze` and `flutter test` first — a failing test blocks the release.
- The release build is **minified, resource-shrunk and obfuscated**:
  `isMinifyEnabled`, `isShrinkResources` and `--obfuscate` are all on. The Dart
  symbols are written to `build/symbols` and uploaded as a build artifact, so
  a Play crash report can still be symbolised. **Keep that artifact** — without
  it a release stack trace is unreadable.
- Cleartext traffic is off in the release manifest; only the debug variant
  allows it (for a plaintext local backend).
- `android/app/upload-keystore.jks` locally is the backup copy of the keystore.
  Codemagic cannot return an uploaded keystore, so back this file up somewhere safe too.
- To publish to a different track: edit `track:` in `codemagic.yaml`, or start a build with
  the `GOOGLE_PLAY_TRACK` environment variable set (e.g. `internal`, `beta`, `production`).
- CI runs on the free plan's Mac mini M2 machine (`instance_type: mac_mini_m2`, `java: 21`
  pinned). Linux machines (`linux_x2`) are not available on the free plan — the build is
  rejected with "selected instance type is not available with the current billing plan".
  Leave the machine type as is unless the Codemagic billing plan changes.
