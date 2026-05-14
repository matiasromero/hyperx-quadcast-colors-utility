# HyperX Quadcast 2 S — RGB control for macOS

Small, native, local app to control the RGB LEDs of the HyperX Quadcast 2 S
on macOS. HyperX NGENUITY (the official software) is Windows-only.

**Current scope:** solid color per zone (upper / lower), brightness 0–100%.
Animated modes (blink, cycle, wave, pulse) are not supported — the protocol
for those modes on the 2S has not been decoded yet.

## Download

Grab the latest signed and notarized `.dmg` from the
[Releases page](https://github.com/matiasromero/hyperx-quadcast-colors-utility/releases/latest),
open it and drag **HyperX RGB** into Applications. macOS 14+ required.

## Structure

| Target              | Location              | What it does                                              |
|---------------------|-----------------------|-----------------------------------------------------------|
| `HyperXProtocol`    | `Sources/` (library)  | Pure USB-packet builder. No macOS dependencies.           |
| `HyperXCore`        | `Sources/` (library)  | IOKit HID wrapper + refresh loop. macOS-only.             |
| `ValidateProtocol`  | `Sources/` (CLI)      | Offline smoke tests for the builder. No hardware needed.  |
| `HIDProbe`          | `Sources/` (CLI)      | Test CLI: sets a color for a few seconds.                 |
| `HyperXRGB`         | `App/` (Xcode app)    | SwiftUI menu bar app (the final .app bundle).             |

## Requirements

- macOS 14+ and Xcode 15+
- [xcodegen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Generate the Xcode project and build the .app

```bash
xcodegen generate
xcodebuild -project HyperXRGB.xcodeproj -scheme HyperXRGB -configuration Release \
           -derivedDataPath build clean build
open build/Build/Products/Release/HyperXRGB.app
```

The `.app` lands in `build/Build/Products/Release/HyperXRGB.app`. To install
it permanently: `cp -R build/Build/Products/Release/HyperXRGB.app /Applications/`.

The `.xcodeproj` is in `.gitignore` — it's regenerated from `project.yml`.

## Protocol verification (no hardware)

```bash
swift run ValidateProtocol     # 40 checks
swift test                      # 13 unit tests with Swift Testing
```

## Test against the real mic

With the mic plugged in:

```bash
swift run HIDProbe ff0000   # red, ~5s
swift run HIDProbe 00ff00   # green
swift run HIDProbe 0080ff   # cyan
```

The LED falls back to its default animation when the command ends (the
firmware retakes control as soon as packets stop arriving).

## Protocol details

Reverse-engineered from [Ors1mer/QuadcastRGB](https://github.com/Ors1mer/QuadcastRGB).

- **HID device**: VID `0x03f0` / PID `0x02b5` (USB product name: "HyperX QuadCast 2 S Controller")
- **Audio**: VID `0x03f0` / PID `0x0d84` — separate USB device, does not interfere
- **Solid color** is sent as 7 packets of 64 bytes:
  - 1 header: `[0x44, 0x01, 0x06, 0, …]` → ACK `rsp[0]=0xff rsp[14]=0x44`
  - 6 data packets `[0x44, 0x02, packet_index, …]` + RGB bytes → ACK `rsp[0]=0x45`
- **Upper zone** starts at `packet[0][4]`, **lower zone** at `packet[2][46]`
- Packets must be **resent continuously** (~every 150ms) or the firmware
  reverts to the default color
- Under IOKit, packets are sent via `IOHIDDeviceSetReport` with
  `kIOHIDReportTypeOutput`

### Non-obvious gotchas (vs. the reference C lib)

1. **Filter by report size**: the "Controller" exposes multiple HID
   collections with the same VID/PID. You must only open the one with
   `MaxOutputReportSize >= 64` AND `MaxInputReportSize >= 64`. The others
   (output size 1) won't accept 64-byte packets.
2. **Drain input responses between each SetReport**: the firmware accumulates
   responses and stops accepting OUTs if they aren't read. Without
   `drainPendingResponses()` before each send, the second cycle already
   returns `kIOReturnTimeout`.
3. **Open with `kIOHIDOptionsTypeSeizeDevice`** to avoid access conflicts.

## Releasing

Releases are built, signed (Developer ID), notarized and published by the
GitHub Actions workflow at [.github/workflows/release.yml](.github/workflows/release.yml)
when a `vX.Y.Z` tag is pushed. The workflow delegates the build to
[Scripts/build-release.sh](Scripts/build-release.sh), which can also be run
locally.

### One-time setup

Required only once per maintainer machine + GitHub repo. Skip if the secrets
listed at the end are already present in the repo.

**1. Developer ID Application certificate.** In
[developer.apple.com → Certificates](https://developer.apple.com/account/resources/certificates/list),
create a new certificate of type **Developer ID Application** and download it.
Double-click the `.cer` to install it into Keychain Access. Then in Keychain
Access, right-click the certificate (with its private key under it) →
**Export 2 items…** → save as `DeveloperID.p12` and set a password — this is
`P12_PASSWORD` below.

**2. App Store Connect API key for notarization.** In
[App Store Connect → Users and Access → Integrations → Team Keys](https://appstoreconnect.apple.com/access/integrations/api),
create a new key with role **Developer**. Download the `.p8` (only available
once) and note the **Key ID** and **Issuer ID**.

**3. Load the secrets into GitHub.** In the repo,
**Settings → Secrets and variables → Actions → New repository secret**, add:

| Secret | Value |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | `base64 -i DeveloperID.p12 \| pbcopy` then paste |
| `P12_PASSWORD` | the password chosen in step 1 |
| `KEYCHAIN_PASSWORD` | any random string (used for a throwaway CI keychain) |
| `SIGNING_IDENTITY` | exact name of the cert, e.g. `Developer ID Application: Matias Romero (ABCDE12345)` — copy from `security find-identity -v -p codesigning` |
| `APPLE_TEAM_ID` | 10-char Team ID, visible in the cert name and in the developer portal |
| `APP_STORE_CONNECT_KEY_ID` | Key ID from step 2 |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID from step 2 |
| `APP_STORE_CONNECT_KEY_P8` | full text contents of the `.p8` file (multiline) |

### Cutting a release

```bash
git tag v0.1.0
git push origin v0.1.0
```

The workflow archives, signs, builds the DMG, notarizes via `notarytool` and
staples the ticket, then publishes a GitHub Release with the `.dmg` attached.
Auto-generated release notes are based on commits since the previous tag.

To sanity-check a release was correctly notarized:

```bash
spctl -a -vv /Applications/HyperXRGB.app          # → "source=Notarized Developer ID"
xcrun stapler validate /Applications/HyperXRGB.app # → "The validate action worked!"
```

### Local dry-run (no Developer ID needed)

The same script can produce an unsigned DMG locally for testing the packaging
end-to-end before tagging:

```bash
brew install create-dmg
SIGNING_IDENTITY="-" Scripts/build-release.sh 0.1.0-dev
# → dist/HyperXRGB-0.1.0-dev.dmg
```

Unsigned DMGs trigger a Gatekeeper warning when opened on another Mac — that's
expected; only use them for local testing.

## Out of scope

- Animated modes (require USB capture of NGENUITY on a Windows VM).
- Other HyperX mics (original Quadcast S, Duocast).
- Auto-update, telemetry.
