# MarkOff

Aplicacion local para macOS Apple Silicon que limpia marcas de agua de videos `.mp4`.

## Estado actual

La version 1.0 implementa:

- Seleccion de video de entrada `.mp4`
- Vista previa del primer frame
- Deteccion automatica de una o varias regiones candidatas para la marca
- Inpainting real por frame con OpenCV (`cv2.inpaint`)
- Modo manual de respaldo con rectangulo editable
- Exportacion de un nuevo video con audio remuxeado desde el original
- Empaquetado de distribucion en `.app` y `.dmg` para macOS arm64
- Icono personalizado de la app integrado en el bundle macOS

## Requisitos

- macOS Tahoe 26 sobre Apple Silicon
- Xcode 26 o superior
- `ffmpeg` y `ffprobe` accesibles desde el sistema
- `python3` disponible en el sistema o entorno local `.venv`
- Dependencias Python: `numpy` y `opencv-python-headless`

## Ejecutar en desarrollo

```bash
swift run MarkOffApp
```

## Preparar dependencias Python

```bash
python3 -m venv .venv
./.venv/bin/pip install numpy opencv-python-headless
```

## Generar app y DMG

```bash
./Scripts/build_release_bundle.sh
```

Artefacto generado:

- `dist/MarkOff-macos-arm64.dmg`

Nota:

- El `.app` firmado se construye en un staging temporal fuera de `Documents` para evitar atributos extendidos que invalidan `codesign`, y queda encapsulado dentro del `.dmg`

## Generar instalador .pkg

```bash
./Scripts/build_pkg_installer.sh
```

Artefacto generado:

- `dist/MarkOff-macos-arm64.pkg`

El `.pkg` instala `MarkOff.app` en `/Applications`. Reutiliza el mismo staging endurecido y firma del `.app`, y luego usa `pkgbuild` con `--install-location /Applications`.

Notas del instalador:

- El paquete instala la app pero **no incluye** `python3`, `ffmpeg` ni `ffprobe`: siguen siendo dependencias del equipo destino
- El `.pkg` no esta firmado con `Developer ID Installer` (no hay certificado de ese tipo en el equipo), por lo que en otros Macs Gatekeeper puede requerir abrirlo con clic derecho > Abrir o instalarlo con `sudo installer -pkg <ruta> -target /`

## Limitaciones conocidas de v1.0

- Si el pipeline elimina o recompone frames, la pista de audio puede quedar mas corta que el video final
- La deteccion automatica sigue siendo heuristica y esta optimizada para overlays pequenos y persistentes, especialmente cercanos al borde
- El motor de eliminacion usa inpainting clasico de OpenCV, no un modelo generativo entrenado
- La app empaquetada sigue dependiendo de `ffmpeg` y `python3` disponibles en el equipo destino

## Licencia

Copyright (c) 2026 Lluviaicloud. Todos los derechos reservados.

Este proyecto no tiene una licencia de codigo abierto. El codigo se publica unicamente para consulta. No se concede permiso para usar, copiar, modificar, distribuir ni crear obras derivadas sin autorizacion previa por escrito del autor.
