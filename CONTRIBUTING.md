# Contributing to Motif

Thanks for helping build Motif. A few ground rules keep the project honest and
reviewable.

## The one rule that matters most

**Never fake device functionality.** If a feature cannot be verified end to
end, it returns `.unsupported` or `.manualOnly` — it does not pretend. Every
PR is reviewed against this.

## Getting set up

```bash
git clone https://github.com/Benji-Bitter/Motif.git
cd Motif
swift test        # must be green before you start
```

No external dependencies beyond the Swift toolchain and the macOS SDK.

## How to contribute

1. Open an issue first for anything non-trivial.
2. Branch from `main` (`feature/…` or `fix/…`).
3. Keep `MotifCore` free of SwiftUI/AppKit imports; UI code lives in the
   `Motif` target.
4. Match the existing style — small structs, explicit error types,
   actors for shared state, no third-party dependencies unless truly needed.
5. Add tests for every behaviour change. `swift test` must stay green.
6. Update docs (COMPATIBILITY, ARCHITECTURE, README) if behaviour changes.

## Good first contributions

- Hardware verification: run [HARDWARE_TESTING](Documentation/HARDWARE_TESTING.md)
  on a real iPhone and report results.
- New `WallpaperPreset`s for unlisted iPhone models.
- UI polish — spacing, accessibility, keyboard shortcuts.
- More example assets (procedural/original only — see CATALOGUE policy).

## Harder, high-value work

- A **verified** `DeviceModificationProvider` for any operation (the protocol
  exists; only merge with hardware evidence).
- PhotoKit-based Live Photo *import* validation improvements.
- Performance profiling on large video imports.

## Pull requests

- Describe *why*, not just *what*.
- Note which hardware checks you ran (or couldn't run).
- Keep diffs focused; no drive-by reformatting.

By contributing you agree to the MIT licence and the
[Code of Conduct](CODE_OF_CONDUCT.md).
