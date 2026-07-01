# Inpaint Videos

Aplicacion local para macOS Apple Silicon que limpia marcas de agua de videos `.mp4`.

## Estado actual

Esta primera fase implementa:

- Seleccion de video de entrada `.mp4`
- Vista previa del primer frame
- Marcado manual del rectangulo donde aparece la marca de agua
- Exportacion de un nuevo video usando `ffmpeg` y el filtro `delogo`

## Requisitos

- macOS con Apple Silicon
- Xcode 26 o superior
- `ffmpeg` y `ffprobe` instalados en `/opt/homebrew/bin`

## Ejecutar

```bash
swift run InpaintVideosApp
```

## Alcance de la fase 1

La deteccion automatica de la marca y el inpainting basado en IA no estan implementados todavia. La arquitectura deja preparada una fase posterior para incorporar OpenCV o modelos dedicados.
