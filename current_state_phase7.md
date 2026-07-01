# Current State Phase 7

- Phase 7 closing commit date and status: 2026-07-01, IMPLEMENTED (uncommitted; user to commit)
- Phase 7 closing commit reference: pendiente de commit por el usuario
- Phase 7 scope: correccion de los tres hallazgos rojos y un hallazgo amarillo derivados de la auditoria adversarial de v1.0

## What Was Built

- Ejecucion del motor Python/ffmpeg fuera del hilo principal mediante `Task.detached`, eliminando el bloqueo de UI durante deteccion y limpieza
- Guarda de "entrada distinta de salida" en dos niveles (UI y motor) para impedir la destruccion del video original si el usuario elige el mismo archivo como entrada y como salida
- Escritura atomica del video final: `ffmpeg` escribe a un temporal adyacente al destino, y solo tras exito se reemplaza el archivo de salida existente
- Limpieza garantizada de todos los archivos temporales tambien en rutas de error
- Dos tests de regresion nuevos que fijan explicitamente los invariantes anteriores

## Files Changed

- `Sources/InpaintVideosApp/PythonVideoEngine.swift` / actualizado / conformancia `Sendable`, `Task.detached` para detect/clean, `PathUtilities` compartido, `processVideo` con `defer` de limpieza, `muxProcessedVideo` reescrito con temp adyacente y `replaceItemAt`
- `Sources/InpaintVideosApp/AppViewModel.swift` / actualizado / guarda `PathUtilities.resolvedPath(for:)` en `runCleanup` con mensaje de error inmediato al usuario
- `Tests/InpaintVideosAppTests/InpaintVideosAppTests.swift` / actualizado / test `cleanupRejectsSameInputAndOutputPath`, test `cleanupPreservesExistingOutputWhenProcessingFails`
- `AUDITORIA_ADVERSARIAL_2026-07-01.md` / creado / hallazgos en checklist semaforico
- `ESTRATEGIA_FASE7.md` / creado / plan de correccion
- `REAUDIT_FASE7.md` / creado / re-auditoria adversarial de la estrategia con 3 correcciones incorporadas
- `current_state_phase7.md` / creado / este documento

## Strategy Applied

- Se abordaron solo los hallazgos rojos y uno amarillo directamente relacionado; el resto de amarillos (ruta `.venv` en el binario, confianza en `$PATH`, stderr crudo en UI, seek por indice) queda documentado como conocido y diferido
- Los cambios de concurrencia usan la primitiva `Task.detached` con captura local del engine, evitando dependencia de `self` cruzando el boundary de Sendable
- La escritura atomica escribe el temporal en el mismo directorio del destino para que `FileManager.replaceItemAt` opere intra-volume
- La guarda de entrada=salida se aplica en dos niveles (UI y motor) como defensa en profundidad, en respuesta a un hallazgo de la re-auditoria

## Adversarial Audit Findings (v1.0 → cerrados en esta fase)

- Rojo #1 UI blocking:
  - Evidencia previa: `VideoProcessor.detectWatermark`/`.cleanVideo` marcados `async` pero sin `await` real, ejecutando `ProcessExecutor.run` bloqueante desde `AppViewModel` MainActor
  - Fix aplicado: `Task.detached` con captura local `let engine = pythonEngine`; `WatermarkDetectionResult` y `PythonVideoEngine` declarados `Sendable`
- Rojo #2 input=output destruye original:
  - Evidencia previa: `muxProcessedVideo` borraba `outputURL` antes de que `ffmpeg` leyera `sourceVideoURL`
  - Fix aplicado: guarda `PathUtilities.resolvedPath(for:)` en `AppViewModel.runCleanup` y en `VideoProcessor.cleanVideo` + `PythonVideoEngine.processVideo`
- Rojo #3 sobrescritura no atomica:
  - Evidencia previa: `muxProcessedVideo` borraba salida existente antes de generar la nueva
  - Fix aplicado: `ffmpeg` escribe a `tempFinalURL` en el directorio del destino; `replaceItemAt` (si existe destino) o `moveItem` (si no) solo tras `terminationStatus == 0`; `defer` con guarda `replaceCompleted` limpia el temp si algo falla
- Amarillo #4 temp huerfano ante fallo de Python:
  - Evidencia previa: el `defer` de `tempVideoURL` estaba dentro de `muxProcessedVideo`, no de `processVideo`
  - Fix aplicado: `defer { try? FileManager.default.removeItem(at: tempVideoURL) }` movido a `processVideo`, cubriendo fallos de `runPython` y del mux

## Re-Audit Results

- `swift build --scratch-path /private/tmp/inpaint-videos-build` completo sin warnings ni errores
- `swift test --scratch-path /private/tmp/inpaint-videos-build` paso `12/12`:
  - 10 escenarios preexistentes de fases 1-6 se mantienen verdes
  - Test nuevo `cleanupRejectsSameInputAndOutputPath` verifica que llamar a `VideoProcessor.cleanVideo` con la misma URL para entrada y salida lanza y preserva el archivo original con su tamano exacto
  - Test nuevo `cleanupPreservesExistingOutputWhenProcessingFails` verifica que ante un input invalido (bogus mp4), el contenido preexistente en `outputURL` sigue byte-a-byte identico tras la excepcion
- Todos los tests se ejecutaron en menos de 0.6 segundos, sin regresiones ni intermitencia

## Known Limitations

- Los hallazgos amarillos residuales de v1.0 siguen abiertos: la ruta al `.venv` sigue grabada en el binario en tiempo de compilacion, `ToolLocator` sigue confiando en `$PATH`, la UI sigue mostrando el stderr crudo del pipeline, y OpenCV sigue haciendo seek por indice de frame
- La estrategia de audio desacoplado (`v2.0_context.md`) sigue como propuesta, sin implementar
- `Task.detached` no hereda cancelacion; si la app se cierra durante el proceso, `ffmpeg`/`python` pueden quedar huerfanos como procesos, comportamiento ya presente en v1.0

## Rollback Instructions

1. `git status` para confirmar que solo estan presentes los archivos de fase 7 modificados
2. Revertir manualmente los tres archivos Swift a su estado previo (`Sources/InpaintVideosApp/PythonVideoEngine.swift`, `Sources/InpaintVideosApp/AppViewModel.swift`, `Tests/InpaintVideosAppTests/InpaintVideosAppTests.swift`) o `git reset --hard` al commit inmediatamente anterior una vez la fase quede committed
3. Los documentos `AUDITORIA_ADVERSARIAL_2026-07-01.md`, `ESTRATEGIA_FASE7.md` y `REAUDIT_FASE7.md` se pueden conservar como registro historico o eliminar si se prefiere una base limpia

## Next Phase Entry Conditions

- Decidir si la fase 8 aborda la propuesta de v2.0 (pipeline de audio extraido y reincorporado) o si primero se cierran los amarillos residuales de v1.0 (`.venv` embed, `$PATH` allowlist, presentacion curada de errores)
- Si se aborda la fase 8 como v2.0, definir si el resultado se publica como una nueva version de la app (`v2.0/`) siguiendo la regla de nomenclatura versionada, o como continuacion de la fase actual
- Considerar anadir un test de UI que verifique que la barra de progreso/spinner sigue respondiendo durante procesos largos, para prevenir regresiones del hallazgo 🔴 #1 (bloqueo de UI) que hoy solo esta cubierto indirectamente por la conversion de las funciones a `async` con `Task.detached`
