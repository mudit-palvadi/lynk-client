# Potential Issues & Mitigations — Lynx P2P Implementation

*This document catalogs the potential risk areas identified during the Phase 3 P2P design review, along with recommended mitigations. It is intended for the lead dev/tech‑lead team and will be referenced during sprint planning and alpha testing.*

---

## 1. Signaling & Session Management

| # | Issue | Why It Matters | Mitigation |
|---|-------|----------------|------------|
| 1 | **WebSocket message format drift** between Dart `jsonEncode` and browser `JSON.parse` | Inconsistent key names or types → receiver cannot parse SDP/candidates → connection failure. | Define a **strict contract** (TypeScript interface or Dart `freezed` class). Write **cross‑language unit tests** that encode/decode both sides and assert equality. |
| 2 | **Room / session cleanup / idle timeout** (Phases.md: 60‑second idle timeout) | Stale rooms leak server resources; if user re‑opens same link, may get confusing “already connected” behavior. | Implement **server‑side TTL** on room creation (`setTimeout` + `room.delete()`). On disconnect, automatically clean up after the timeout. Expose a health endpoint for ops. |
| 3 | **Concurrent transfers per user** | User may initiate multiple sends; without locking, ICE candidates/SDP could mix between transfers, causing corrupted streams. | Enforce `maxConcurrentTransfers = 1` in UI; queue subsequent transfers; persist `inFlightTransferId` in shared prefs for quick resume. |

---

## 2. Flutter WebRTC Service

| # | Issue | Why It Matters | Mitigation |
|---|-------|----------------|------------|
| 4 | **ICE candidate gathering failure** (cellular/CG‑NAT) | No working ICE pair → DataChannel never opens → user sees “connecting…” indefinitely. | **STUN + TURN fallback**: configure Google STUN (`stun:stun.l.google.com:19302`) + optional TURN (OCI Always‑Free Coturn). After 6 s of no connectivity, auto‑add TURN candidate and retry. |
| 5 | **`bufferedAmount` backpressure edge cases** (Phases.md: pause when buffer > 1 MB) | Too aggressive → transfer stalls; too lenient → receiver buffer overflows and drops chunks. | Test three thresholds (0.5 MB, 1 MB, 2 MB) on real devices/browsers; choose the highest that never causes drops in worst‑case (3G, congested Wi‑Fi). |
| 6 | **8‑second P2P timeout → R2 fallback** | If too short, legitimate P2P (high‑latency Wi‑Fi) incorrectly falls back, increasing cost/latency. | Make timeout **configurable** via env var; collect alpha metrics; adjust based on observed P2P success rate. |
| 7 | **Memory pressure on low‑end devices** (1 GB RAM phones) | `RTCDataChannel` buffers all in‑flight chunks; large files (up to 200 MB) could OOM if not released. | Dispose of `RTCDataChannel` and `RTCPeerConnection` immediately after transfer completion; use `Isolate` for encryption/decryption (already done for file‑encrypt/decrypt). |
| 8 | **Codec/encryption mismatch** between Flutter and browser | Flutter uses background isolate AES‑256‑CBC with 16‑byte IV prepended; browser must use `crypto.subtle.decrypt` with **identical** IV extraction. | Document exact format: `iv = first 16 bytes of ciphertext`. Both sides must read it the same way. Add **integration test** that sends a known test file from Flutter → receives in browser and verifies hash. |

---

## 3. Web Receiver Page (vanilla JS)

| # | Issue | Why It Matters | Mitigation |
|---|-------|----------------|------------|
| 9 | **Safari/iOS WebRTC limitations** (no `RTCDataChannel` on older iOS, limited codec support) | Significant iOS user base may be unable to receive P2P transfers. | **Feature detect** `RTCDataChannel`; if unavailable, **gracefully downgrade** to R2 cloud download (already the fallback path). |
| 10 | **File API differences** (Chrome vs Firefox vs Safari) for `<a download>` | Some browsers may block automatic download or save to a different location. | Use `URL.createObjectURL(blob)` + `navigator.msSaveOrOpenBlob` for IE/Edge fallback; test on latest Chrome, Firefox, Safari. |
| 11 | **Concurrent P2P sessions** (two tabs with same `lynkshare.app/send/{id}#{key}`) | Both tabs attempt to connect to same signaling room → conflicts, broken transfers. | Disallow multiple tabs: store `transferId` in `localStorage`; if already opened, show “Transfer already in progress” message. |

---

## 4. Infrastructure & Deployment

| # | Issue | Why It Matters | Mitigation |
|---|---|---|---|
| 13 | **Cloudflare DNS proxy + Origin Rule (port 80 → 8000)** | Misconfigured Origin Rule breaks WebSocket `wss://` connectivity for browsers behind restrictive proxies. | Test full path: `lynkshare.app` → Cloudflare → OCI EC2:8000 → FastAPI Uvicorn; verify `wss://` works in Chrome DevTools Network ws tab. |
| 14 | **Android App Links / iOS Universal Links** (Phases.md: `assetlinks.json` + `apple-app-site-association`) | If missing/mis‑served, deep‑link `https://lynkshare.app/send/{id}#{key}` falls back to browser instead of opening the app. | Serve both files with `Content-Type: application/json`; host at exact paths; validate via `adb shell intent -W -a android.intent.action.VIEW -d https://lynkshare.app/send/...` on Android. |
| 15 | **Domain not yet purchased** (Phases.md: “TBD”) | Without a real domain, all `https://`/`wss://` links are placeholders; users cannot test deep linking. | Use existing `lynkshare.app` placeholder for now; document that **purchase + DNS setup** is a prerequisite before alpha release. |

---

## 5. Security & Privacy

| # | Issue | Why It Matters | Mitigation |
|---|---|---|---|
| 16 | **AES key leakage via URL fragment** (`#key`) | If fragment is logged (server access logs, browser history), encryption is compromised. | Ensure **backend FastAPI never logs the request URI**; configure Nginx/Cloudflare to **omit the fragment** from access logs; educate users not to share the QR code. |
| 17 | **ICE candidate exposure** (contains internal IP) | Could reveal LAN topology; contrary to “privacy‑first” stance. | Do **not** send ICE candidates to any external service beyond the signaling WS; keep them client‑only. |
| 18 | **TURN relay usage** (if STUN fails) | Relay sees raw SRTP packets; if relay is compromised, file content could be exposed. | Use **short‑lived TURN credentials**; wipe credential from memory immediately after session ends; prefer direct P2P over relay whenever possible. |

---

## 6. Testing & QA

| # | Issue | Why It Matters | Mitigation |
|---|---|---|---|
| 19 | **Lack of cross‑platform automated tests** | WebRTC behavior varies wildly across device/OS/browser combos; manual testing alone is insufficient. | Write **TDD‑style unit tests**: `webrtc_service_test.dart` – signaling message parsing, 8‑second timeout, bufferedAmount logic. `app_router_test.dart` – deep link route matching, fragment extraction. Add **browser integration** via Playwright/Selenium for the web receiver page. |
| 20 | **No “smoke test” CI pipeline** | Merges could break P2P for certain device configs without detection. | Add **GitHub Actions** workflow that builds release APK and runs the 71‑test suite; optionally run the web receiver headless via `playwright --headless`. |

---

## 7. Risk Summary (High‑Level)

| Risk Category | Likelihood | Impact | Owner |
|--------------|------------|--------|-------|
| ICE/STUN failure on cellular/CG‑NAT | High | Users cannot connect → fallback to R2 (costs) | Backend/Flutter lead |
| Browser‑to‑Flutter encryption mismatch | Medium | Decryption fails; user thinks file is corrupted | Crypto/Flutter lead |
| Safari iOS DataChannel unsupported | Medium | iOS users forced to R2 download only | Web lead |
| Signaling message drift (Flutter vs browser) | Medium | Connection never establishes | Lead tester |
| TURN relay cost under alpha load | Low‑Medium | Unexpected egress if many users fall back | Ops |
| Deep‑link/app‑association not working | Low | Users can’t open app from browser link | DevOps |

---

*Document version: 1.0 — created during Phase 3 design review. Review and update after each alpha sprint.*