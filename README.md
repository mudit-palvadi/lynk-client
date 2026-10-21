# Lynk

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/Riverpod-4A154B?style=for-the-badge" alt="Riverpod" />
  <img src="https://img.shields.io/badge/License-MIT-green.svg?style=for-the-badge" alt="License" />
</p>

Lynk sends files straight from one device to another. No account, no sign-up,
no password. Open the app, pick your files, and share a QR code.

The files are encrypted on the device that sends them. The key that unlocks
them travels inside the QR code and never reaches the server, so what is
stored is unreadable without the code.

The Android app lives in this folder. The website that pairs with it lives in
`web/`. There is no iOS app — iOS users use the website.

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

| | Free | Raised limit |
|---|---|---|
| App, cloud storage | 15 MB | 30 MB |
| App, device to device | 20 MB | 50 MB |
| Website | 10 MB | 10 MB |

The app can raise a limit for you on request. The server refuses any single
file over 50 MB, so every size the app offers is one it can really send.

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
├── core/                  # Theme, networking, shared helpers
└── features/
    ├── file_transfer/     # Sending: picking files, uploading, showing the code
    └── file_receive/      # Receiving: scanning the code, downloading
```

Each feature is split into three layers: the rules, the data that comes and
goes, and the screens the user sees.

---

## Tech stack

* Flutter and Dart
* Riverpod, for state
* Dio, for networking
* file_picker, for choosing files
* qr_flutter and mobile_scanner, for the codes
* open_filex, for opening a finished download

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
