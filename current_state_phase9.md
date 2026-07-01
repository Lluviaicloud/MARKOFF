# Current State Phase 9

- Phase 9 closing date and status: 2026-07-01, IMPLEMENTED (uncommitted; user to commit)
- Phase 9 scope: barra de progreso real de limpieza en la parte inferior + ventana compacta tipo QuickTime

## What Was Built

- Barra de progreso **determinada** (0-100%) de la limpieza, situada en la parte inferior de la ventana, alimentada por el progreso real frame a frame del motor Python
- Ventana de la aplicacion mucho mas pequena y compacta, estilo QuickTime (vertical, centrada en el video), reemplazando el layout ancho de dos columnas de 1100x760
- Los campos numericos del rectangulo manual ahora solo se muestran en modo Manual, reduciendo el desorden en modo Auto

## Files Changed

- `Scripts/watermark_pipeline.py` / actualizado / funcion `write_progress`, parametro `--progress-file`, emision de fraccion 0..1 cada 3 frames en `process_video`, propagacion desde `main`
- `Sources/InpaintVideosApp/PythonVideoEngine.swift` / actualizado / parametro `progressURL` en `VideoProcessor.cleanVideo` y `PythonVideoEngine.processVideo`, que se traduce a `--progress-file`
- `Sources/InpaintVideosApp/AppViewModel.swift` / actualizado / propiedad `cleanupProgress: Double?`, creacion de archivo temporal de progreso, tarea de sondeo `startProgressPolling`, limpieza del archivo en `defer`
- `Sources/InpaintVideosApp/ContentView.swift` / reescrito / layout compacto vertical (toolbar con iconos + preview flexible + campos manuales condicionales + barra inferior con `ProgressView`)
- `Sources/InpaintVideosApp/main.swift` / actualizado / ventana `minWidth 380, idealWidth 460, minHeight 560, idealHeight 720` en lugar de `minWidth 1100, minHeight 760`

## Strategy Applied

- **Progreso via archivo, no via pipe**: el motor Python escribe la fraccion de avance en un archivo temporal que Swift sondea cada 120 ms. Este enfoque evita por completo el riesgo de deadlock de pipe que se corrigio en la fase 4 (el `ProcessExecutor` sigue capturando stdout/stderr a archivos y esperando con `waitUntilExit`), y aprovecha que desde la fase 7 el proceso Python corre en `Task.detached` fuera del hilo principal, dejando el MainActor libre para sondear.
- **Barra determinada, no indeterminada**: se usa el conteo de frames (`CAP_PROP_FRAME_COUNT`) para reportar avance real. Si el conteo no esta disponible (`<= 0`), Python no escribe fracciones y la UI muestra una barra indeterminada mientras `isProcessing` esta activo.
- **Layout compacto preservando funcionalidad**: se paso de dos columnas anchas a una pila vertical centrada en el video; se conservaron todas las acciones (abrir, guardar como, detectar, limpiar, selector de modo, edicion manual, confianza, estado, error) y se anadio la barra.

## Verification

- `python3 -m py_compile Scripts/watermark_pipeline.py`: OK
- `swift build --scratch-path /private/tmp/inpaint-videos-build`: compila sin warnings
- `swift test`: `13/13` verde (ningun test preexistente regresiona; el nuevo parametro `progressURL` tiene valor por defecto `nil`, por lo que las llamadas de test siguen validas)
- Verificacion end-to-end del progreso real contra `~/Desktop/video luna.MP4`:
  - El archivo de progreso avanza monotona y suavemente: `0.0769 → 0.2212 → 0.3654 → 0.5096 → 0.6731 → 0.8462 → 1.0000`
  - Es exactamente la secuencia que la barra de Swift lee y muestra como porcentaje
- La app se lanzo con `swift run` para inspeccion visual de la ventana compacta

## Known Limitations

- Durante el paso final de mux con `ffmpeg` (~1 s) la barra permanece cerca del 100%, porque el progreso frame a frame solo cubre la fase de inpainting de OpenCV, que es la dominante
- La barra de progreso cubre unicamente la limpieza (`isProcessing`), no la deteccion (`isDetecting`), que es rapida (muestrea ~12 frames)
- La marca de agua tipo estrella fija en la esquina inferior (reportada por el usuario) sigue sin resolverse: pertenece a la funcionalidad de "marcas fijas manuales" que quedo pendiente de decision de alcance
- Los amarillos residuales de auditorias previas (double-encode S3, VFR S4, calidad de inpainting S2) siguen abiertos

## Rollback Instructions

1. `git status` para confirmar el conjunto de archivos de fase 9
2. Revertir manualmente los 5 archivos listados o `git reset --hard` al commit anterior una vez la fase quede committed

## Next Phase Entry Conditions

- Retomar la decision de alcance sobre "marcas fijas manuales" (varias marcas vs una; combinar con auto vs modo aparte) para poder eliminar la estrella fija de la esquina inferior
- Considerar cubrir la fase de mux dentro del progreso reportado (ponderar Python 0-90%, mux 90-100%) si se quiere un avance mas fiel en el ultimo tramo
