# Auditoria Adversarial — Inpaint Videos (estado v1.0, post-fase 6)

- Fecha: 2026-07-01
- Alcance: `Sources/InpaintVideosApp/*.swift`, `Scripts/watermark_pipeline.py`, `Scripts/build_release_bundle.sh`, `Package.swift`, `Tests/InpaintVideosAppTests/*.swift`
- Metodo: lectura adversarial linea por linea, sin ejecutar build/tests (auditoria de codigo estatica). No se modifico nada.

## Checklist semaforico

| # | Severidad | Area | Hallazgo |
|---|-----------|------|----------|
| 1 | 🔴 Rojo | Concurrencia / UI | La deteccion y limpieza bloquean el hilo principal durante todo el procesamiento (congelan la app) |
| 2 | 🔴 Rojo | Perdida de datos | Elegir el mismo archivo como entrada y salida destruye el video original antes de procesarlo |
| 3 | 🔴 Rojo | Perdida de datos | Sobrescribir una salida ya existente la borra antes de confirmar que el nuevo render tendra exito |
| 4 | 🟡 Amarillo | Recursos | Video temporal en `/tmp` queda huerfano si el paso Python falla antes del remux |
| 5 | 🟡 Amarillo | Recursos | Archivos temporales de stdout/stderr pueden quedar huerfanos si `Process.run()` falla |
| 6 | 🟡 Amarillo | Portabilidad | La ruta al `.venv` esta grabada en el binario compilado como ruta absoluta de la maquina de build |
| 7 | 🟡 Amarillo | Cadena de herramientas | `ToolLocator` confia en todo `$PATH`, ejecutando el primer binario que encuentre |
| 8 | 🟡 Amarillo | UX de errores | Los mensajes de error muestran texto crudo de stderr (trazas de Python/ffmpeg) directamente en la UI |
| 9 | 🟡 Amarillo | Heuristica | El muestreo de frames usa `CAP_PROP_POS_FRAMES`, impreciso en video VFR o con GOPs largos |
| 10 | 🟢 Verde | Inyeccion | Los argumentos a `ffmpeg`/`python3` se pasan como array (`Process.arguments`), no hay interpolacion de shell |
| 11 | 🟢 Verde | Robustez numerica | `normalize_map` protege division por cero cuando el frame es uniforme |
| 12 | 🟢 Verde | Vista previa | `VideoPreviewGenerator` usa APIs async reales (no bloquea el hilo principal) |
| 13 | 🟢 Verde | Empaquetado | El pipeline de firma/DMG (fase 5) ya fue endurecido y verificado con `codesign --verify --deep --strict` sobre el `.dmg` montado |
| 14 | 🟢 Verde | Cobertura de tests | Existe suite de regresion para geometria, deteccion, duracion de audio y resolucion de rutas |

---

## Detalle de hallazgos criticos (🔴)

### 1. Bloqueo del hilo principal durante deteccion/limpieza

- Evidencia: [`Sources/InpaintVideosApp/PythonVideoEngine.swift:13-15`](Sources/InpaintVideosApp/PythonVideoEngine.swift:13), [`PythonVideoEngine.swift:17-29`](Sources/InpaintVideosApp/PythonVideoEngine.swift:17), [`ProcessExecutor.swift:9-48`](Sources/InpaintVideosApp/ProcessExecutor.swift:9)
- `VideoProcessor.cleanVideo(...)` y `.detectWatermark(...)` estan marcados `async throws`, pero sus cuerpos llaman directamente a funciones **sincronas** (`pythonEngine.processVideo`, `.detectWatermark`) sin ningun `await` interno. En Swift Concurrency, una funcion `async` que nunca suspende no cede el hilo: se ejecuta enteramente en el executor que la invoco.
- `AppViewModel` es `@MainActor`, y los `Task { ... }` en `runCleanup()` ([`AppViewModel.swift:106-123`](Sources/InpaintVideosApp/AppViewModel.swift:106)) y `detectWatermark()` ([`AppViewModel.swift:135-151`](Sources/InpaintVideosApp/AppViewModel.swift:135)) heredan el aislamiento del MainActor. Como no hay suspension real en la cadena, `ProcessExecutor.run` (que llama a `process.waitUntilExit()`, una espera bloqueante) se ejecuta **en el hilo principal**.
- Impacto: durante todo el analisis de frames con OpenCV y el re-encode con `ffmpeg`, la app deja de responder (beachball, "no responde" en Forzar salida), no hay animacion del boton "Procesando...", y el usuario no puede cancelar.
- Nota: contrasta con `VideoPreviewGenerator` ([`VideoPreviewGenerator.swift:30-46`](Sources/InpaintVideosApp/VideoPreviewGenerator.swift:30)), que si usa una API asincrona real (`generateCGImageAsynchronously` + continuation) y no bloquea. El patron correcto ya existe en el proyecto, simplemente no se aplico al motor Python/ffmpeg.
- Sugerencia (no aplicada): envolver `ProcessExecutor.run` en `Task.detached` o despachar a una cola en segundo plano mediante `withCheckedThrowingContinuation`, igual que hace `VideoPreviewGenerator`.

### 2. Elegir el mismo archivo como entrada y salida borra el video original

- Evidencia: [`PythonVideoEngine.swift:71-94`](Sources/InpaintVideosApp/PythonVideoEngine.swift:71)
- `muxProcessedVideo` primero borra `outputURL` si existe (`FileManager.default.removeItem`) y **despues** ejecuta `ffmpeg -i processedVideo -i sourceVideoURL ...`. Si el usuario usa "Guardar Como" ([`AppViewModel.swift:65-75`](Sources/InpaintVideosApp/AppViewModel.swift:65)) y selecciona el mismo archivo de entrada como destino — un gesto plausible si quiere "sobrescribir en el sitio" — se borra el archivo fuente antes de que `ffmpeg` intente leerlo como segundo input, `ffmpeg` falla por archivo inexistente, y el resultado neto es: video original destruido, sin salida generada.
- No hay ninguna guarda en el codigo que compare `inputURL` contra `outputURL` antes de procesar.
- Sugerencia (no aplicada): comparar rutas normalizadas de entrada/salida antes de `runCleanup()` y bloquear/advertir si coinciden; o renderizar siempre a un archivo temporal y mover al destino final solo tras exito.

### 3. Sobrescribir una salida existente la borra antes de confirmar exito

- Evidencia: misma funcion, [`PythonVideoEngine.swift:72-74`](Sources/InpaintVideosApp/PythonVideoEngine.swift:72)
- Si `outputURL` ya contiene un video limpio de una ejecucion anterior (buena), y el usuario vuelve a ejecutar la limpieza sobre la misma ruta de salida, el archivo bueno se borra **antes** de saber si el nuevo `ffmpeg` mux tendra exito. Si el segundo intento falla (codec, disco lleno, entrada corrupta, etc.), el usuario pierde el resultado anterior sin ningun respaldo.
- Sugerencia (no aplicada): escribir siempre a una ruta temporal y hacer `replaceItemAt` (operacion atomica de reemplazo) solo cuando el mux termine con exito.

---

## Detalle de hallazgos moderados (🟡)

### 4-5. Fugas de archivos temporales en rutas de error

- Evidencia: [`PythonVideoEngine.swift:42-69`](Sources/InpaintVideosApp/PythonVideoEngine.swift:42) (el `defer` que limpia `tempVideoURL` vive dentro de `muxProcessedVideo`, no se alcanza si `runPython` falla antes); [`ProcessExecutor.swift:20-27`](Sources/InpaintVideosApp/ProcessExecutor.swift:20) (si `process.run()` lanza, los archivos de stdout/stderr ya creados no se limpian).
- Impacto bajo (archivos pequenos/vacios en `/tmp`, que el sistema limpia eventualmente), pero es acumulacion silenciosa en fallos repetidos.

### 6. Ruta del `.venv` grabada en el binario en tiempo de compilacion

- Evidencia: [`ProjectPaths.swift:4-9`](Sources/InpaintVideosApp/ProjectPaths.swift:4), usado en [`PythonVideoEngine.swift:129-136`](Sources/InpaintVideosApp/PythonVideoEngine.swift:129)
- `projectRoot` se calcula con `#filePath`, que el compilador incrusta como cadena literal absoluta de la maquina donde se compilo (`~/Documents/Inpaint_videos/...`). En una `.app` distribuida a otra maquina esa ruta nunca existira, por lo que `virtualEnvPython` siempre fallara alli y el codigo cae (correctamente) a `python3` del sistema via `ToolLocator`. Funciona por el fallback, pero:
  - Efecto secundario menor: el nombre de usuario y estructura de carpetas del desarrollador queda visible como texto plano dentro del ejecutable (`strings InpaintVideosApp` lo revela).
  - Ya es una limitacion conocida documentada (dependencia de `python3` del sistema), pero el mecanismo exacto (ruta *build-time*, no *runtime*) no estaba explicitado en las fases previas.

### 7. `ToolLocator` confia en todo `$PATH`

- Evidencia: [`ToolLocator.swift:16-22`](Sources/InpaintVideosApp/ToolLocator.swift:16)
- Si un directorio anterior en `$PATH` del usuario contuviera un binario llamado `ffmpeg`/`python3` distinto del esperado, la app lo ejecutaria sin verificacion de origen. Riesgo bajo para una app local de un solo usuario, pero vale la pena documentarlo si esto se distribuye a terceros.

### 8. Mensajes de error exponen texto crudo de stderr

- Evidencia: [`PythonVideoEngine.swift:96-99`](Sources/InpaintVideosApp/PythonVideoEngine.swift:96), mostrado via `errorMessage` en [`ContentView.swift:139-143`](Sources/InpaintVideosApp/ContentView.swift:139)
- No es un bug de seguridad, pero trazas de Python/ffmpeg sin curar pueden ser confusas para el usuario final.

### 9. Muestreo de frames con seek por indice

- Evidencia: [`watermark_pipeline.py:52-53`](Scripts/watermark_pipeline.py:52) — `capture.set(cv2.CAP_PROP_POS_FRAMES, ...)` seguido de `.read()`
- OpenCV con backends basados en FFmpeg puede posicionar de forma imprecisa en contenedores con frame rate variable o keyframes espaciados; el impacto es sobre la precision heuristica de deteccion, no un crash (ya mitigado por el fallback manual).

---

## Lo que ya esta bien (🟢), verificado en esta pasada

- Todos los argumentos a procesos externos se pasan como arrays (`Process.arguments`), nunca interpolados en un string de shell → sin riesgo de inyeccion de comandos.
- `normalize_map` evita division por cero cuando `min == max` en un mapa de score.
- La generacion de vista previa (`VideoPreviewGenerator`) es realmente asincrona y no bloquea la UI — el patron correcto ya existe en el proyecto, solo falta aplicarlo al motor de procesamiento (ver hallazgo #1).
- El pipeline de empaquetado (`build_release_bundle.sh`) ya fue endurecido en la fase 5: staging fuera de `Documents`, copias con `ditto --norsrc --noextattr --noqtn --noacl`, verificacion `codesign --verify --deep --strict` sobre el `.app` montado desde el `.dmg` generado.
- Existe una suite de tests de regresion real (10 escenarios) cubriendo geometria, deteccion multi-region, preservacion de duracion de audio, y resolucion de rutas del script empaquetado vs. checkout — pero **ninguno de estos tests cubre los hallazgos 1, 2 y 3** (bloqueo de UI, entrada=salida, sobrescritura destructiva), porque son escenarios que un test headless no ejercita naturalmente.

## Recomendacion de priorizacion

1. Hallazgo #2 y #3 (perdida de datos) — corregirlos antes de cualquier otra cosa; son los unicos que pueden destruir contenido del usuario sin posibilidad de deshacer.
2. Hallazgo #1 (bloqueo de UI) — no destruye datos, pero es el defecto de experiencia mas grave y mas facil de notar por cualquier usuario.
3. Hallazgos #4-9 — limpieza tecnica de menor impacto, abordables en una pasada de endurecimiento posterior.
