# Catalogue format (future, v0.2+)

Motif's library is designed so a community catalogue can be added later without
schema changes. This document defines the format so that work can begin in the
open. **The catalogue does not ship in v0.1** — this is a spec only.

A catalogue is a JSON manifest fetched over HTTPS (or shipped with the app).
It lists downloadable asset bundles; each bundle uses the same
`.motifdesign` / `.motifwallpaper` format `LibraryStore` already imports
and exports.

## `catalogue.json`

```json
{
  "formatVersion": 1,
  "generatedAt": "2026-01-01T00:00:00Z",
  "assets": [
    {
      "id": "sunset-dunes",
      "title": "Sunset Dunes",
      "creator": "Motif Examples",
      "category": "wallpaper",
      "tags": ["nature", "warm", "example"],
      "preview": "previews/sunset-dunes.jpg",
      "source": "https://example.org/motif-assets/sunset-dunes.motifwallpaper",
      "license": "CC0-1.0",
      "sha256": "ab12…",
      "compatibleFormats": ["livephoto", "still"],
      "minMotifVersion": "0.1.0"
    }
  ]
}
```

## Asset fields

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Stable unique slug |
| `title` | yes | Display name |
| `creator` | yes | Attribution — required even for CC0 |
| `category` | yes | `card` \| `wallpaper` \| `collection` |
| `tags` | no | Imported into the user's tag set |
| `preview` | yes | Relative JPEG/PNG ≤ 512 px on the long edge |
| `source` | yes | HTTPS URL to a `.motifdesign`/`.motifwallpaper` bundle |
| `license` | yes | SPDX identifier. Only permissive licences allowed (CC0, CC-BY, MIT…) |
| `sha256` | yes | Verified after download; mismatch = reject |
| `compatibleFormats` | yes | e.g. `["livephoto","still"]`, `["card-1536x969"]` |
| `minMotifVersion` | no | Skip assets requiring newer Motif |

## Import rules

- Download to a temp dir, verify `sha256`, then hand to the same
  `importBundle` path used for local files — no second ingestion path.
- Never execute anything inside a bundle; bundles are data only.
- Attribution is stored on the imported entry and shown in the inspector.
- The app must work fully with the catalogue unreachable.

## Content policy

- Original or permissively-licensed work only. **No copyrighted card artwork,
  brand marks, or unlicensed wallpapers.**
- Procedurally generated assets are preferred for built-in examples — see
  `ExampleAssets.swift`, which seeds the library on first launch.
