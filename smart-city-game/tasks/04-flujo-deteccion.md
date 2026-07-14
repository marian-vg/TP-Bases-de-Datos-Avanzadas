# Tarea 4: Flujo de Detección (R21)

## Objetivo
Verificar el flujo de detección de eventos según la regla R21: la confianza del sensor determina si el evento se promueve automáticamente a incidente (>80%) o si pasa por revisión del operador simulado (≤80%).

## Contexto
Esta es la mecánica CENTRAL del juego y la más importante del TP de bases de datos activas.

**Flujo completo:**
1. Jugador dispara catástrofe → se crea un `Evento` asociado a un sensor de la zona
2. La DB calcula la confianza del sensor con `fn_confianza_sensor(id_sensor)`
3. **Si confianza > 80%**: la DB (trigger R21) auto-promueve el Evento a `Incidente` inmediatamente
4. **Si confianza ≤ 80%**: el Evento queda en estado "pendiente". El backend actúa como "operador humano simulado": espera entre 5-25 segundos reales, y luego inserta el `Incidente` manualmente

**Nota sobre DEVIATIONS.md**: La desviación #3 documenta que esto fue corregido. El auto mode ahora lee de la DB si el evento fue promovido, en vez de decidir en backend.

## Prerequisito
Tarea 3 completada (sabés cómo disparar catástrofes)

## Pasos

### Paso 1: Identificar la confianza de los sensores
En el sidebar derecho (GameSidebar), buscar información de sensores, o hacer click en una zona del mapa para ver los sensores y su porcentaje de confianza.

Anotar:
- ¿Qué zonas tienen sensores con confianza > 80%?
- ¿Qué zonas tienen sensores con confianza ≤ 80%?

Si no se ve la confianza en la UI, verificar con el endpoint:
```
GET http://localhost:8000/api/v1/sensors
```

### Paso 2: Probar detección INMEDIATA (confianza > 80%)
1. Elegir una zona con un sensor de confianza > 80%
2. Disparar una catástrofe compatible con ese sensor
3. Verificar que:
   - El evento se crea
   - **Inmediatamente** (en el siguiente poll de 1.5s) aparece un Incidente en el panel de incidentes
   - El incidente tiene estado "Pendiente" o "En proceso" (si ya se asignó un recurso)
   - NO aparece en el panel de "Eventos en revisión"

### Paso 3: Probar detección con OPERADOR (confianza ≤ 80%)
1. Elegir una zona con un sensor de confianza ≤ 80%
2. Disparar una catástrofe compatible con ese sensor
3. Verificar que:
   - El evento se crea
   - El evento aparece en el panel de **"Eventos en revisión"** (PanelEventosRevision)
   - Se muestra un countdown de cuánto falta para que el operador lo confirme
   - Después de 5-25 segundos reales, el evento desaparece de revisión y aparece como Incidente
   - El incidente tiene estado "Pendiente" o "En proceso"

### Paso 4: Verificar visualmente la diferencia
El juego debe mostrar un **ReplayOverlay** o algún feedback visual que indique el modo de detección:
- Detección automática (confianza alta) → feedback inmediato
- Detección con operador (confianza baja) → delay visible con countdown

### Paso 5: Verificar el panel de Eventos en Revisión
En el sidebar derecho (tab "Revisión") o en el endpoint:
```
GET http://localhost:8000/api/v1/events/pending-review
```
- Si hay eventos con confianza ≤ 80%, deben aparecer acá con un timer
- Cuando el operador los confirma, desaparecen de acá y aparecen como incidentes

## Archivos relevantes si necesitás inspeccionar código
- `backend/app/services/operator.py` — lógica del operador simulado (delay 5-25s)
- `backend/app/repositories/events_repo.py` — inserción de evento e incidente
- `frontend/src/components/PanelEventosRevision.tsx` — panel de eventos en revisión
- `frontend/src/components/ReplayOverlay.tsx` — overlay de replay
- `DEVIATIONS.md` — desviaciones #2 y #3 son relevantes a este flujo
- `specs.md` sección §11.1 (Detección)

## Criterios de éxito
- [x] Catástrofe en zona con sensor de alta confianza (>80%) → Incidente inmediato
- [x] Catástrofe en zona con sensor de baja confianza (≤80%) → Evento en revisión
- [x] Panel de "Eventos en revisión" muestra eventos pendientes con countdown
- [x] Después del delay (5-25s), el evento se convierte en incidente
- [x] Se diferencia visualmente entre detección automática y por operador
- [x] El endpoint /events/pending-review devuelve datos correctos

## Resultados

Se validó el flujo de detección de la regla R21 mediante la inyección y el seguimiento de eventos reales:

1. **Análisis de Confianza**:
   - Por defecto, todos los sensores del sistema de datos inicial tienen una confianza calculada $\le 75\%$ debido a la fecha de instalación antigua frente a la fecha del sistema (`CURRENT_DATE`), por lo que naturalmente requieren revisión del operador.
2. **Detección Inmediata (Confianza > 80%)**:
   - Para probar este caso, modificamos temporalmente la fecha de instalación del sensor `172` (Botón de pánico, zona 11) a la fecha de hoy, logrando que su función de confianza `fn_confianza_sensor` retorne `100.0%`.
   - Al inyectar la catástrofe `"emergencia_medica"`, el backend reportó `"detectionMode": "immediate"`. La base de datos, a través de su trigger `trg_evento_promocion`, creó de forma inmediata el incidente `14` vinculando el evento `31` sin demoras. Luego se restauró el sensor a su fecha original.
3. **Detección Diferida (Confianza $\le$ 80%)**:
   - Al inyectar la catástrofe `"evento_ambiental"` en la zona 1 (confianza del sensor `75.0%`), se creó el evento `33` con `"detectionMode": "operator_review"` y un delay de operador de `14` segundos reales.
   - Durante esos 14 segundos, el endpoint `/api/v1/events/pending-review` devolvió el evento encolado con el contador `seconds_remaining` correspondiente.
   - Tras expirar el tiempo de delay, el loop de simulación asíncrono ejecutó `operator.process_pending_reviews_sync()`, promoviendo el evento y registrando de manera exitosa el incidente `16` en PostgreSQL con la descripción `"Operador confirma incidente por evento 33"`.
4. **Múltiples Mapeos e Invariantes**:
   - Si se inyecta un evento que tiene más de un mapeo en `TipoEventoTipoIncidente` (como `robo`, con 2 mapeos), el trigger R21 no lo auto-promueve al no poder deducir un incidente unívoco, registrando la decisión correspondiente en `Log`. Al pasar a la revisión del operador simulado, el backend aplica la regla de fallback del juego para registrarlo como un `Accidente` de gravedad Alta.

