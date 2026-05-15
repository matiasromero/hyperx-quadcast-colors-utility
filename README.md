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

Required only once per maintainer machine + GitHub repo. Skip parts that
are already done.

#### A. Create the Developer ID Application certificate

1. **Generate a Certificate Signing Request (CSR) on your Mac.** Open
   **Keychain Access** → menu **Keychain Access → Certificate Assistant →
   Request a Certificate from a Certificate Authority**. Fill in your email
   and name, leave **CA Email Address** empty, select **Saved to disk**, and
   save the `.certSigningRequest` somewhere temporary.
2. **Upload the CSR to Apple.** Go to
   [developer.apple.com/account/resources/certificates/list](https://developer.apple.com/account/resources/certificates/list)
   → click **+** → select **Developer ID Application** → **Continue** →
   upload the `.certSigningRequest` → **Continue** → **Download**. Double-click
   the downloaded `.cer` to install it into the `login` keychain.
3. **Verify the cert is installed and grab its identity string:**

   ```bash
   security find-identity -v -p codesigning
   ```

   You should see a line like:

   ```
   1) ABCDEF1234567890… "Developer ID Application: Matias Romero (ABCDE12345)"
   ```

   - The full quoted string is the value for the `SIGNING_IDENTITY` secret.
   - The 10-character code in parentheses is your `APPLE_TEAM_ID`.

#### B. Export the certificate as `.p12`

1. In **Keychain Access**, select the **login** keychain on the left and the
   **My Certificates** category. Click the disclosure triangle next to
   *Developer ID Application: …* to confirm it has a private key nested
   underneath — if it doesn't, the export won't work and you need to redo
   step A from the same Mac that generated the CSR.
2. Right-click the certificate → **Export "Developer ID Application: …"** →
   **File Format: Personal Information Exchange (.p12)** → save as
   `DeveloperID.p12` and set a strong password (this becomes `P12_PASSWORD`).
3. Encode it for the GitHub secret:

   ```bash
   base64 -i DeveloperID.p12 | pbcopy
   ```

   Your clipboard now holds the value for `BUILD_CERTIFICATE_BASE64`.

#### C. Create the App Store Connect API key (for notarization)

1. Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com) →
   **Users and Access** → tab **Integrations** → sub-tab **Team Keys**
   (not "Individual Keys").
2. Click **+** → name it e.g. `Notarization CI` → Access **Developer** →
   **Generate**.
3. **Download the `.p8` immediately** — Apple only lets you do this once.
   Keep it somewhere safe; you'll paste its contents into a GitHub secret.
4. On the same page, note:
   - **Key ID** — 10-character code in the table row.
   - **Issuer ID** — the UUID-style string at the top of the keys section.

#### D. Load the eight secrets into GitHub

In the repo: **Settings → Secrets and variables → Actions → New repository
secret**. Add each of these:

| Secret | Where it comes from |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | clipboard from step B.3 |
| `P12_PASSWORD` | the password you set in step B.2 |
| `KEYCHAIN_PASSWORD` | any random string — e.g. `openssl rand -base64 24` |
| `SIGNING_IDENTITY` | full quoted string from step A.3, e.g. `Developer ID Application: Matias Romero (ABCDE12345)` |
| `APPLE_TEAM_ID` | the 10-char code in parentheses from step A.3 |
| `APP_STORE_CONNECT_KEY_ID` | Key ID from step C.4 |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID from step C.4 |
| `APP_STORE_CONNECT_KEY_P8` | full text of the `.p8` from step C.3, including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines (multi-line) |

### Testing before the first release

Before tagging `v0.1.0` it pays off to validate locally, then with a throwaway
tag, so CI failures don't end up in your real release history.

**1. Local signed + notarized dry-run.** Run the full pipeline on your own
Mac with the exact same credentials CI will use:

```bash
brew install create-dmg
export SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export APPLE_TEAM_ID="TEAMID"
export APP_STORE_CONNECT_KEY_ID="KEYID"
export APP_STORE_CONNECT_ISSUER_ID="ISSUERID"
export APP_STORE_CONNECT_KEY_P8="$(cat ~/Downloads/AuthKey_KEYID.p8)"
Scripts/build-release.sh 0.1.0-test
```

When it finishes with `Built and notarized: dist/HyperXRGB-0.1.0-test.dmg`,
mount the DMG, drag the app into Applications, and open it. Gatekeeper should
let it through without warnings.

**2. End-to-end test of the GitHub Actions workflow.** Push a throwaway
release-candidate tag:

```bash
git tag v0.1.0-rc1
git push origin v0.1.0-rc1
```

Watch **Actions → Release** in GitHub. If it reaches *Create GitHub Release*,
download the DMG from the published release and install it (ideally on a
different Mac, or after `xattr -d com.apple.quarantine` to strip the
"downloaded from internet" flag locally). If anything goes wrong, clean up:

```bash
gh release delete v0.1.0-rc1 -y
git push --delete origin v0.1.0-rc1
git tag -d v0.1.0-rc1
```

Once the dry-run is green, you're ready to tag the real release.

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
