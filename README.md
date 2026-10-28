# LynkShare

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/Riverpod-4A154B?style=for-the-badge" alt="Riverpod" />
  <img src="https://img.shields.io/badge/License-MIT-green.svg?style=for-the-badge" alt="License" />
</p>

LynkShare sends files straight from one device to another. No account, no
sign-up, no password. Open the app, pick your files, and share a QR code.

The files are encrypted on the device that sends them. The key that unlocks
them travels inside the QR code and never reaches the server, so what is
stored is unreadable without the code.

---

## What it does

* **No account.** Open the app and start sending.
* **Encrypted on the device.** Files are scrambled before they leave the phone,
  and only the person holding the QR code can read them.
* **Send several files at once.** Pick them, review the list, remove anything
  you changed your mind about.
* **Two ways to move the bytes.** Two devices talk directly to each other when
  they can, and fall back to Cloudflare storage when they cannot.
* **QR codes do the pairing.** Either you show a code and the other person
  scans it, or the other person shows one and you scan it.
* **Honest progress.** The progress bar follows the bytes actually sent.
* **Dark interface.** A calm slate-and-indigo theme. A fuller visual pass is
  still planned.

---

## Size limits

| Device | Cloud (Free) | Cloud (Raised) | P2P (Free) | P2P (Raised) |
|---|---|---|---|---|
| App | 15 MB | 30 MB | 20 MB | 50 MB |
| Website | 10 MB | 10 MB | 10 MB | 10 MB |

*Cloud* means the file is stored on the server for a moment and the other
device picks it up. *P2P* means the two devices send it to each other
directly, with no storage in between.

The app can raise a limit for you on request; the website always works at the
free limit. Each number is the sum of the files in one transfer.

---

## Privacy

* Files are encrypted on the device that sends them. The key stays on the
  phone and travels only inside the QR code.
* The server keeps encrypted files, plus the name and size of each file. It
  cannot read the contents.
* The app and the website share the same transfers, so you can send from one
  and receive on the other.

---

## Project layout

```text
lib/
├── core/                     # Shared building blocks
│   ├── theme/                 # Colors, typography, spacing
│   ├── network/               # The HTTP client and its settings
│   ├── errors/                # Failure types and a Result wrapper
│   ├── providers/             # Transfer, download and receive state
│   ├── routing/               # The screens, their URLs and deep links
│   ├── services/              # Upload, download, encryption, peer-to-peer
│   ├── utils/                 # Formatting, file names, links, permissions
│   └── widgets/               # Small shared pieces of UI
└── features/
    ├── home/                  # The home screen
    ├── onboarding/            # The intro screens
    ├── file_transfer/         # Sending: pick, encrypt, upload, show the code
    ├── file_receive/          # Receiving: scan, download, decrypt
    └── recent_transfers/      # The history list
```

Each feature is split into three layers:

* **domain/** — the rules. Plain Dart, no widgets and no network. It defines
  what a transfer is and what may be done with one.
* **data/** — the plumbing. It turns the API's replies into the domain's
  objects and back, and implements the interfaces the domain declares.
* **presentation/** — what the user sees and touches: the screens, the
  widgets, and the providers that hold the state.

A screen never talks to the network itself. It asks a use case, the use case
asks the domain, and the data layer does the talking.

---

## Tech stack

* **State management:** `flutter_riverpod` (the providers hold the state, and
  `riverpod_generator` writes the repetitive parts)
* **Routing:** `go_router` (one URL per screen, so a link can open the right
  one)
* **HTTP client:** `dio` (custom timeouts, and upload and download progress)
* **File picking:** `file_picker` (native file and directory selection)
* **QR generation:** `qr_flutter` (draws the code from the data)
* **QR scanning:** `mobile_scanner` (camera-based scanning)
* **Encryption:** `cryptography` and `encrypt` (file encryption and key
  wrapping)
* **Peer to peer:** `flutter_webrtc` and `web_socket_channel` (the direct
  connection, and the short chat that introduces the two devices)
* **On the device:** `shared_preferences` and `path_provider` (settings,
  history, and where the files live)
* **Opening a file:** `open_filex` (opens a finished download in the system
  viewer)
* **Sharing:** `share_plus` and `url_launcher` (send a link out, open one)
* **Configuration:** `flutter_dotenv` (public settings read from a `.env`
  file)
* **Identifiers:** `uuid`

---

## Getting started

### What you need

* Flutter 3.44.6 or later
* The Android SDK, or Xcode if you are building for a device that is not
  Android

### Configure

Clone the repository and open the `client` folder. Create a `.env` file next
to `pubspec.yaml`:

```env
API_BASE_URL=http://localhost:8000/api/v1
```

On an Android emulator, use `http://10.0.2.2:8000/api/v1` to reach a backend
running on your computer.

### Run it

```bash
flutter pub get
flutter run
```

### Check it

```bash
flutter analyze
flutter test
```

The tests cover routing and deep links, the file-name rules, the release
configuration, and the CI pipeline. To run one part:

```bash
flutter test test/core/routing/    # routing and deep links
flutter test test/platform/        # release and CI configuration
```

### Continuous integration

`.github/workflows/ci.yml` runs on every push to `main`, on every pull
request, and on demand. It checks the code and runs the tests. A newer commit
cancels a run that is still going, and a failing check blocks the merge.

Releases are built separately by Codemagic (`codemagic.yaml`, manual trigger).

### Build a release

```bash
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols
```

The release build shrinks and obfuscates the app, so keep `build/symbols` and
upload it to Play — without it, crash reports cannot be read.

`docs/release-process.md` lists everything the release pipeline needs.

---

## License

MIT
