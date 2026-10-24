# Changelog

All notable changes to Motif are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com); this project adheres to
[Semantic Versioning](https://semver.org).

## [0.1.0] — Unreleased

First functional release.

### Added

- **Wallet Studio** — import PNG/JPEG/HEIC artwork; crop, pan, zoom, rotate;
  brightness/contrast/saturation/sharpness adjustments; undo/redo; live card
  preview with realistic corner geometry; PNG export including the 1536×969
  preset.
- **Wallpaper Studio** — import MP4/MOV video; inspect duration/dimensions;
  trim with a scrubbable timeline; crop/reframe to device presets (iPhone 14
  Plus included); playback-speed and audio-removal controls; still-frame
  picker; lock-screen preview with clock, date, and safe areas.
- **Live Photo export** — real JPEG+MOV pair with matching MakerApple content
  identifier and QuickTime still-image-time metadata; structural validation
  before success is reported; mismatched pairs are rejected.
- **Library** — SQLite-persisted designs; rename, duplicate, delete, search,
  tags, favourites, collections, recent imports, bundle import/export,
  lazy thumbnails for images and video posters.
- **Devices** — USB discovery via libimobiledevice when installed; explicit
  locked/untrusted/failed states; reconnect; diagnostics; simulated service
  for development, clearly labelled.
- **Apply workflow** — per-operation planning with honest states
  (supported/unsupported/not-tested/manual); confirmation before any device
  action; Wallet card installation is always reported unsupported.
- **Docs & infra** — architecture, compatibility, hardware-testing checklist,
  catalogue spec, releasing guide; CI (build+test+app artifact) and release
  (universal .app → .dmg → GitHub Release) workflows.

### Known limitations

- No verified mechanism exists to install card artwork into Wallet — Motif
  exports artwork and says so.
- Wallpaper application is export + manual transfer only.
- Live Photo lock-screen playback eligibility depends on iOS version
  (works ≤ iOS 15, absent on 16, restored on 17+) — see COMPATIBILITY.
- No physical-device validation performed yet — see HARDWARE_TESTING.

[0.1.0]: https://github.com/Benji-Bitter/Motif/releases/tag/v0.1.0
