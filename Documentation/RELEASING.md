# Releasing Motif

## Local build

```bash
Scripts/build_app.sh release   # universal build/Motif.app (arm64 + x86_64)
Scripts/make_dmg.sh            # build/Motif.dmg
```

`generate_icon.swift` regenerates `Resources/AppIcon.icns` if the mark changes;
the CI release workflow runs it automatically.

## What the scripts produce

- A standard `.app` bundle — executable in `Contents/MacOS`, `Info.plist`,
  SPM resource bundle, `AppIcon.icns`.
- **Ad-hoc signed** (`codesign --sign -`) so it runs locally on Apple Silicon.
  Gatekeeper will still warn on other Macs.

## CI

- `ci.yml` — on push/PR to `main`: `swift build`, `swift test`, assemble the
  `.app`, upload it as an artifact.
- `release.yml` — on `v*` tag (or manual dispatch): icon → universal `.app` →
  `.dmg` → attaches the dmg to a GitHub Release.

## Signing & notarisation (not yet configured)

Current builds are **unsigned** — the README and release notes must say so.

To ship a properly signed release:

1. Enrol in the Apple Developer Program.
2. Add secrets to the repo: `CERTIFICATES_P12`, `CERTIFICATES_PASSWORD`,
   `KEYCHAIN_PASSWORD`, `NOTARIZE_APPLE_ID`, `NOTARIZE_PASSWORD` (app-specific
   password), `TEAM_ID`.
3. In `release.yml`, import the certificate into a temp keychain, then:

   ```bash
   codesign --deep --force --options runtime \
       --sign "Developer ID Application: <Name> (<TEAM_ID>)" build/Motif.app
   ```

4. Notarise:

   ```bash
   xcrun notarytool submit build/Motif.dmg \
       --apple-id "$NOTARIZE_APPLE_ID" --password "$NOTARIZE_PASSWORD" \
       --team-id "$TEAM_ID" --wait
   xcrun stapler staple build/Motif.dmg
   ```

Until that is done, do not label any release "signed" or "notarised".

## Release checklist

- [ ] `swift test` green on CI
- [ ] CHANGELOG updated
- [ ] `CFBundleShortVersionString` bumped in `Resources/Info.plist`
- [ ] Tag `vX.Y.Z`, push tag
- [ ] Verify the dmg on a clean Mac (Gatekeeper wording is honest in notes)
- [ ] Note hardware-verification status from HARDWARE_TESTING.md in the release
