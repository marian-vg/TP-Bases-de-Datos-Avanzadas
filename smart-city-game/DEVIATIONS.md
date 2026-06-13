# Desviaciones respecto de `top_secret/specs.md`

Análisis independiente de la implementación del juego (`smart-city-game/`) contra el plan
`top_secret/specs.md`. La BD del TP se toma como contrato fijo y correcto: nada de esto la toca.

## Resumen

La implementación respeta lo estructural y la restricción dura clave: **no modifica el esquema
de la BD** (sin DDL; solo `INSERT Evento`, `INSERT Incidente` del operador y `UPDATE` de
timestamps de `Asignacion`). Arquitectura, polling, routers/repositories/services y rutas del
§13 (vía `legacy.py`) coinciden con el plan.

Se detectaron y corrigieron las siguientes desviaciones.

## 🔴 1. Desajuste de relojes — penalizaciones (R9/P4) rotas  → CORREGIDO

- `timestamp_asignacion` lo escribe la BD con `CURRENT_TIMESTAMP` (tiempo **real**).
- El backend escribía `timestamp_llegada` con `sim_now()` (tiempo **simulado**, ×20, que arranca
  igual al real pero corre adelante).
- `sp_CalcularPenalizacion` penaliza según `(llegada − asignacion)` contra un SLA de 5–10 min.

Resultado previo: la diferencia ≈ `19 × (tiempo real transcurrido) + viaje`, así que toda
llegada excedía el SLA por márgenes crecientes → penalizaciones espurias e ilimitadas, y la
mecánica de "llegó tarde" (10% misma zona / 50% otra) quedaba decorativa.

**Fix** (`physical_world.py`): se separa el *disparo* (en reloj simulado, respeta pausa y escala)
del *valor escrito*. `timestamp_llegada = timestamp_asignacion + viaje`, con el viaje expresado
en minutos simulados relativos al SLA del incidente (en hora vs. tarde). Así `(llegada −
asignacion)` refleja el viaje real y el SLA penaliza de forma coherente. Se agregó el SLA del
incidente a la consulta de asignaciones abiertas (`assignments_repo`).

## 🟠 2. Doble fuente de verdad para gravedad / mapeo evento→incidente  → CORREGIDO

- Camino >80% (inmediato): el trigger `fn_evento_promocion` toma tipo_incidente y gravedad de
  `TipoEventoTipoIncidente` (BD).
- Camino ≤80% (operador): tomaba tipo_incidente/gravedad del **config del backend**.

El mismo `TipoEvento` podía generar gravedades distintas según la confianza del sensor.

**Fix** (`operator.py` + `events_repo.get_promocion_mapeo_sync`): el operador deriva
tipo_incidente/gravedad de `TipoEventoTipoIncidente` (misma fuente que el trigger) y replica su
regla de "exactamente un mapeo". El estado inicial se resuelve por nombre (`'Pendiente'`) en vez
de un id hardcodeado.

## 🟠 3. Modo auto duplicaba el umbral de confianza (roza RT1)  → CORREGIDO

El camino automático decidía en el backend `confianza <= 80` para encolar el operador, en vez de
leer de vuelta de la BD (como sí hace el camino manual).

**Fix** (`scheduler.py`): tras `sp_SimularEventos`, se lee de vuelta si la BD promovió el evento
(`find_incidente_by_evento_sync`); si no, lo toma el operador simulado. Sin umbral duplicado.

## 🟡 4. Menores  → corregidos / anotados

- Delay del operador era determinista (`hash(...)`) e ignoraba `OPERATOR_REVIEW_MIN/MAX_DELAY`.
  **Fix**: `random.randint` real usando esas constantes de config.
- `assignments_repo.set_failure_sync` es código muerto (nunca se llama). Anotado.
- Modo auto asume zonas con id `1..12` (`random.randint(1,12)`). Anotado.
- Nomenclatura: el juego se llamaba "Pulse City", inconsistente con el TP/BD `smart_city`.
  **Fix**: renombrado a "Smart City" / carpeta `smart-city-game/` y scripts `start-smart-city.*`
  (sin tocar las animaciones CSS `pulse-glow`/`animate-pulse`, que son funcionales). Las rutas
  literales en español del §13 siguen expuestas vía `legacy.py`.

## Pendiente de verificación

Los arreglos se validaron por compilación y por lógica de dominio. Falta una corrida end-to-end
con la BD del TP levantada (`docker compose up`) para confirmar que las penalizaciones aparecen
con la cadencia esperada (≈10%/50% de llegadas tarde).
