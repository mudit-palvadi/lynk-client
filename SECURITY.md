# Security policy

## Supported versions

Security reports are accepted for the latest released LynkShare Android client
and the current `main` branch. Older releases may require an update before a fix
can be supported. A source fix does not establish that a store release or
Shorebird patch containing it has been published.

This policy covers this client repository. Reports involving the companion
website or API can describe that interaction, without disclosing another user's
files or credentials. No response or resolution deadline is guaranteed.

## Reporting a vulnerability

**Do not open a public issue** or pull request containing vulnerability details.
Use [GitHub's private vulnerability reporting form](https://github.com/mudit-palvadi/lynk-client/security/advisories/new)
from the repository's **Security → Report a vulnerability** entry. A GitHub
account is required to submit the report.

**If private reporting is unavailable**, the repository administrator must enable
it under **Settings → Code security → Private vulnerability reporting**. Do not
publish exploit details in an issue while the private channel is unavailable.
This policy does not itself enable that repository setting.

Include enough information for a safe reproduction:

- App version/build, relevant Shorebird patch number if known, device and OS.
- A concise description, affected flow, expected behavior and security impact.
- Minimal reproduction steps using test accounts/devices and non-sensitive files.
- Approximate occurrence time and **redacted** identifiers or screenshots, where
  useful; identify which values were removed.

Do not submit storage keys, service-account credentials, signing keys, file
decryption keys, access tokens, complete QR payloads, full capability links,
presigned/signed URLs or private file contents. Sanitize logs before submission.
If a credential was exposed, revoke or rotate it through its provider rather than
including the live credential in the report.

## Testing boundaries

Use a local or explicitly authorized test environment. Obtain written permission
before production testing that could affect availability, other users, storage
or costs. This policy is not authorization for denial-of-service tests, automated
Code guessing, destructive requests, bulk uploads or access to another transfer.
Stop testing if unexpected access or service impact occurs; report the minimum
evidence instead of continuing exploitation.

## Coordinated disclosure

Keep the report private while it is assessed and a fix and disclosure plan are
discussed. Coordinate publication of technical details with the maintainer,
including the status of any required app, website or backend rollout.

Reporters can request attribution or anonymity. Agree on the wording of any public
credit before disclosure. No bounty, payment, response deadline or remediation
date is promised by this policy.
