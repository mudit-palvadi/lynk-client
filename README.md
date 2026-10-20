# Lynk — Cross-Device File Transfer App (Client)

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/Riverpod-4A154B?style=for-the-badge" alt="Riverpod" />
  <img src="https://img.shields.io/badge/License-MIT-green.svg?style=for-the-badge" alt="License" />
</p>

Lynk is a login-free file transfer app. A Flutter client (Android) and the website in `web/` can both send and receive. There is no iOS app distribution — iOS users use the website. Files are encrypted on the device with AES-256-CBC before they leave. The plaintext key stays in the QR link fragment. The server stores ciphertext plus the filename and size.

Files are uploaded directly to **Cloudflare R2** via short-lived presigned URLs, and session/transfer metadata is stored in **Redis** with strict TTL-based expiration.

---

## Features

* **Zero Login/Sign-up:** Open the app, pick your files, and start transferring instantly.
* **Client-side encryption:** AES-256-CBC with a prepended IV. The fragment key is a 32-character string used as raw UTF-8, from `EntropyGenerator.generateKey()` on the app and from 16 CSPRNG bytes on the website. The file ciphertext has no authentication tag.
* **Multi-File Support:** Select, preview, and remove multiple files in a single transfer.
* **Two transports:** WebRTC data channel first (the mobile sender waits up to 60 seconds; the receiver and the website use 8 seconds), then Cloudflare R2 through presigned URLs. File bytes are not proxied through the API. The server rejects a file over 50 MB even when the app UI offers a 200 MB P2P unlock.
* **Secure QR Flows:**
  1. **Sender QR Flow (Primary):** Upload files $\rightarrow$ generate QR code $\rightarrow$ scan to download.
  2. **Receiver QR Flow:** Receiver generates session QR $\rightarrow$ Sender scans $\rightarrow$ Sender uploads $\rightarrow$ Receiver downloads.
* **Byte-Weighted Progress:** Real-time upload and download progress accurately calculated using file size weights.
* **Dark UI:** Slate-indigo dark theme. The fuller visual pass (glass, motion, type) is still Phase 5 and is not shipped.

---

## 🛠️ Architecture & Folder Structure

The client codebase is structured following **Clean Architecture** principles grouped by **Feature** to enforce separation of concerns, testability, and scalability.

```text
lib/
├── core/
│   ├── theme/           # App styles, typography, and premium dark mode theme
│   ├── network/         # ApiClient (Dio client with timeout and log interceptor)
│   ├── errors/          # Custom Failure classes & Result monad wrapper
│   └── utils/           # Shared helpers (e.g., FileSizeFormatter)
│
└── features/
    ├── file_transfer/   # Sender Flow: File selection, uploading, & QR generation
    │   ├── domain/      # Entities and abstract repository contracts
    │   ├── data/        # JSON Models, DataSources, and Repository implementations
    │   └── presentation/# Riverpod controllers, widgets, and screen layouts
    │
    └── file_receive/    # Receiver Flow: QR scanning & file downloading
        ├── domain/      # Entities and abstract repository contracts
        ├── data/        # JSON Models, DataSources, and Repository implementations
        └── presentation/# Riverpod controllers, widgets, and screen layouts
```

### Clean Architecture Rules:
1. **Domain Layer:** Independent of external frameworks, libraries, and the Data layer. It holds the pure business logic (**Entities** and **Repository contracts**).
2. **Data Layer:** Handles data retrieval and serialization. It implements repository contracts, maps raw responses to entities, and connects to remote API sources.
3. **Presentation Layer:** Manages application state via **Riverpod Notifiers** and builds responsive, beautiful user interfaces.

---

## Tech Stack & Dependencies

* **State Management:** `flutter_riverpod` (Simple, reactive state architecture)
* **HTTP Client:** `dio` (With custom timeouts, logs, and upload/download progress streaming)
* **File Picker:** `file_picker` (For multi-file selection)
* **QR Utilities:** `qr_flutter` (QR code generation) & `mobile_scanner` (Fast camera-based QR scanning)
* **File Opener:** `open_filex` (To open downloaded files on device)
* **Equality Helper:** `equatable` (For type-safe equality value checking without boilerplates)

---

## 🏁 Getting Started

### Prerequisites
* Flutter SDK (version `^3.12.2` or later)
* Android SDK or Xcode (for iOS development)

### Local Configuration
1. Clone the repository and navigate to the client folder.
2. Create a `.env` file in the root of the client directory:
   ```env
   API_BASE_URL=http://localhost:8000/api/v1
   ```
   *(Note: For Android Emulators, use `http://10.0.2.2:8000/api/v1` to point to your local machine backend).*

### Commands
* **Fetch Dependencies:**
  ```bash
  flutter pub get
  ```
* **Run Linter:**
  ```bash
  flutter analyze
  ```
* **Run Tests:**
  ```bash
  flutter test
  ```
* **Run the Deep-Link Suites:**

  Three layers: parser units, end-to-end behaviour (cold start, warm start, onboarding gate) and the manifest/assetlinks contract. See `docs/ARCHITECTURE.md` §7.1 in the repo root `docs/` for the full description.
  ```bash
  flutter test test/core/routing/ test/platform/          # both deep-link suites
  flutter test test/core/routing/deep_link_behavior_test.dart
  ```
  The contract suite reads `../web/.well-known/assetlinks.json`; it skips when the sibling `web/` checkout is absent (CI checks out one repo at a time) and fails only when the file is present and the contract is wrong.
* **Run the File-Name Suites:**
  ```bash
  flutter test test/core/utils/file_name_sanitizer_test.dart test/integration/download_flow_test.dart
  ```
* **Run the Release-Hardening Suite:**
  ```bash
  flutter test test/platform/release_hardening_test.dart
  ```
  It asserts the release manifest forbids cleartext, the AdMob app id is a build-time placeholder rather than Google's sample id, the release build type shrinks and obfuscates, and the ad-bypass key is not shipped.
* **Run App (Local Development):**
  ```bash
  flutter run
  ```

### Release Builds

A release build refuses to run without a real AdMob configuration, so a sample
id can never reach Play.

```bash
# the AdMob application id (not the sample one) and the four ad unit ids
export ADMOB_APP_ID=ca-app-pub-xxxxxxxxxxxxxxxx~yyyyyyyyyyyy
export ORG_GRADLE_PROJECT_admobAppId=$ADMOB_APP_ID
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols
```

* `ORG_GRADLE_PROJECT_admobAppId` (or `-PadmobAppId=`, or `ADMOB_APP_ID`)
  fills the `${admobAppId}` placeholder in the manifest. Without it, or with
  Google's sample id, every release Gradle task fails with a `GradleException`.
* The four ad unit ids (`ADMOB_BANNER_ID`, `ADMOB_INTERSTITIAL_ID`,
  `ADMOB_REWARDED_ID`, `ADMOB_REWARDED_INTERSTITIAL_ID`) are read from `.env` at
  runtime. When any of them is missing, `AdService` reports that there are no
  real ad units and no ad is requested, rather than silently showing test ads.
* `--obfuscate` plus `--split-debug-info` keeps the Dart symbols out of the
  bundle. Upload `build/symbols` to Play so crash reports stay readable.
* Cleartext traffic is off in the release manifest. Only the debug variant
  allows it, for a plaintext local backend.
* The ad bypass is a **compile-time define**, not a value in `.env`:
  `flutter run --dart-define=LYNK_DEBUG_BYPASS_KEY=<key>` plus seven taps on
  the version label. It is ignored in a release build, and the key never
  reaches a shipped APK.
* `.env` **is** bundled as an asset, so it ships inside the APK. It holds
  public configuration only (the API base URL, the privacy-policy URL, the
  deep-link base URL, the AdMob ids). Never put a secret in it — that is
  exactly how the old bypass key ended up in every user's hands.

---

## Security & Performance Guidelines

* **Zero-Knowledge Encryption:** Cryptographic keys are generated on-device and shared only via the QR code. Files remain fully encrypted in transit and at rest on R2 storage.
* **Secure Keys:** Never store Cloudflare R2 bucket credentials or private secrets on the client. All upload and download URLs are presigned and short-lived.
* **Untrusted File Names:** A file name comes from the sender, so it is never used as a path. `FileNameSanitizer.safeFileName()` (`lib/core/utils/file_name_sanitizer.dart`) takes the last path segment, strips control characters, and trims to 255 UTF-8 bytes at every write site (cloud download, P2P download, P2P temp file, upload). The backend validates the same rules and answers `400` for a bad name.
* **Hardened release build:** cleartext traffic is off outside the debug variant, the release build type is minified and resource-shrunk, the Dart code is obfuscated with the symbols split out, the AdMob application id is injected at build time and Google's sample id is rejected by a Gradle gate, and no client-side bypass key is compiled into a release APK. See "Release Builds" above and `test/platform/release_hardening_test.dart`.
* **Low Memory Footprint:** Files are streamed during upload (`File.openRead()`) and download instead of being loaded fully into memory.
* **Abuse Controls:** File counts, total sizes, and rates are authoritatively checked on the backend and mapped to friendly, descriptive error widgets on the client.
