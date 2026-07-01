# Re-auditoria de la Estrategia Fase 8

- Fecha: 2026-07-01
- Documento auditado: `ESTRATEGIA_FASE8.md`
- Metodo: lectura adversarial buscando huecos logicos, edge cases y omisiones.

## Hallazgos de re-auditoria

### Amarillo: la regla de decision se aplica sobre `component_mask`, no sobre la region tras el padding

- Problema: la estrategia mide brillo y bordes en el `component_mask` que devuelve `component_candidates`. Pero `detect_corner_watermark` posteriormente **expande** el rectangulo con un padding de 10 px y una llamada a `grow_mask_in_rect` que genera una mascara mas grande y suave. Si el juicio se hace solo sobre el nucleo del componente puede darse el caso de que ese nucleo pase el filtro pero la mascara final expandida cubra area sin evidencia.
- Impacto: bajo. El nucleo del componente es lo mas discriminativo — si el nucleo carece de brillo y bordes, no tiene sentido inflarlo despues. El resto son detalles de acabado.
- Correccion al plan: mantener la decision sobre `component_mask`, no cambia la estrategia. Se documenta esta desicion aqui.

### Amarillo: falta de un piso absoluto de brillo en pixel value

- Problema: `brightness_map` es normalizado por frame; en un video completamente uniforme podria devolver valores altos por el simple hecho de que el componente es "lo mas brillante" aunque en absoluto sea oscuro. El caso extremo: video totalmente negro con un tenue gradiente — el componente ganador podria tener `brightness_map.mean() = 1.0` mientras que su gris crudo real es 5.
- Impacto: bajo — un video que no tiene marca real y solo distractores tenues es poco probable en la muestra de uso; y aunque cayera, el resultado seria inpaintar sobre pixeles que son practicamente indistinguibles del fondo.
- Correccion al plan: no anadir un piso absoluto ahora; documentarlo como riesgo residual y una posible mejora incremental de futuras fases.

### Amarillo: la iteracion sobre candidatos podria alterar el `confidence` reportado

- Problema: hoy el `confidence` sale de `component_score * 0.68 + stability_score * 0.32` usando el top candidate. Si se pasa a un candidato mas abajo por rechazo del primero, el `confidence` reflejara el score de ese candidato (menor). La UI podria mostrar un porcentaje mas bajo del habitual.
- Impacto: aceptable — un candidato secundario **debe** tener menor confianza; es la senal correcta al usuario.
- Correccion al plan: no ajustar la formula; se mantiene la semantica actual.

### Verde: el test negativo esta bien acotado

- El test propuesto (`automaticDetectionRejectsFalsePositiveCornerOnDarkFrame`) captura exactamente el invariante en cuestion: "sin marca en bottom-right → no aparece region en bottom-right". No depende de tolerancias de calidad ni de umbrales frágiles.

### Verde: riesgo de romper la deteccion sintetica existente esta acotado

- Los datos de calibracion muestran que los tres rank-superior del video sintetico tienen `brightness_map.mean() >= 0.55`, muy por encima del umbral 0.20. El test `automaticDetectionFindsBottomRightWatermark` no se rompe.

### Verde: la muestra real fija numericamente la calibracion

- Al usar los valores medidos empiricamente para fijar los umbrales, se elimina la incertidumbre de "que valor uso". El unico riesgo real es que otros videos reales con marcas oscuras raras se acerquen a la frontera; se acepta como riesgo residual documentado.

## Decision

Estrategia **APROBADA sin cambios materiales**:
- La regla de decision opera sobre `component_mask` (nucleo), no sobre la mascara expandida.
- No se anade piso absoluto de gris crudo en esta fase.
- La formula de `confidence` no se toca.
- Se procede a implementar los 4 cambios listados en `ESTRATEGIA_FASE8.md`.
