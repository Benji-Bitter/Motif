# Compatibility

This document is the single source of truth for what Motif can and cannot do
on a given device. Every claim here maps to a `Capability` value returned by
`CapabilityRegistry` — the app UI is driven by the same table, so the docs and
the app cannot drift apart.

## Legend

| Registry value | Meaning |
|---|---|
| `.supported` | Verified to work automatically |
| `.notTested` | Plausible but unverified — disabled until tested |
| `.manualOnly` | No automated path exists; export + instructions only |
| `.unsupported` | Confirmed impossible without jailbreak |

## Feature × mechanism matrix

| Feature | Mechanism | Status on all current iOS | Notes |
|---|---|---|---|
| Detect iPhone over USB | libimobiledevice (`idevice_id`, `ideviceinfo`, `idevicepair`) | `.supported` | Requires libimobiledevice installed on the Mac and the iPhone unlocked + trusted |
| Card artwork design & export | Local render | `.supported` | Fully local — no device needed |
| Card artwork → Apple Wallet | — | `.unsupported` | No public or verified private mechanism exists. Historical exploits (e.g. the AirCard-era Passbook bug) were patched years ago and are marked `.notTested`/blocked, never used |
| Live Photo pair generation | Local AVFoundation pipeline | `.supported` | Produces structurally valid JPEG+MOV with matching content identifiers |
| Live Photo → Photos library | AirDrop / Finder sync (manual) | `.manualOnly` | iOS does not expose a desktop-driven import |
| Live Photo → animated lock screen | iOS Settings → Wallpaper (manual) | `.manualOnly` | Playback support depends on iOS version — see below |
| Set lock-screen wallpaper directly | — | `.unsupported` | No API exists; Motif will never claim otherwise |

## Live Photo lock-screen playback, by iOS

Animated Live Photo lock screens have come and gone across iOS versions:

| iOS | Animated lock screen via Live Photo |
|---|---|
| iOS 9–15 | Supported (press/hold; later tap-and-hold on newer devices) |
| iOS 16 | Removed — Live Photos could not be used as animated lock screens |
| iOS 17+ | Restored (tap the photo icon / plays on wake) |

`CapabilityRegistry.livePhotoLockScreenPlayback` encodes this:

- `major < 16` → `.supported`
- `major == 16` → `.unsupported`
- `major ≥ 17` → `.supported` (structurally valid pair required; subject to
  hardware restrictions on very old devices)

Even on iOS 17+, **Motif only prepares the assets**. Enabling animation is a
manual step on the phone (choose the wallpaper, tap the Live Photo icon).

## Card artwork history (why `.unsupported`)

The only known jailbreak-free Wallet-card artwork changes relied on
short-lived private bugs in `nanopassbookd`/Passes that Apple patched:

- original Passbook artwork bug — iOS 8.x era, patched
- later revival — narrow iOS 9.x window, patched

Shipping code that pokes undocumented daemons hoping for a bug is exactly the
fake-functionality Motif exists to avoid. `WalletSkinProvider.isSupported`
returns `.unsupported` unconditionally; if a *verified* method ever exists it
slots in behind that protocol without touching the UI.

## Device detection requirements

| Requirement | Why |
|---|---|
| `libimobiledevice` installed | Motif shells out to it; not bundled to keep the app dependency-free |
| iPhone unlocked | `lockdownd` refuses most queries while locked |
| Computer trusted | Pairing record required before `ideviceinfo` returns data |
| USB (or paired Wi-Fi) | libimobiledevice supports both; Motif does not distinguish |

Motif reports `needsUnlock` / `needsTrust` / `failed` explicitly rather than
pretending the device is usable.
