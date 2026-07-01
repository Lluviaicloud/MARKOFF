# Re-auditoria de la Estrategia Fase 7

- Fecha: 2026-07-01
- Documento auditado: `ESTRATEGIA_FASE7.md`
- Metodo: lectura adversarial de la estrategia, buscando fallos logicos, edge cases y omisiones.

## Hallazgos de re-auditoria

### Rojo: guarda de entrada=salida solo en `AppViewModel` es incompleta

- Problema: la estrategia (C2) coloca la comparacion de paths unicamente en `AppViewModel.runCleanup()`. `VideoProcessor.cleanVideo(...)` sigue siendo llamable desde tests (y desde cualquier futura llamada no-UI) con `inputURL == outputURL` sin proteccion, replicando el bug original.
- Ademas, el test propuesto `cleanupRejectsSameInputAndOutputPath` opera contra `VideoProcessor` directamente y no contra `AppViewModel`, por lo que la guarda que se probaria no seria la que se implementaria.
- Correccion al plan: **defensa en profundidad**. Guard tambien en `VideoProcessor.cleanVideo(...)` (o en `PythonVideoEngine.processVideo(...)`) lanzando `AppError` si los paths coinciden. La guarda en `AppViewModel` se conserva como feedback inmediato al usuario antes de mostrar "Procesando...".

### Amarillo: comparacion de rutas no cubre alias / symlinks

- Problema: `standardizedFileURL.path` normaliza `..` y `.` pero no resuelve symlinks. Si el usuario apunta como salida un symlink al video de entrada, la comparacion falla y el bug se materializa.
- Correccion al plan: usar `resolvingSymlinksInPath().standardizedFileURL.path` para la comparacion. Aceptar que si el `outputURL` aun no existe fisicamente, `resolvingSymlinksInPath` devuelve la ruta tal cual — suficiente porque un output inexistente no puede ser alias del input existente.

### Amarillo: el test de "preservacion de output ante fallo" apuntaba a un mecanismo fragil

- Problema: la estrategia planteaba forzar un fallo del mux para probar que `outputURL` sobrevive. Forzar un fallo *especifico* del mux (no del Python) es fragil y depende de trucos con codecs.
- Correccion al plan: relajar el test al contrato mas amplio: "si cualquier paso falla, `outputURL` preexistente no se toca". La forma mas simple es pasar un input invalido (por ejemplo, bytes que no son un MP4 real, como en `detectionFailsForNonVideoFile`) y pre-poblar `outputURL` con contenido conocido, verificando que ese contenido sigue igual tras la excepcion. Esto prueba el mismo invariante que motiva C3.

### Verde: la mecanica de `Task.detached` es correcta

- `WatermarkDetectionResult` y `PythonVideoEngine` son `Sendable` implicito por composicion (`CGRect`, `Double`, `[CGRect]`, sin propiedades para el engine).
- Capturar `let engine = pythonEngine` local antes del `Task.detached` es la practica correcta para evitar depender de `self` cruzando el boundary de Sendable.
- El closure de `Task.detached` puede lanzar; `.value` propaga la excepcion, preservando la semantica actual.

### Verde: `replaceItemAt` en el mismo directorio del destino es la eleccion adecuada

- Al escribir el temporal en `outputURL.deletingLastPathComponent()`, el `replaceItemAt` opera intra-volume y es atomico. En volumenes con permisos restringidos el proceso fallara con error claro (aceptable: el usuario eligio esa carpeta con `NSSavePanel`).

### Verde: el `defer` de limpieza en `processVideo` cubre C4 correctamente

- Al mover el `defer { try? FileManager.default.removeItem(at: tempVideoURL) }` desde `muxProcessedVideo` a `processVideo`, cualquier throw en la cadena (`runPython` o `muxProcessedVideo`) libera el temporal.

## Riesgos residuales aceptados

- `Task.detached` no hereda cancelacion — quedan `Process` huerfanos si el usuario mata la app durante el proceso. Ya era asi antes; queda fuera del alcance de esta fase.
- Si el disco de destino se llena entre la escritura del temp y el replace, `replaceItemAt` fallara y no habra output nuevo, pero el viejo se conserva (comportamiento correcto).

## Decision

Estrategia **APROBADA con las 3 correcciones anteriores integradas**:
1. Guard entrada=salida en `VideoProcessor.cleanVideo` (defensa en profundidad) ademas del guard UX en `AppViewModel`.
2. Comparacion de paths via `resolvingSymlinksInPath().standardizedFileURL.path`.
3. Test de preservacion usa input invalido (bogus mp4) contra output pre-populado, no un fallo forzado del mux.

Se procede a implementar con las tres correcciones incorporadas.
