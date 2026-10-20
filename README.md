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
* **Run App (Local Development):**
  ```bash
  flutter run
  ```

---

## Security & Performance Guidelines

* **Zero-Knowledge Encryption:** Cryptographic keys are generated on-device and shared only via the QR code. Files remain fully encrypted in transit and at rest on R2 storage.
* **Secure Keys:** Never store Cloudflare R2 bucket credentials or private secrets on the client. All upload and download URLs are presigned and short-lived.
* **Untrusted File Names:** A file name comes from the sender, so it is never used as a path. `FileNameSanitizer.safeFileName()` (`lib/core/utils/file_name_sanitizer.dart`) takes the last path segment, strips control characters, and trims to 255 UTF-8 bytes at every write site (cloud download, P2P download, P2P temp file, upload). The backend validates the same rules and answers `400` for a bad name.
* **Low Memory Footprint:** Files are streamed during upload (`File.openRead()`) and download instead of being loaded fully into memory.
* **Abuse Controls:** File counts, total sizes, and rates are authoritatively checked on the backend and mapped to friendly, descriptive error widgets on the client.
