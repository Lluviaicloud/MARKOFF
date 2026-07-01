# Estrategia Fase 8 — Corregir falso positivo del detector de esquina

- Fecha: 2026-07-01
- Auditoria origen: `AUDITORIA_ADVERSARIAL_2026-07-01_SIMULACION.md`, hallazgo S1 (unico rojo)
- Alcance: correccion quirurgica del falso positivo del detector `detect_corner_watermark` de `Scripts/watermark_pipeline.py`. Nada mas.

## Objetivo

Impedir que `detect_corner_watermark` devuelva una region cuando el candidato ganador carece de evidencia real de marca de agua (ni brillo destacado ni bordes), como ocurre hoy con la esquina inferior derecha del video `video luna.MP4` (region 28x64 px sin pixeles brillantes que sin embargo se inpainta).

## No-objetivos

- No se toca el algoritmo de inpainting (S2 requiere modelo generativo, fuera de alcance).
- No se cambia el codec intermedio de OpenCV (S3 pertenece al rediseno de v2.0).
- No se aborda VFR/CFR (S4 pertenece al rediseno de v2.0).
- No se anade barra de progreso (S5 es UX, materia de otra fase).
- No se modifica el detector `detect_top_right_overlay` — sigue funcionando bien sobre el mismo video real.

## Diagnostico calibrado empiricamente

Se midio `brightness_map[componentMask].mean()` y `edge_mean[componentMask].mean()` para el top candidate:

| Caso | brightness_map | edge_mean | raw_mean_gray | veredicto esperado |
|------|----------------|-----------|----------------|--------------------|
| video luna, esquina falsa positiva | 0.1018 | 0.1124 | 17.89 | rechazar |
| synthetic test, rank 0 (parche blanco) | 0.9389 | 0.0820 | 239.4 | mantener |
| synthetic test, rank 1 (parche blanco chico) | 0.9900 | 0.1061 | 252.4 | mantener |
| synthetic test, rank 2 (banda blanca) | 0.5536 | 0.1458 | 141.2 | mantener |

Regla de decision que separa limpiamente estos casos:

```
if brightness_map[componentMask].mean() >= 0.20
   OR edge_mean[componentMask].mean() >= 0.15:
    aceptar
else:
    descartar
```

- Falso positivo (0.10 y 0.11) queda por debajo de ambos umbrales → se descarta.
- Todos los positivos observados quedan claramente por encima de al menos uno de los dos umbrales → se mantienen.

## Cambios propuestos

### C1 — `detect_watermark` pasa `edge_mean` al detector de esquina

- Archivo: `Scripts/watermark_pipeline.py`, funcion `detect_watermark`.
- Cambio: incluir `edge_mean` en la lista de argumentos de `detect_corner_watermark(...)`.

### C2 — `detect_corner_watermark` itera candidatos y aplica el filtro de evidencia

- Archivo: `Scripts/watermark_pipeline.py`, funcion `detect_corner_watermark`.
- Cambio:
  1. Anadir `edge_mean` como parametro.
  2. Iterar sobre `candidates` (no solo `candidates[0]`), aplicando la regla de decision anterior a cada uno.
  3. Devolver el primer candidato que pase el filtro; si ninguno pasa, devolver `None`.
- Justificacion: iterar en vez de bloquear solo el top permite recuperar un segundo candidato legitimo cuando el primero es un falso positivo (por diseno, `candidates` esta ordenado por score, no por evidencia).

### C3 — Test de regresion negativo

- Archivo: `Tests/InpaintVideosAppTests/InpaintVideosAppTests.swift`.
- Test nuevo `automaticDetectionRejectsFalsePositiveCornerOnDarkFrame`:
  - Genera un video sintetico **sin marca en la esquina inferior derecha**, solo con la banda superior derecha y los distractores en movimiento.
  - Ejecuta `VideoProcessor().detectWatermark(...)`.
  - Verifica que las regiones devueltas contienen una region superior derecha (`y < 0.20 && x > 0.55`) pero NO contienen ninguna region en la esquina inferior derecha (`y > 0.55 && x > 0.55`).
  - Si ninguna region top-right se detecta (poco probable con el detector actual), tolerar caso `throws` — igualmente cumple el invariante "no fabricar corner".

### C4 — Verificacion contra la muestra real

- Post-implementacion, correr `Scripts/watermark_pipeline.py detect --input "~/Desktop/video luna.MP4"` y verificar que las `regions` del JSON de salida contienen la banda superior derecha pero NO la esquina inferior derecha falsa.

## Plan de tests

- Los 12 tests existentes (post fase 7) deben seguir en verde.
- El test nuevo `automaticDetectionRejectsFalsePositiveCornerOnDarkFrame` debe pasar.
- La suite total debe quedar en 13/13.

## Rollback

Todos los cambios contenidos en 2 archivos (`Scripts/watermark_pipeline.py` y el archivo de tests). `git reset --hard` a la fase 7 revierte sin efectos colaterales.

## Riesgos y mitigaciones

- **Riesgo A**: los umbrales 0.20/0.15 pudieran ser demasiado laxos y dejar pasar falsos positivos parecidos. Mitigacion: aceptable como primera iteracion; una fase futura puede endurecer con datos de mas videos reales.
- **Riesgo B**: los umbrales pudieran ser demasiado estrictos y rechazar una marca real en un caso limite (mark oscuro con pocos bordes). Mitigacion: la regla OR (brillo O bordes) evita rechazar por una sola causa; ademas queda como respaldo el detector top-right + el modo manual.
- **Riesgo C**: iterar los candidates puede degradar rendimiento si la lista es grande. Mitigacion: `component_candidates` ya limita a componentes que pasan un percentil 98.7 mas filtros de tamano, tipicamente <10 candidatos por frame; costo despreciable.

## Aprobacion

Esta estrategia queda sujeta a re-auditoria adversarial antes de implementar.
