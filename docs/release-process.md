# Open-testing release process

The manually started `lynk-android-release` Codemagic workflow builds a signed
release AAB and uploads to Google Play **open testing (`beta`) only**. Nothing runs
on push. This workflow does not promote to production.

## Configuration

- Keep the `lynk_upload_keystore` signing identity and the `lynk_config` and
  `google_play` environment groups in Codemagic. The Play service account needs
  permission to release to testing tracks; never commit its JSON credentials.
- `API_BASE_URL`, `PRIVACY_POLICY_URL` and `DEEP_LINK_BASE_URL` come from
  `lynk_config`. Do not put the debug bypass key in release configuration.
- Five public AdMob identifiers are configured in `codemagic.yaml`:
  `ADMOB_APP_ID`, `ADMOB_BANNER_ID`, `ADMOB_INTERSTITIAL_ID`, `ADMOB_REWARDED_ID`
  and `ADMOB_REWARDED_INTERSTITIAL_ID`. Environment overrides must also contain
  all five correctly formatted, non-sample IDs from the same publisher.
- Remove any stale `GOOGLE_PLAY_TRACK` override, or set it to `beta`. Other values
  fail the preflight, including `alpha` and `production`.
- A release cannot fall back to Google sample IDs or debug signing. Gradle
  requires a complete keystore configuration; CI verifies the AAB certificate
  against the registered upload certificate and checks the packaged AdMob app ID.
- Debug and profile variants always use Google's test app/ad-unit IDs, even with
  real IDs in the local ignored `.env`. Do not click live ads during release QA;
  register test devices with the Mobile Ads SDK for any live-ID device testing.

## Console checks before starting a build

1. Confirm the AdMob app is linked to the correct Play listing, its app/ad units
   are ready, and applicable Privacy & messaging consent messages are configured.
   Play production-access approval does not establish AdMob approval/readiness.
2. Check the AdMob console's **app-ads.txt** instructions and publish/verify the
   exact required developer-site record if requested. The site's AdSense
   `ads.txt` is not a substitute. These console/site checks are operator tasks,
   not verified by the build.
3. Confirm Play's contains-ads declaration, Data safety, privacy policy, open-test
   countries and release availability match the app and configured SDKs.
4. Verify the next `100 + PROJECT_BUILD_NUMBER` is greater than every existing
   Play versionCode. The counter alone cannot guarantee this after manual uploads
   or a CI-app migration. Failed builds can consume numbers.
5. Verify Google UMP on a registered test device: consent flow where required,
   no requests before eligibility, **Ad privacy options** in Settings when
   required, and withdrawal removing banners/preloaded ads. Transfers must remain
   usable when consent or ads are unavailable. Do not force consent geography in
   a shipping release.

## Start an open-testing release

1. Optionally change the versionName in `pubspec.yaml`; CI supplies versionCode.
2. Push reviewed changes to `main`, then choose Codemagic → **Start new build** →
   `lynk-android-release` → `main`. Starting this workflow authorizes its automatic
   upload to the open track on success; do not start it merely to inspect settings.
3. Check analysis, tests, signing and manifest checks. Retain the AAB, Dart symbols
   under `build/symbols` and R8 mapping artifacts for crash symbolication.
4. Verify processing and availability in Play Console, install the Play build and
   complete the device transfer/ad/update checks before widening availability.

The workflow retains Mac mini M2, Java 21, release minification/resource shrinking,
Dart obfuscation and symbol artifacts. Back up the upload keystore securely;
Codemagic cannot return its uploaded copy. No signing-key rotation is involved.
