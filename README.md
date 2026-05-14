# HyperX Quadcast 2 S — RGB control para macOS

App local pequeña, nativa, para controlar los LEDs RGB del HyperX Quadcast 2 S
en macOS. NGENUITY (el software oficial de HyperX) es solo Windows.

**Alcance actual:** color sólido por zona (upper / lower), brillo 0–100%.
Modos animados (blink, cycle, wave, pulse) no están soportados — el protocolo
para esos modos en el 2S no ha sido decodificado todavía.

## Estructura

| Target              | Tipo        | Qué hace                                                  |
|---------------------|-------------|-----------------------------------------------------------|
| `HyperXProtocol`    | library     | Builder puro de los paquetes USB. Sin dependencias macOS. |
| `HyperXCore`        | library     | IOKit HID wrapper + refresh loop. macOS-only.             |
| `HyperXRGB`         | executable  | App SwiftUI menu bar (la app final).                      |
| `ValidateProtocol`  | executable  | Smoke tests offline del builder. Sin hardware.            |
| `HIDProbe`          | executable  | CLI de prueba: setea un color por 3 segundos.             |

## Build

```bash
swift build
```

## Verificación del protocolo (sin hardware)

```bash
swift run ValidateProtocol
# → "40 passed, 0 failed"
```

## Probar contra el mic real

Con el mic conectado:

```bash
swift run HIDProbe ff0000   # rojo por ~3s
swift run HIDProbe 00ff00   # verde
swift run HIDProbe 0080ff   # cyan
```

El LED vuelve a su animación default cuando el comando termina (el firmware
retoma el control si no llegan paquetes).

## Correr la app

```bash
swift run HyperXRGB
```

Aparece un icono de micrófono en la barra de menú. Click para abrir el panel
con dos color pickers (vinculables), slider de brillo, y status del dispositivo.

Para detener la app, click "Salir" en el panel.

## Detalles del protocolo

Reverse-engineering del [Ors1mer/QuadcastRGB](https://github.com/Ors1mer/QuadcastRGB).

- **Dispositivo HID**: VID `0x03f0` / PID `0x02b5` (nombre USB: "HyperX QuadCast 2 S Controller")
- **Audio**: VID `0x03f0` / PID `0x0d84` — dispositivo USB separado, no interfiere
- **Para color sólido** se envían 7 paquetes de 64 bytes:
  - 1 header: `[0x44, 0x01, 0x06, 0, …]`
  - 6 data packets con header `[0x44, 0x02, packet_index, 0, ...]` + bytes RGB en cada slot de LED
- **Zona upper** empieza en `packet0[4]`, **zona lower** empieza en `packet2[46]`
- Los paquetes deben **reenviarse continuamente** (~cada 150ms) o el firmware
  vuelve al color default
- En IOKit, los paquetes se envían vía `IOHIDDeviceSetReport` con
  `kIOHIDReportTypeOutput`

## Migración a Xcode (cuando esté instalado)

El código no cambia. Las opciones:

1. **Seguir con SPM**: `swift build -c release` produce el binario. Para
   distribuir como `.app` bundle: usar `swift bundler` o armar el bundle a mano
   (Info.plist con `LSUIElement = true`).
2. **Crear .xcodeproj**: `File > New > Project > macOS App`, agregar los
   archivos de `Sources/` al target. Configurar Info.plist con
   `LSUIElement = true` (Application is agent — no dock icon).

## Tests con Xcode

Una vez Xcode instalado, los tests en `Tests/HyperXProtocolTests/` corren con:

```bash
swift test
```

Mientras tanto, `ValidateProtocol` corre las mismas verificaciones como
ejecutable.

## Fuera de alcance

- Modos animados (requieren captura USB de NGENUITY en una VM Windows).
- Soporte de otros mics HyperX (Quadcast S original, Duocast).
- Distribución firmada/notarizada.
- Auto-update, telemetría.
