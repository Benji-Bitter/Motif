# Motif

**Make your iPhone yours.**

Motif is an open-source macOS application for designing iPhone customisations —
custom card artwork and Live Photo wallpapers — without jailbreaking. Everything
is designed, edited, rendered, and exported locally on your Mac.

- **Wallet Studio** — import artwork (PNG / JPEG / HEIC), crop, rotate, zoom,
  adjust brightness/contrast/saturation/sharpness, preview in a card frame, and
  export print-ready PNGs (including the 1536×969 preset).
- **Wallpaper Studio** — import video (MP4 / MOV), trim, crop, adjust speed,
  pick a still frame, preview it on a simulated lock screen, and export a real
  Live Photo pair (still JPEG + paired MOV with matching metadata).
- **Library** — every design is saved locally: rename, duplicate, favourite,
  tag, search, organise into collections, and import/export bundles.
- **Devices** — detects iPhones over USB via [libimobiledevice](https://libimobiledevice.org)
  when it is installed, and reports honest connection state (connected, locked,
  untrusted, failed).
- **Apply** — plans each operation, reports exactly what is supported,
  what needs manual installation, and what is unsupported — and never reports
  an operation as successful unless it actually ran.

## What Motif can do today (v0.1)

| Capability | Status |
|---|---|
| Card artwork import, edit, preview, save, export | ✅ Fully working |
| Video import, trim, crop, speed, still-frame pick | ✅ Fully working |
| Live Photo pair export with correct pairing metadata | ✅ Fully working |
| iPhone device detection via libimobiledevice | ✅ Works when tooling + hardware present (untested on real hardware yet) |
| Transferring a Live Photo to iPhone | 📤 Export + manual import instructions (no verified direct transfer) |
| Animated lock-screen playback eligibility | ⚠️ Depends on iOS version and device — see [COMPATIBILITY](Documentation/COMPATIBILITY.md) |
| Installing card artwork into Wallet | ❌ Unsupported — no verified jailbreak-free method exists |

Motif will never pretend otherwise. Anything it cannot do directly is exported
with clear manual instructions, and the Apply sheet labels every operation with
its true state.

## System requirements

- macOS 14 Sonoma or later
- Apple Silicon or Intel
- Xcode 16+ / Swift 6 toolchain to build from source
- (optional) `libimobiledevice` for iPhone detection:
  `brew install libimobiledevice`

## Install

Download `Motif.dmg` from
[Releases](https://github.com/Benji-Bitter/Motif/releases), open it, and drag
Motif to Applications.

> Release builds are currently **unsigned and unnotarised**. On first launch,
> right-click → Open, or allow it in System Settings → Privacy & Security.
> See [RELEASING](Documentation/RELEASING.md) for the signing plan.

## Build from source

```bash
git clone https://github.com/Benji-Bitter/Motif.git
cd Motif

# Run tests
swift test

# Build a universal .app (arm64 + x86_64) + optional .dmg
Scripts/build_app.sh          # → build/Motif.app
Scripts/make_dmg.sh           # → build/Motif.dmg

# Regenerate the app icon (optional)
swift Scripts/generate_icon.swift
```

## Privacy

Motif is local-first and privacy-first:

- No accounts, no telemetry, no analytics, no ads.
- All image and video processing happens on your Mac.
- Nothing is uploaded anywhere; there is no network code in the app.
- No payment card numbers, bank credentials, or Apple account data is accessed.
- Device identifiers are used for a live session only — never persisted.

## Project layout

```
Sources/
  Motif/            SwiftUI application (features + design system)
  MotifCore/        Models, persistence, media pipelines, device layer, apply engine
Tests/
  MotifCoreTests/   57 XCTest cases covering the core
Resources/          Info.plist, generated AppIcon.icns
Scripts/            build_app.sh, make_dmg.sh, generate_icon.swift
Documentation/      Architecture, compatibility, hardware testing, releasing, catalogue spec
```

## Documentation

- [Architecture](Documentation/ARCHITECTURE.md) — modules, data flow, design decisions
- [Compatibility](Documentation/COMPATIBILITY.md) — what works on which iOS version, and why
- [Hardware testing](Documentation/HARDWARE_TESTING.md) — manual checklist for real-iPhone validation
- [Catalogue format](Documentation/CATALOGUE.md) — spec for a future community asset catalogue
- [Releasing](Documentation/RELEASING.md) — building, signing, notarising, distributing
- [Contributing](CONTRIBUTING.md) · [Security](SECURITY.md) · [Code of Conduct](CODE_OF_CONDUCT.md) · [Changelog](CHANGELOG.md)

## Known limitations

- **Card artwork cannot be installed into Apple Wallet.** There is no verified,
  jailbreak-free mechanism for this on any supported iOS version. Motif exports
  the artwork and tells you the truth instead of faking a write.
- **Direct wallpaper application is not possible.** iOS does not allow a Mac to
  set the lock screen wallpaper. Motif exports the Live Photo pair; you AirDrop
  it to the phone, save it to Photos, then choose it in Settings → Wallpaper.
  Whether it animates on the lock screen depends on the iOS version — see
  COMPATIBILITY.
- **Device detection requires libimobiledevice** (open-source, not bundled) and
  a trusted, unlocked iPhone. Without it, the Devices section shows setup help.
- Real-hardware behaviour (pairing, Live Photo transfer, lock-screen playback)
  is documented in the hardware checklist but marked **unverified** until run
  against a physical device.

## Licence

MIT — see [LICENSE](LICENSE).
