# HyperX Quadcast 2 S — RGB control for macOS

Small, native, local app to control the RGB LEDs of the HyperX Quadcast 2 S
on macOS. HyperX NGENUITY (the official software) is Windows-only.

**Current scope:** solid color per zone (upper / lower), brightness 0–100%.
Animated modes (blink, cycle, wave, pulse) are not supported — the protocol
for those modes on the 2S has not been decoded yet.

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

## Out of scope

- Animated modes (require USB capture of NGENUITY on a Windows VM).
- Other HyperX mics (original Quadcast S, Duocast).
- Signed/notarized distribution.
- Auto-update, telemetry.
