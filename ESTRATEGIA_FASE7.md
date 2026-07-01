# Estrategia Fase 7 — Correcciones derivadas de la auditoria adversarial

- Fecha: 2026-07-01
- Documento de auditoria origen: `AUDITORIA_ADVERSARIAL_2026-07-01.md`
- Alcance: cerrar los 3 hallazgos rojos y capturar 1 hallazgo amarillo directamente relacionado (fuga de temporales en rutas de error). Los otros amarillos (ruta `.venv` grabada, `$PATH`, texto crudo de stderr, seek por indice) se posponen para una fase de endurecimiento posterior.

## Objetivos

1. Eliminar el bloqueo del hilo principal durante deteccion y limpieza (hallazgo 🔴 #1).
2. Impedir que la aplicacion destruya el video original cuando el usuario elige la misma ruta como entrada y salida (hallazgo 🔴 #2).
3. Impedir que un fallo del re-encode borre un video de salida ya existente (hallazgo 🔴 #3).
4. Garantizar limpieza de temporales tambien en rutas de error (hallazgo 🟡 #4).

## No-objetivos

- No se modifica la heuristica de deteccion, ni el motor Python, ni el pipeline de audio (eso es materia del contexto v2.0 ya redactado).
- No se cambia la arquitectura de resolucion de herramientas (`ToolLocator`) ni la resolucion del `.venv`.
- No se toca el pipeline de empaquetado ni la firma.

## Cambios propuestos

### C1 — Ejecutar el motor Python/ffmpeg fuera del MainActor

- Archivo: `Sources/InpaintVideosApp/PythonVideoEngine.swift`
- Motivo: `VideoProcessor.detectWatermark(...)` y `.cleanVideo(...)` estan declarados `async` pero llaman codigo puramente sincrono (`ProcessExecutor.run` + `waitUntilExit`). Como se invocan desde `AppViewModel` (`@MainActor`), ejecutan el `waitUntilExit` bloqueante en el hilo principal.
- Correccion: envolver la llamada al motor Python en `Task.detached { ... }.value` para forzar ejecucion en un executor de segundo plano. Requiere que `PythonVideoEngine` y `WatermarkDetectionResult` sean `Sendable`:
  - `PythonVideoEngine` es un struct sin propiedades almacenadas → `Sendable` implicito, se documenta el requisito.
  - `WatermarkDetectionResult` contiene `CGRect` (Sendable), `[CGRect]` (Sendable si el elemento lo es), `Double` (Sendable) → `Sendable` implicito. Se anade conformidad explicita `Sendable` por claridad.
- Referencia: `VideoPreviewGenerator` ya usa un patron async real (con `withCheckedThrowingContinuation`), asi que el cambio es coherente con el estilo existente.

### C2 — Guarda entrada ≠ salida

- Archivo: `Sources/InpaintVideosApp/AppViewModel.swift`
- Motivo: elegir el mismo archivo como entrada y como salida hace que `muxProcessedVideo` borre `outputURL` **antes** de que `ffmpeg` lo lea como segundo input, destruyendo el video original sin producir salida.
- Correccion: en `runCleanup()`, antes de disparar el `Task`, comparar `inputURL.standardizedFileURL.path` con `outputURL.standardizedFileURL.path`; si coinciden, mostrar `errorMessage` inmediato y no procesar. Comparacion sobre `path` normalizado para tolerar diferencias triviales de codificacion.

### C3 — Escritura atomica al destino final

- Archivo: `Sources/InpaintVideosApp/PythonVideoEngine.swift` (funcion `muxProcessedVideo`)
- Motivo actual: la funcion borra `outputURL` **antes** de que `ffmpeg` genere el nuevo video. Si `ffmpeg` falla, el archivo bueno anterior ya se perdio.
- Correccion:
  1. Dejar de borrar `outputURL` al inicio.
  2. Dirigir la salida de `ffmpeg` a una ruta temporal (`tempFinalURL`) en el mismo directorio que `outputURL` (misma volume → replace realmente atomico).
  3. Solo tras `terminationStatus == 0`, usar `FileManager.replaceItemAt(outputURL, withItemAt: tempFinalURL)` si el destino existe, o `moveItem` si no existe.
  4. Anadir cleanup de `tempFinalURL` en un `defer` para casos de fallo intermedio.
- Efecto colateral: cubre tambien el hallazgo 🟡 #4 en el paso Python → temp file de ffmpeg, porque el `defer` de limpieza del temp de mux queda garantizado.

### C4 — Limpieza de temporales en rutas de error

- Archivo: `Sources/InpaintVideosApp/PythonVideoEngine.swift` (funcion `processVideo`)
- Motivo actual: `tempVideoURL` se genera antes de invocar Python. El `defer` que lo elimina esta dentro de `muxProcessedVideo`, no de `processVideo`, asi que si `runPython` falla, el archivo temporal queda huerfano.
- Correccion: mover el `defer { try? FileManager.default.removeItem(at: tempVideoURL) }` a `processVideo`, envolviendo tanto la llamada a Python como al mux. Asi cualquier fallo (Python o ffmpeg) libera el temporal.

## Plan de tests

- Test nuevo `cleanupRejectsSameInputAndOutputPath` — construye un video valido y llama a `cleanVideo` con `inputURL == outputURL`. Espera un `AppError` y verifica que el archivo original sigue intacto (mismo tamano y bytes que antes de la llamada).
- Test nuevo `cleanupPreservesExistingOutputWhenMuxFails` — pre-escribe contenido "bueno" en `outputURL`. Fuerza un fallo del mux configurando un `inputURL` que apruebe la deteccion pero rompa el remux (p. ej. archivo cuyo audio track no existe y forzando `--rect` con valores invalidos que hagan fallar Python). Verifica que `outputURL` conserva el contenido original tras la excepcion.
  - Nota de riesgo: forzar un fallo de mux confiable es fragil; si no se encuentra un mecanismo estable, este test se reduce a validar que `outputURL` no se toca cuando `runPython` falla (mas facil: pasar un `.mp4` bogus).
- Tests existentes que deben seguir pasando:
  - `manualCleanupOverwritesExistingOutput` (ahora garantiza mas: no solo sobreescribe, sino que lo hace sin ventana de perdida).
  - `automaticCleanupPreservesVideoDurationWhenAudioIsShorter`.
  - `automaticCleanupReducesWatermarkBrightness`.
  - Toda la suite de resolucion de rutas y geometria.

## Rollback

- Todos los cambios estan contenidos en 3 archivos Swift + 1 archivo de tests. `git reset --hard HEAD~N` desde el commit de cierre revierte la fase sin efectos colaterales fuera del proyecto.

## Riesgos residuales tras esta fase

- Si `Sendable` implicito no se aplica automaticamente por un cambio futuro del compilador Swift, `Task.detached` fallaria en compilacion → se detecta en `swift build`, no en runtime.
- `replaceItemAt` en volumenes distintos no es estrictamente atomico; escribir el temp en el mismo directorio del destino lo mitiga.
- Los hallazgos amarillos 6-9 (ruta `.venv` incrustada, `$PATH`, stderr crudo, seek por indice) siguen presentes y quedan documentados como conocidos.

## Aprobacion para pasar a implementacion

Esta estrategia se auto-aprobara solo si supera la re-auditoria adversarial documentada en la siguiente seccion del proceso.
