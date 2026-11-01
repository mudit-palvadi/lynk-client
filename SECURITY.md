# Security Policy

## 📌 Supported Versions

Security updates are provided for the latest released LynkShare Android client
and the current `main` branch.

| Version | Supported |
| --- | --- |
| Latest released Android client | ✅ |
| Current `main` branch | ✅ |
| Older releases | ❌ |

Older releases may need to be updated before a fix can be supported. A fix in
source does not mean a store release or Shorebird patch containing it has been
published.

This policy covers this client repository. Reports involving the companion
website or API can describe that interaction, but must not include another
person's files or credentials.

---

## 🔒 Reporting a Vulnerability

If you discover a security vulnerability in LynkShare:

1. **Do not open a public issue.**
2. Use [GitHub's private vulnerability reporting form](https://github.com/mudit-palvadi/lynkshare-mobile/security/advisories/new),
   or go to the repository's **Security** tab and choose **Report a vulnerability**.
3. Include enough detail for a safe reproduction:
   - App version/build, and the Shorebird patch number if known
   - Device and operating system
   - Steps to reproduce
   - Potential impact
   - Any suggested fix, if known

Please use test files and redact sensitive values, including access tokens,
storage keys, signing keys, service credentials, file-decryption keys, complete
QR payloads, full capability links, signed URLs and private file contents. If a
credential was exposed, revoke or rotate it through its provider rather than
sending the live value.

> **If the Report a vulnerability button is unavailable**, the repository
> administrator must enable **Settings → Code security → Private vulnerability
> reporting**. Do not publish exploit details in a public issue while the private
> channel is unavailable.

No response or resolution deadline is guaranteed.

---

## 🤝 Disclosure Policy

- We will confirm the issue, develop a fix, and coordinate disclosure after a
  fix is available.
- Please keep the report private while it is assessed and a disclosure plan is
  agreed.
- Credit will be given to researchers who responsibly report issues, unless
  anonymity is requested.
- Testing must use a local or explicitly authorized environment. Do not run
  denial-of-service tests, automated Share Code guessing, bulk transfers,
  destructive requests or attempts to access another user's transfer.
- This policy does not promise a bounty, payment or remediation date.

---

## 🙏 Thanks

We appreciate the work of the security community in helping keep LynkShare safe
for everyone.
