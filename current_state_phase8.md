# Current State Phase 8

- Phase 8 closing commit date and status: 2026-07-01, IMPLEMENTED (uncommitted; user to commit)
- Phase 8 closing commit reference: pendiente de commit por el usuario
- Phase 8 scope: correccion del unico hallazgo rojo (S1) descubierto en la auditoria adversarial con simulacion real sobre `video luna.MP4` — falso positivo del detector `detect_corner_watermark` que inpaintaba una region sin marca real

## What Was Built

- Umbral de evidencia positivo en `detect_corner_watermark`: la region candidata solo se acepta si su `brightness_map[mask].mean() >= 0.20` **o** `edge_mean[mask].mean() >= 0.15`
- Iteracion sobre los candidatos ordenados por score, no solo sobre el top: si el top candidate no presenta evidencia, se pasa al siguiente hasta encontrar uno legitimo o devolver `None`
- Test de regresion negativo `automaticDetectionRejectsFalsePositiveCornerOnDarkFrame` que ejerce el invariante "video sin marca en la esquina → no aparece region de esquina"

## Files Changed

- `Scripts/watermark_pipeline.py` / actualizado / constantes `CORNER_BRIGHTNESS_EVIDENCE_MIN=0.20` y `CORNER_EDGE_EVIDENCE_MIN=0.15`, filtro de evidencia por candidato en `detect_corner_watermark`, propagacion de `edge_mean` desde `detect_watermark`
- `Tests/InpaintVideosAppTests/InpaintVideosAppTests.swift` / actualizado / test `automaticDetectionRejectsFalsePositiveCornerOnDarkFrame` + helper `generateVideoWithoutCornerWatermark`
- `AUDITORIA_ADVERSARIAL_2026-07-01_SIMULACION.md` / previa / auditoria con evidencia real que motivo la fase
- `ESTRATEGIA_FASE8.md` / creado / plan de correccion con umbrales calibrados empiricamente
- `REAUDIT_FASE8.md` / creado / re-auditoria adversarial de la estrategia
- `current_state_phase8.md` / creado / este documento

## Strategy Applied

- Se resolvio unicamente el rojo S1. Los amarillos S2 (calidad de inpainting), S3 (double-encode), S4 (VFR) quedan diferidos al rediseno de v2.0. S5 (barra de progreso) queda para una fase de UX separada.
- Los umbrales de evidencia (0.20 y 0.15) se calibraron con medicion real sobre 4 casos: la region falsa positiva del video luna (0.10 y 0.11) y los tres candidatos top del video sintetico usado por los tests (0.55 a 0.99 en brillo). Los umbrales caen limpiamente entre ambos grupos.
- La logica se aplico al detector `detect_corner_watermark`, sin tocar `detect_top_right_overlay`, que en la simulacion real funciono correctamente.

## Adversarial Audit Findings (S1 → cerrado en esta fase)

- Rojo S1 falso positivo del corner detector:
  - Evidencia previa: sobre `video luna.MP4`, el detector devolvia la region `(x=0.9611, y=0.8312, w=0.0389, h=0.05)` con confidence 0.6073 aunque en 4 timestamps muestreados (0.5s, 3s, 6s, 9s) esa region tenia 0 pixeles brillantes >= 230; el pipeline inpaintaba pixeles reales del contenido con una diferencia media de 20 unidades de gris
  - Fix aplicado: en `detect_corner_watermark`, cada candidato se evalua contra el umbral de brillo o el de bordes; se acepta el primero que pase, y si ninguno pasa se devuelve `None`
  - Verificacion end-to-end: tras el fix, `detect --input "video luna.MP4"` devuelve una sola region (la banda superior derecha real) con confidence 0.4436, sin fabricar la esquina; el output final ya no altera pixeles del bottom-right y la diferencia entre las salidas de fase 7 y fase 8 en esa region es exactamente 7.5 unidades de gris (el inpainting espurio eliminado)

## Re-Audit Results

- `swift test --scratch-path /private/tmp/inpaint-videos-build` paso `13/13`:
  - Los 12 tests preexistentes siguen verdes (`automaticDetectionFindsBottomRightWatermark` con umbral `brightness_map.mean()=0.94` sigue muy por encima del filtro)
  - Test nuevo `automaticDetectionRejectsFalsePositiveCornerOnDarkFrame` verifica sobre un video sintetico sin marca de esquina que solo se detecta la banda superior derecha y no aparece region con `x>0.55, y>0.55`
- Verificacion contra la muestra real `video luna.MP4`:
  - Antes de la fase 8: 2 regiones (`[bottom-right FP, top-right banner]`), confidence 0.6073
  - Despues de la fase 8: 1 region (`[top-right banner]`), confidence 0.4436
  - La confidence baja porque ahora refleja solo la senal de la region real, no una media de dos regiones — comportamiento correcto
- Comparacion pixel a pixel entre salidas de fase 7 y fase 8 en la region antes falsa positiva a t=6s:
  - Diferencia media de gris: 7.50
  - Es exactamente el aporte del inpainting espurio que se elimino
  - El resto de la diferencia contra el input (20.29) proviene del double-encode HEVC → MPEG-4 → H.264, ya conocido como hallazgo amarillo S3

## Known Limitations

- Los umbrales 0.20 y 0.15 se calibraron con dos muestras (una real, una sintetica). Videos con marcas de agua tenues, semitransparentes o de contraste bajo podrian caer justo por debajo del umbral y quedar sin detectar; en ese caso queda el respaldo del modo manual
- El detector `detect_top_right_overlay` no se modifico y no comparte esta salvaguarda; si en el futuro se descubre un falso positivo simetrico ahi, requerira un tratamiento equivalente
- Los amarillos residuales (S2 calidad del inpainting, S3 double-encode, S4 VFR, S5 progreso de UI) siguen abiertos y documentados

## Rollback Instructions

1. `git status` para confirmar que solo estan presentes los archivos de fase 8 modificados
2. Revertir manualmente `Scripts/watermark_pipeline.py` y `Tests/InpaintVideosAppTests/InpaintVideosAppTests.swift` a su estado previo, o `git reset --hard` al commit inmediatamente anterior una vez la fase quede committed
3. Los documentos `ESTRATEGIA_FASE8.md` y `REAUDIT_FASE8.md` se pueden conservar como registro historico o eliminar

## Next Phase Entry Conditions

- Decidir si la fase 9 aborda la propuesta de v2.0 (pipeline de audio extraido y reincorporado, que resuelve S3 y S4 de raiz), o si primero se cierran los amarillos restantes de v1.0
- Si se descubren otros falsos positivos con muestras adicionales, considerar exponer un `confidence` por region en el JSON (hoy solo hay uno global) y filtrar en la UI las regiones bajo un piso configurable
- Considerar anadir feedback de progreso incremental (S5) como fase de UX independiente si se planea limpiar videos largos (60+ s)
