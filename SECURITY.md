# Security policy

## Supported versions

| Version | Status |
|---|---|
| 0.1.x | current — fixes on `main` |

## Reporting a vulnerability

Please report security issues privately:

- Email: **benmilespersonal@gmail.com**
- GitHub: open a private security advisory on this repository

Do not open a public issue for exploitable problems. Expect a response within
a few days; if it takes longer, send a follow-up.

## Scope notes

Motif's threat model is intentionally small:

- **Local-first** — no network code, no telemetry, no accounts.
- **Device access** happens through libimobiledevice CLI tools only; Motif
  never touches the iPhone filesystem directly.
- **Import parsing** is the main attack surface: image decode (ImageIO),
  video decode (AVFoundation), and bundle manifests (JSON). Malformed media is
  rejected before processing.
- **Imported bundles are data, never code** — nothing inside a
  `.motifdesign`/`.motifwallpaper` is executed.
- Device identifiers are session-scoped and never persisted.

If you find a path where imported content could escape the local sandbox,
corrupt the library store, or misrepresent a device operation, that is in
scope and worth reporting.
