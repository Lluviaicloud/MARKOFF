# Auditoria Adversarial con Simulacion Real — Inpaint Videos

- Fecha: 2026-07-01
- Muestra de entrada: `~/Desktop/video luna.MP4` (17 MB, 720x1280, HEVC/H.265, 12.000 s de contenedor, 312 frames de video, audio AAC de 10.194 s)
- Codigo bajo prueba: rama `master` post-fase 7 (con los fixes de concurrencia y escritura atomica ya aplicados)
- Alcance: ejecucion end-to-end del pipeline real (`Scripts/watermark_pipeline.py detect`, `... process --mode auto`, mux `ffmpeg` con los mismos argumentos que `PythonVideoEngine.muxProcessedVideo`) y comparacion visual/estadistica de las regiones de marca contra el video original.
- Artefactos generados dentro del proyecto: `audit_phase7_run/python_stage.mp4`, `audit_phase7_run/video_luna_clean_phase7.mp4`, frames `in_*.png`/`out_*.png` a t=0.5s, 3s, 6s, 9s, grids visuales `top-right_banner_grid.png` y `bottom-right_small_grid.png`.

## Resumen ejecutivo

El pipeline **completa** el trabajo end-to-end sobre esta muestra real: detecta dos regiones candidatas, inpainta, remuxa con el audio original y produce un `.mp4` de salida de 12.000 s con video H.264 y audio AAC preservado. No hay crash, no hay perdida de duracion, no hay corrupcion de contenedor. La fase 7 (concurrencia y escritura atomica) tampoco introduce regresion sobre esta muestra.

Pero la simulacion real destapa **defectos de calidad** que la suite de tests sinteticos no captura, porque los tests usan un video de 320x240 en negro con parches trivialmente brillantes.

## Checklist semaforico

| # | Severidad | Area | Hallazgo |
|---|-----------|------|----------|
| S1 | 🔴 Rojo | Deteccion / falso positivo | El detector "bottom-right corner" fija una region en la esquina inferior derecha (x=0.961, y=0.831, w=0.039, h=0.05) donde **no hay marca visible** en el video real, y el inpainting altera esos pixeles innecesariamente |
| S2 | 🟡 Amarillo | Inpainting / eficacia parcial | El banner superior derecho (marca de autor) se limpia solo parcialmente: 63% de reduccion en pixeles muy brillantes a t=0.5s, 82% a t=3s, 100% a t=6s — la eliminacion es dependiente del contenido detras y del contraste local |
| S3 | 🟡 Amarillo | Doble re-encode con degradacion de codec | HEVC (H.265, 11 Mbps) → MPEG-4 Part 2 escrito por OpenCV → H.264 CRF 18 (2.2 Mbps). Dos re-encodes lossy consecutivos, con reduccion de bitrate a ~1/5 |
| S4 | 🟡 Amarillo | VFR / tasa de frames | Input reporta `r_frame_rate=24/1` pero `avg_frame_rate=26/1`. OpenCV toma 26 fps constante y la salida queda a 26 fps CFR. En esta muestra el conteo de frames se preserva (312 in / 312 out), pero en videos con VFR mas pronunciado la duracion visual puede desplazarse |
| S5 | 🟡 Amarillo | Tiempo de proceso sin feedback | El pipeline python tarda ~4 s de reloj sobre 12 s de video (multi-hilo OpenCV a 224% de CPU); el mux `ffmpeg` otro ~1 s. Total 5 s. Aceptable, pero la UI no muestra progreso incremental (solo el spinner) |
| S6 | 🟢 Verde | Duracion contenedor | Salida tiene `format.duration=12.000` s, identica al input, con video 12.000 s y audio 10.216 s (preservados por separado desde el fix de fase 4) |
| S7 | 🟢 Verde | Preservacion de audio | El audio AAC original (10.194 s) se copia sin re-encode (`-c:a copy`), llega intacto al `.mp4` de salida y no fuerza truncar el video |
| S8 | 🟢 Verde | Compatibilidad HEVC | OpenCV en `.venv` puede leer HEVC del sample sin fallos; no hay error de codec ni frames perdidos |
| S9 | 🟢 Verde | Contrato JSON del detector | El script emite JSON bien formado por stdout, con `status=ok`, dos regiones normalizadas y `confidence=0.6073`. El bridge Swift lo parsearia sin problema |
| S10 | 🟢 Verde | Robustez de duracion frente a audio corto | El audio del input dura 1.8 s menos que el video; el fix de fase 4 (retirar `-shortest`) sigue funcionando aqui: contenedor de salida no se recorta |
| S11 | 🟢 Verde | Fase 7 fixes | Ejecucion end-to-end no regresiona por los cambios de escritura atomica, `Task.detached`, ni la guarda de entrada=salida |

---

## Hallazgo critico S1 — Falso positivo del detector "bottom-right corner"

- Region detectada: `x=0.9611, y=0.8312, w=0.0389, h=0.05` (~28x64 px en 720x1280).
- Evidencia numerica: en frames muestreados a t=0.5s, 3s, 6s, 9s el input tiene **0 pixeles brillantes >= 230** dentro de esa region. Es decir, no hay una marca luminosa clara ahi.
- Sin embargo, el pipeline aplica inpainting en esa zona. La diferencia media de gris entre input y output llega a ~21 unidades a t=6s.
- Impacto: la app **modifica pixeles del contenido original** en la esquina inferior derecha aun cuando ahi no hay marca de agua. Segun cual sea el contenido, esto se puede notar como una zona ligeramente suavizada o con textura alterada.
- Causa probable en el codigo:
  - `Scripts/watermark_pipeline.py:98` combina el score con `0.20 * corner_bias`, sesgo fuerte hacia esquinas.
  - `component_candidates` (linea 110) usa un umbral en el percentil 98.7 del score y luego seleccion greedy por corner_bonus. En un video sin marca de agua real en la esquina, cualquier detalle estable en la esquina (una hoja fija, un borde de fondo, un artefacto de compresion) supera el umbral por diseno de la heuristica.
  - `detect_corner_watermark` (linea 189) siempre devuelve el mejor candidato si existe alguno. No hay un piso absoluto de confianza que impida devolver una region cuando en realidad no hay marca.
- Correcciones posibles (no aplicadas):
  - Anadir un umbral absoluto de "cantidad de pixeles brillantes en la region" o de "estabilidad minima" por debajo del cual `detect_corner_watermark` devuelve `None`.
  - Requerir concordancia entre `component_score` y una senal independiente (edge_mean por ejemplo) antes de emitir la region.
  - Exponer la confianza por region (no solo global) para que la UI pueda decidir mostrar o no cada rectangulo.

## Hallazgo S2 — Eficacia parcial del inpainting sobre el banner superior derecho

- Region: `x=0.5556, y=0.1854, w=0.40, h=0.109`.
- Medidas de pixeles brillantes (`R,G,B >= 230`) dentro de la region:
  - t=0.5s: input 864 → output 321 (63% eliminados)
  - t=3s: input 619 → output 112 (82% eliminados)
  - t=6s: input 853 → output 0 (100% eliminados)
  - t=9s: input 0 → output 0 (no habia texto que quitar)
- Interpretacion: la calidad del inpainting varia con el contenido detras del texto. Cuando hay un fondo relativamente uniforme el texto se elimina bien; cuando hay textura compleja detras del texto (t=0.5s), el inpainting deja residuos claramente perceptibles.
- Esto es una limitacion **conocida del algoritmo TELEA** de OpenCV, ya documentada en `README.md` ("El motor de eliminacion usa inpainting clasico de OpenCV, no un modelo generativo entrenado"). No es un bug, es un limite del enfoque actual.
- Sin embargo, la suite de tests solo mide "reduccion de brillo" contra un fondo negro sintetico, por lo que no captura este comportamiento real. El grid visual entregado permite juzgarlo directamente.

## Hallazgo S3 — Doble re-encode con degradacion de codec

- Cadena real observada:
  - Input: HEVC/H.265, 11.06 Mbps, 17 MB para 12 s
  - Etapa Python (`cv2.VideoWriter` con fourcc `mp4v`): **MPEG-4 Part 2**, 3.6 MB
  - Salida final (`ffmpeg -c:v libx264 -crf 18 -preset medium`): H.264, 2.2 Mbps, 3.5 MB
- Cada paso es una re-encodificacion con perdida. La primera (a MPEG-4 Part 2) es innecesariamente vieja para un flujo de 2026; introduce artefactos que la segunda etapa H.264 no puede recuperar.
- Ya reconocido como "no ideal" en `current_state_phase4.md` ("Known Limitations: double-encode path... acceptable for now but not ideal para calidad").
- Correcciones posibles (no aplicadas):
  - Cambiar el `fourcc` de OpenCV a algo mas cercano ("avc1" para H.264 si el backend lo soporta, o usar `ffmpeg` como paso intermedio con codec sin perdida).
  - Escribir los frames como PNG/TIFF sin perdida a disco y dejar que `ffmpeg` haga el unico re-encode a H.264.
  - Directamente publicar el diseno de v2.0 (audio extraido, video procesado independiente) con un intermedio sin perdida.

## Hallazgo S4 — VFR interpretado como CFR

- El input reporta discrepancia `r_frame_rate=24/1` vs `avg_frame_rate=26/1`. Sintoma tipico de video VFR o de contenedor con timestamps no uniformes.
- OpenCV lee `CAP_PROP_FPS` y obtiene 26. El `VideoWriter` fija 26 fps constante. La salida queda con `r_frame_rate=26/1`, `avg_frame_rate=26/1` — CFR forzado.
- En esta muestra el conteo de frames se preserva (312 in / 312 out) y la duracion visual coincide (12.000 s), asi que el efecto es inocuo.
- Riesgo: con videos donde la VFR es mas pronunciada (por ejemplo, grabaciones de iPhone con `avg_frame_rate` bastante distinto de `r_frame_rate`), el mismo pipeline puede desalinear el audio con la nueva pista de video CFR aunque el conteo de frames sea el mismo. Ningun test actual cubre ese escenario.

## Hallazgo S5 — Falta de feedback de progreso

- El pipeline python tarda ~4 s de reloj CPU sobre este video de 12 s; el mux `ffmpeg` ~1 s adicional. En videos mas largos escalara linealmente.
- La UI muestra solo un spinner de texto ("Procesando...") sin porcentaje ni tiempo estimado. Para videos de 60-120 s la percepcion de "colgado" puede volver a aparecer aun con la ejecucion ya movida a `Task.detached` en fase 7.
- No es un defecto de correctitud, pero es un defecto de UX que solo la simulacion real hace evidente.

---

## Lo que confirma como bueno la simulacion (verdes)

- **Duracion y contenedor**: la fase 4 sigue haciendo su trabajo — el audio corto (10.194 s) no recorta el video (12.000 s) en el contenedor final.
- **Preservacion de audio**: `-c:a copy` conserva la pista original AAC sin re-encode, con la duracion original de 10.216 s en el output (ligero ajuste de contenedor esperable).
- **Compatibilidad HEVC**: OpenCV en el `.venv` decodifica H.265 sin problema en esta maquina; no hay dependencia rota.
- **Contrato JSON**: el script emite JSON parseable con region primaria + array `regions` + `confidence`, coherente con lo que espera `PythonResponsePayload` en Swift.
- **Fase 7**: los cambios de concurrencia y escritura atomica no introducen regresion sobre el pipeline real; el archivo final aparece en su destino sin residuos temporales y con el contenido correcto.

## Priorizacion recomendada

1. **S1** (falso positivo de esquina) — es el unico rojo y **modifica contenido del usuario** sin motivo. Requiere endurecer el detector para no devolver regiones si la evidencia de marca es debil.
2. **S3 y S4** — degradacion de codec y VFR — deberian abordarse juntas como parte del rediseno del pipeline de v2.0 (extract audio + procesamiento sin perdida + reincorporacion), no como parches sueltos.
3. **S2** (calidad de inpainting) — solo se resuelve reemplazando el motor por uno generativo; queda como decision estrategica.
4. **S5** (feedback de progreso) — cambio de UX menor: publicar `progress` desde Python via stderr y bindear a un `ProgressView` en Swift.

## Artefactos de evidencia

Todos dentro de `~/Documents/Inpaint_videos/audit_phase7_run/`:

- `python_stage.mp4` — salida cruda del script Python (pre-mux)
- `video_luna_clean_phase7.mp4` — salida final tras mux `ffmpeg`
- `in_0.5.png`, `in_3.png`, `in_6.png`, `in_9.png` — frames del input a distintos tiempos
- `out_0.5.png`, `out_3.png`, `out_6.png`, `out_9.png` — mismos frames del output
- `top-right_banner_grid.png` — grid visual comparativo del banner superior derecho
- `bottom-right_small_grid.png` — grid visual comparativo de la esquina inferior derecha
