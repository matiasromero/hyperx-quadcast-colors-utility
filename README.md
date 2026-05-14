# HyperX Quadcast 2 S — RGB control para macOS

App local pequeña, nativa, para controlar los LEDs RGB del HyperX Quadcast 2 S
en macOS. NGENUITY (el software oficial de HyperX) es solo Windows.

**Alcance actual:** color sólido por zona (upper / lower), brillo 0–100%.
Modos animados (blink, cycle, wave, pulse) no están soportados — el protocolo
para esos modos en el 2S no ha sido decodificado todavía.

## Estructura

| Target              | Ubicación             | Qué hace                                                  |
|---------------------|-----------------------|-----------------------------------------------------------|
| `HyperXProtocol`    | `Sources/` (library)  | Builder puro de los paquetes USB. Sin dependencias macOS. |
| `HyperXCore`        | `Sources/` (library)  | IOKit HID wrapper + refresh loop. macOS-only.             |
| `ValidateProtocol`  | `Sources/` (CLI)      | Smoke tests offline del builder. Sin hardware.            |
| `HIDProbe`          | `Sources/` (CLI)      | CLI de prueba: setea un color durante unos segundos.      |
| `HyperXRGB`         | `App/` (Xcode app)    | App SwiftUI menu bar (la app final, .app bundle).         |

## Requisitos

- macOS 14+ y Xcode 15+
- [xcodegen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Generar el proyecto Xcode y buildear el .app

```bash
xcodegen generate
xcodebuild -project HyperXRGB.xcodeproj -scheme HyperXRGB -configuration Release \
           -derivedDataPath build clean build
open build/Build/Products/Release/HyperXRGB.app
```

El `.app` queda en `build/Build/Products/Release/HyperXRGB.app`. Para instalarlo
permanentemente: `cp -R build/Build/Products/Release/HyperXRGB.app /Applications/`.

El `.xcodeproj` está en `.gitignore` — se regenera desde `project.yml`.

## Verificación del protocolo (sin hardware)

```bash
swift run ValidateProtocol     # 40 checks
swift test                      # 13 unit tests con Swift Testing
```

## Probar contra el mic real

Con el mic conectado:

```bash
swift run HIDProbe ff0000   # rojo por ~5s
swift run HIDProbe 00ff00   # verde
swift run HIDProbe 0080ff   # cyan
```

El LED vuelve a su animación default cuando el comando termina (el firmware
retoma el control si no llegan paquetes).

## Detalles del protocolo

Reverse-engineering del [Ors1mer/QuadcastRGB](https://github.com/Ors1mer/QuadcastRGB).

- **Dispositivo HID**: VID `0x03f0` / PID `0x02b5` (nombre USB: "HyperX QuadCast 2 S Controller")
- **Audio**: VID `0x03f0` / PID `0x0d84` — dispositivo USB separado, no interfiere
- **Para color sólido** se envían 7 paquetes de 64 bytes:
  - 1 header: `[0x44, 0x01, 0x06, 0, …]` → ACK `rsp[0]=0xff rsp[14]=0x44`
  - 6 data packets `[0x44, 0x02, packet_index, …]` + bytes RGB → ACK `rsp[0]=0x45`
- **Zona upper** empieza en `packet[0][4]`, **zona lower** en `packet[2][46]`
- Los paquetes deben **reenviarse continuamente** (~cada 150ms) o el firmware
  vuelve al color default
- En IOKit los paquetes se envían vía `IOHIDDeviceSetReport` con
  `kIOHIDReportTypeOutput`

### Gotchas no obvios (vs. la C lib de referencia)

1. **Filtrar por tamaño de report**: el "Controller" expone múltiples HID
   collections con la misma VID/PID. Hay que abrir solo la que tiene
   `MaxOutputReportSize >= 64` Y `MaxInputReportSize >= 64`. Las otras
   (output size 1) no aceptan paquetes de 64 bytes.
2. **Drenar input responses entre cada SetReport**: el firmware acumula
   respuestas y deja de aceptar OUTs si no se leen. Sin `drainPendingResponses()`
   antes de cada send, el segundo cycle ya da `kIOReturnTimeout`.
3. **Abrir con `kIOHIDOptionsTypeSeizeDevice`** para evitar conflictos.

## Fuera de alcance

- Modos animados (requieren captura USB de NGENUITY en una VM Windows).
- Soporte de otros mics HyperX (Quadcast S original, Duocast).
- Distribución firmada/notarizada.
- Auto-update, telemetría.
