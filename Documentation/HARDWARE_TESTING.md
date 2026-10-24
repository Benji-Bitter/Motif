# Hardware testing checklist

Device-dependent behaviour cannot be exercised by the automated suite. Each
item below must be run against real hardware before it may be called verified.
Items not yet performed are marked **UNVERIFIED** — currently **all of them**
(no physical iPhone was available during v0.1 development).

## Setup

- [ ] Install libimobiledevice: `brew install libimobiledevice` — UNVERIFIED
- [ ] Launch Motif, open the Devices section — UNVERIFIED

## Device discovery & pairing

- [ ] Connect iPhone over USB → appears in Devices with name, model, iOS version — UNVERIFIED
- [ ] Locked iPhone → state shows "Unlock iPhone" — UNVERIFIED
- [ ] Untrusted computer → state shows "Needs trust" — UNVERIFIED
- [ ] Tap Trust on device → state resolves to Ready — UNVERIFIED
- [ ] Disconnect USB → device marked Disconnected — UNVERIFIED
- [ ] Reconnect → device re-detected without restarting Motif — UNVERIFIED
- [ ] Two devices connected → both listed independently — UNVERIFIED
- [ ] libimobiledevice absent → Devices section shows install help, no crash — VERIFIED (unit: `testLibimobiledeviceServiceAvailability`)

## Live Photo transfer & playback

- [ ] Export Live Photo pair → AirDrop to iPhone → lands in Photos as one Live Photo — UNVERIFIED
- [ ] On iOS 17+: set as lock-screen wallpaper, tap Live icon → animates on lock screen — UNVERIFIED
- [ ] On iOS 16: same pair → wallpaper sets but does not animate — UNVERIFIED
- [ ] `idevicepair` diagnostics in Devices show meaningful output on failure — UNVERIFIED

## Wallet / card artwork

- [x] Apply sheet always reports card installation as unsupported — VERIFIED (unit: `testCardArtworkIsNeverReportedSupported`, `testPlanMarksCardInstallUnsupported`)
- [ ] Exported 1536×969 PNG visually inspected at 1:1 — UNVERIFIED (pixel-level correctness is covered by `testCardRenderProducesExactPresetSize`)

## Apply workflow

- [ ] Apply with no device → plan refuses with clear message — VERIFIED (unit: `testPlanRequiresDevice`)
- [ ] Apply with device → wallpaper operation plans export/manual transfer — VERIFIED (unit)
- [ ] Manual-transfer instructions render correctly in the sheet — VERIFIED (code review; visual check pending first real run)

## Sign-off

| Build | Tester | Date | Device | iOS | Result |
|---|---|---|---|---|---|
| — | — | — | — | — | pending |
