# Inpaint Videos

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
swift run InpaintVideosApp
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

- `dist/InpaintVideos-macos-arm64.dmg`

Nota:

- El `.app` firmado se construye en un staging temporal fuera de `Documents` para evitar atributos extendidos que invalidan `codesign`, y queda encapsulado dentro del `.dmg`

## Limitaciones conocidas de v1.0

- Si el pipeline elimina o recompone frames, la pista de audio puede quedar mas corta que el video final
- La deteccion automatica sigue siendo heuristica y esta optimizada para overlays pequenos y persistentes, especialmente cercanos al borde
- El motor de eliminacion usa inpainting clasico de OpenCV, no un modelo generativo entrenado
- La app empaquetada sigue dependiendo de `ffmpeg` y `python3` disponibles en el equipo destino
