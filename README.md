# Inpaint Videos

Aplicacion local para macOS Apple Silicon que limpia marcas de agua de videos `.mp4`.

## Estado actual

La fase 2 implementa:

- Seleccion de video de entrada `.mp4`
- Vista previa del primer frame
- Deteccion automatica de una region candidata para la marca de agua
- Inpainting real por frame con OpenCV (`cv2.inpaint`)
- Modo manual de respaldo con rectangulo editable
- Exportacion de un nuevo video con audio remuxeado desde el original

## Requisitos

- macOS con Apple Silicon
- Xcode 26 o superior
- `ffmpeg` y `ffprobe` instalados en `/opt/homebrew/bin`
- Entorno Python local en `.venv` con `numpy` y `opencv-python-headless`

## Ejecutar

```bash
swift run InpaintVideosApp
```

## Preparar dependencias Python

```bash
python3 -m venv .venv
./.venv/bin/pip install numpy opencv-python-headless
```

## Alcance actual

- La deteccion automatica actual es heuristica y esta optimizada para overlays pequenos y persistentes, especialmente cercanos al borde
- El motor de eliminacion usa inpainting clasico de OpenCV, no un modelo generativo entrenado
- Si la autodeteccion falla o la confianza no es suficiente, la app permite correccion manual antes de exportar
