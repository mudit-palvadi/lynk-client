# Shorebird baselines, staging patches and open-testing releases

The manually started `lynk-android-release` Codemagic workflow builds a signed
Shorebird-enabled AAB and uploads to Google Play **open testing (`beta`) only**.
The separate `lynk-android-patch` workflow publishes to **Shorebird staging only**,
without Play publishing. Nothing runs on push. Neither workflow promotes to
production or promotes a patch to stable automatically.

## Shorebird registration and CI access

LynkShare is newly registered in **xynix** (61441), with public app ID
`e0d614ae-2b54-45d5-b7ac-63dd5133f8f0`. Commit `shorebird.yaml` and its pubspec
asset entry; never reinitialize with `--force`, which replaces the app identity.
This is not a transfer of an existing Shorebird app or the Play listing.

Create an organization-owned service-account API key with release/patch access
and store it as secure `SHOREBIRD_TOKEN` in Codemagic's `shorebird` group. Do not
commit or print the key. Obsolete `shorebird login:ci` tokens are not supported.
CI pins CLI **1.6.134** and the existing, verified-available Flutter **3.44.6**.
The existing package, upload keystore and Play listing remain unchanged.

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
  The configured keystore is also verified before Shorebird publication.
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

## Start an open-testing store baseline

1. Optionally change the versionName in `pubspec.yaml`; CI supplies versionCode.
2. Push reviewed changes to `main`, then choose Codemagic → **Start new build** →
   `lynk-android-release` → `main`. Starting this workflow authorizes its automatic
   Shorebird baseline publication and upload to the open track on success; do not
   start it merely to inspect settings.
3. Check analysis, tests, signing and manifest checks. Retain the AAB, Dart symbols
   under `build/symbols` and R8 mapping artifacts for crash symbolication. Retain
   `build/shorebird-baseline.txt`: actual version+build, Flutter version, source
   commit and bundled `.env` SHA-256 (not its contents).
4. Verify processing and availability in Play Console, install the Play build and
   complete the device transfer/ad/update checks before widening availability.

The workflow retains Mac mini M2, Java 21, release minification/resource shrinking,
Dart obfuscation and symbol artifacts. Back up the upload keystore securely;
Codemagic cannot return its uploaded copy. No signing-key rotation is involved.

Ordinary Flutter installations cannot receive Shorebird patches until a new
Shorebird-enabled baseline is installed through Play. Each later store version
needs its own baseline; Shorebird patch numbers are not Play versionCodes.

## Manually publish a staging patch

1. Begin with the intended baseline's source/configuration and a reviewed Dart-only
   fix. Native plugins, Gradle/manifest changes, assets (including `.env` and
   `shorebird.yaml`) and Flutter SDK changes require a new store baseline.
2. Set `SHOREBIRD_RELEASE_VERSION` to the **exact version+build** and
   `SHOREBIRD_ENV_SHA256` to that baseline artifact's value in the manual build's
   environment. Never use `latest`, increment the CI counter, or use an unrelated
   baseline. Missing/malformed targets and changed configuration are rejected.
3. Start `lynk-android-patch` manually from the reviewed source. This authorizes
   staging publication only. Analysis, full tests, signing verification,
   obfuscation and symbol artifacts remain enabled. Never bypass native/asset
   compatibility checks with override flags.
4. Preview the exact release/patch on a test device, using actual version numbers:

   ```sh
   shorebird preview --app-id e0d614ae-2b54-45d5-b7ac-63dd5133f8f0 --release-version 0.1.0+137 --track staging
   ```

   Check cold/warm links, Cloud/Direct transfers, active-transfer continuity,
   consent, themes and the Play update gate. CI mocks do not replace device QA.

## Explicit promotion and rollback

Play `beta` is separate from Shorebird's patch tracks. Normal installations check
Shorebird **stable** by default. After explicit approval, an operator can promote
the tested staging patch or roll back a bad patch; these commands are not run by CI:

```sh
shorebird patches promote --app-id e0d614ae-2b54-45d5-b7ac-63dd5133f8f0 --release-version 0.1.0+137 --patch-number 1
shorebird patches rollback --app-id e0d614ae-2b54-45d5-b7ac-63dd5133f8f0 --release-version 0.1.0+137 --patch-number 1
```

Replace example numbers with the verified baseline and patch. Default background
checks/downloads happen at startup; patches apply on a subsequent process launch,
not live in an active transfer. Rollback also requires a check/restart and is not
instant for offline devices. The mandatory Play gate continues to govern offered
store versions, not patch numbers. No custom updater or forced restart is added.

Before the first baseline, review updater metadata against privacy disclosures
and Play Data safety, verify organization usage/allowance and service-account
access, and test staging delivery, promotion and rollback on real devices.
Registration and mocked CI tests do not establish those operational checks.
