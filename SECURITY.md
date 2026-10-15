# Security policy

The latest public release receives security fixes on a best-effort basis.
Older versions do not receive backports. There is one active maintainer and no
response-time SLA.

Report vulnerabilities privately with
[GitHub's private vulnerability reporting](https://github.com/Mr-Neutr0n/iscreenshoter-open/security/advisories/new).
Include the affected version, a minimal reproduction using synthetic data, the
impact, and any proposed fix. Do not attach screenshots, recordings, tokens, or
files that contain other people's private data. If that form is unavailable,
open a public issue asking for a private reporting channel without disclosing
the vulnerability or its reproduction.

Screen capture permission gives this app access to sensitive desktop content.
OCR runs locally. Clipboard contents are available to applications with clipboard
access. Saved exports persist until the user removes them. History retention and
removal are explained in the README.

Release checksums detect download corruption. CI release attestations establish
which workflow produced a ZIP. Neither a checksum nor an attestation is Apple
notarization, a security audit, or a claim that the app is free of defects.
