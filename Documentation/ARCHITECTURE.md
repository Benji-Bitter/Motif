# Motif architecture

Motif is a single Swift Package with two targets and a clean separation
between *what the app does* (`MotifCore`) and *how it looks* (`Motif`).

```
┌─────────────────────────────────────────────────────────────┐
│  Motif (executable) — SwiftUI + AppKit                       │
│                                                             │
│  MotifApp ── AppEnvironment ── six feature views             │
│  (shell)      (wiring +        Overview · WalletStudio ·     │
│               app state)       WallpaperStudio · Library ·   │
│                                Devices · Settings · Apply    │
└──────────────────────┬──────────────────────────────────────┘
                       │ protocols + models (no UI types below)
┌──────────────────────┴──────────────────────────────────────┐
│  MotifCore (library) — Swift 6, strict concurrency           │
│                                                             │
│  Models        CardDesign · Wallpaper · Library · Device ·   │
│                Apply · EditHistory · SystemVersion           │
│                                                             │
│  Persistence   SQLiteDatabase (raw SQLite3) · LibraryStore   │
│                (actor; media on disk, metadata in DB)        │
│                                                             │
│  Services      ImageProcessor · CardArtworkRenderer ·        │
│                ThumbnailCache · VideoProcessor ·             │
│                LivePhotoGenerator · DeviceService ·          │
│                SimulatedDeviceService · Providers ·          │
│                ApplyEngine · ExampleAssets                   │
│                                                             │
│  Compatibility CapabilityRegistry                          │
└─────────────────────────────────────────────────────────────┘
```

## Design rules

1. **MotifCore never imports SwiftUI.** Everything the UI needs crosses the
   boundary as value types (`struct`s, `enum`s) or `CGImage`. The app could be
   replaced with a CLI and the core would be unchanged.
2. **All device access goes through `DeviceService`.** The real backend
   (`LibimobiledeviceDeviceService`) shells out to `ideviceinfo`,
   `idevice_id`, and `idevicepair` when they exist. `SimulatedDeviceService`
   is explicitly labelled simulated and is used only for development/tests.
   No code path fabricates a device operation.
3. **The apply engine is honest by construction.** `ApplyEngine` asks
   `CapabilityRegistry` + `DeviceModificationProvider`s what is possible,
   returns a plan of `ApplyOperation`s with explicit states
   (`supported / unsupported / notTested / requiresManualInstall …`), and only
   executes verified providers. `WalletSkinProvider` exists as a stub whose
   `isSupported` always returns `.unsupported` — a documented extension point.
4. **Actors own shared mutable state.** `LibraryStore`, `ThumbnailCache`, and
   `DeviceManager` mutations serialise through actors or the main actor.
   `OSAllocatedUnfairLock` guards tiny critical sections (Swift 6 forbids
   `NSLock` in async contexts).
5. **Media is processed off the main thread.** Inspection, rendering, export,
   and Live Photo generation are `async`; heavy loops run detached where the
   API allows.

## Data flow — design lifecycle

```
import ─► validate ─► payload struct ─► LibraryStore.save
                                        ├─ JSON payload + row → SQLite
                                        ├─ media file        → Library/files/
                                        └─ thumbnail         → Library/thumbs/
recall ─► LibraryStore.entries/search ─► ThumbnailView (ThumbnailCache)
edit   ─► payload → view model → EditHistory (undo/redo) → save
export ─► CardArtworkRenderer / LivePhotoGenerator → user-chosen folder
apply  ─► ApplyEngine.plan → ApplySheet → verified providers only
```

## Live Photo pipeline (the hardest piece)

iOS pairs a still JPEG and a QuickTime movie via a shared identifier:

- the JPEG carries `MakerApple` maker-note key `17` = *content identifier*
- the MOV carries a QuickTime metadata item with the same value, plus the
  *still-image-time* flag (`com.apple.quicktime.still-image-time = 0`) in a
  timed metadata track

`LivePhotoGenerator`:
1. re-encodes the edited video through `VideoProcessor` (trim, crop, speed,
   mute) at the chosen `WallpaperPreset` size,
2. writes a metadata track containing the still-image-time item,
3. renders the selected still frame at full preset resolution,
4. writes the still JPEG via ImageIO with the `MakerApple` dictionary
   (the `CGImageMetadata` path silently drops the maker note — the
   properties-dict path persists it; see `writeStillJPEG`),
5. runs `validateLivePhotoPair` — checks the JPEG maker note, MOV metadata
   track, and dimension alignment — before declaring success.

A structurally valid Live Photo pair is **necessary but not sufficient** for
animated lock-screen playback; iOS applies further eligibility rules by
version. Motif reports the distinction.

## Persistence

`LibraryStore` is a SQLite-backed actor at
`~/Library/Application Support/Motif/Library/`:

- `entries` table — id, kind, name, JSON payload, file name, timestamps,
  favourite flag
- `tags`, `collections`, `collection_entries`, `recent_imports` tables
- `files/` — one media file per entry (PNG/MOV/JPEG), never mutated in place
- `thumbs/` — JPEG thumbnails generated lazily by `ThumbnailCache`

Bundles export a zip-compatible folder (`manifest.json` + payload + media) and
import validates manifest version before copying anything.

## Where things live

| Need | File |
|---|---|
| App entry + sidebar shell | `Sources/Motif/MotifApp.swift` |
| Dependency wiring + library location | `Sources/Motif/AppEnvironment.swift` |
| Design tokens (colors, panel, badge) | `Sources/Motif/DesignSystem/MotifDesign.swift` |
| Card editor state + gestures | `…/WalletStudio/CardEditorModel.swift` |
| Video edit state + export | `…/WallpaperStudio/WallpaperModel.swift` |
| Apply sheet + states | `…/Apply/ApplySheet.swift` |
| Live Photo generate + validate | `Sources/MotifCore/Services/LivePhotoGenerator.swift` |
| Video inspect/trim/crop/export | `Sources/MotifCore/Services/VideoProcessor.swift` |
| Capability truth table | `Sources/MotifCore/Compatibility/CapabilityRegistry.swift` |
| Verified-provider boundary | `Sources/MotifCore/Services/Providers.swift` |
| Operation planning | `Sources/MotifCore/Services/ApplyEngine.swift` |
| libimobiledevice CLI bridge | `Sources/MotifCore/Services/DeviceService.swift` |
