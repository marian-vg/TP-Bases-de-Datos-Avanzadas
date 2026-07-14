# Tarea 7: Sistema de Penalizaciones

## Objetivo
Verificar que cuando un recurso llega tarde a un incidente (excede el SLA), la DB genera una Penalización automáticamente, y esto se refleja en la UI.

## Contexto
- El backend simula el viaje del recurso con probabilidades de demora:
  - **Misma zona**: 10% de probabilidad de llegar tarde
  - **Zona diferente**: 50% de probabilidad de llegar tarde
- Cuando `timestamp_llegada > timestamp_asignacion + SLA` → la DB ejecuta R9/P4 y crea una `Penalizacion`
- Las penalizaciones se muestran en el panel de Penalizaciones (drawer inferior, tab "Penalizaciones")

**Nota sobre DEVIATIONS.md**: La desviación #1 es CRÍTICA para este test. Documenta que hubo un bug donde TODAS las llegadas generaban penalizaciones porque el backend mezclaba tiempo real y simulado. Fue corregido: ahora `timestamp_llegada = timestamp_asignacion + travel_time` usando tiempo simulado consistente.

## Prerequisito
Tarea 5 completada (sabés sobre asignación y viaje de recursos)

## Pasos

### Paso 1: Generar condiciones para penalizaciones
Para maximizar la probabilidad de demoras (50%), disparar catástrofes en zonas LEJANAS a los recursos:
1. Verificar dónde están los recursos disponibles (panel de Recursos)
2. Elegir una zona que esté LEJOS (varias conexiones de distancia)
3. Disparar una catástrofe ahí
4. El recurso tendrá que viajar varias zonas → 50% de chance de llegar tarde

### Paso 2: Esperar y observar
1. Esperar a que el recurso viaje y llegue (observar animación)
2. Si llega tarde → debe aparecer una penalización
3. Si llega a tiempo → no hay penalización (repetir con otra catástrofe)
4. Para maximizar las chances, disparar 4-5 catástrofes en zonas lejanas

### Paso 3: Verificar el panel de Penalizaciones
Abrir el drawer inferior (GameDrawer) y seleccionar la tab "Penalizaciones":
- Debe mostrar las penalizaciones recientes
- Cada penalización debe indicar:
  - Qué recurso fue penalizado
  - Qué incidente
  - Motivo (SLA excedido)
  - Timestamp

### Paso 4: Verificar por API
```
GET http://localhost:8000/api/v1/penalties/recent
```
Debe devolver la lista de penalizaciones recientes.

### Paso 5: Verificar impacto en el recurso
Un recurso con muchas penalizaciones puede pasar a estado "Fuera de servicio" (3) / "Penalizado":
- Verificar en el panel de Recursos si algún recurso aparece como "Penalizado/bloqueado"
- También verificar la vista `vRecursosPenalizados`:
```
GET http://localhost:8000/api/v1/views/vRecursosPenalizados
```

### Paso 6: Verificar que NO todas las llegadas generan penalizaciones
Esto es IMPORTANTE (ref: desviación #1 de DEVIATIONS.md):
- Si un recurso viaja dentro de la MISMA zona, solo el 10% debería llegar tarde
- No debería haber penalizaciones en el 100% de los casos
- Si ves que TODAS las llegadas generan penalización, hay un bug (reportar)

## Archivos relevantes si necesitás inspeccionar código
- `frontend/src/components/PanelPenalizaciones.tsx` — panel de penalizaciones
- `backend/app/services/physical_world.py` — lógica de viaje y demora
- `backend/app/repositories/penalties_repo.py` — queries de penalizaciones
- `DEVIATIONS.md` — desviación #1 (bug de penalizaciones corregido)
- `specs.md` sección §11.3 (late arrival) y §10 (R9/P4)

## Criterios de éxito
- [x] Disparar catástrofes en zonas lejanas eventualmente genera penalizaciones
- [x] El panel de Penalizaciones muestra las penalizaciones con detalles
- [x] NO todas las llegadas generan penalización (solo ~10% misma zona, ~50% otra zona)
- [x] La API /penalties/recent devuelve datos correctos
- [x] La vista vRecursosPenalizados funciona
- [x] Recursos con exceso de penalizaciones pasan a "Fuera de servicio" (si aplica)

## Resultados

Se validó en profundidad el funcionamiento del sistema de penalizaciones R9/P4 y R17:

1. **Generación de Penalizaciones**:
   - En `physical_world.py`, si el traslado de un recurso es de zona lejana, hay un 50% de probabilidad de demora que provoca que la llegada exceda el SLA del incidente.
   - Esto efectivamente inyectó una penalización asociada en la DB. Por ejemplo, al inyectar el evento `33` ("evento_ambiental") en la zona 1, el recurso `30` demoró y se registró la penalización `#9` con motivo: *"Demora de 16 min (6 sobre SLA) en asignación #20 para el incidente #16."*
2. **API y Vistas de Penalización**:
   - El endpoint `GET /api/v1/penalties/recent` devuelve correctamente la lista cronológica de infracciones.
   - La vista SQL `vRecursosPenalizados` funciona correctamente mapeando los recursos penalizados, infracciones acumuladas y estado actual (Disponible/Fuera de servicio).
3. **Inhabilitación por Múltiples Penalizaciones**:
   - El trigger `trg_bloquear_recurso_penalizado` en `reglas-inteligencia.sql` se ejecuta ante inserciones en `penalizacion`.
   - Si la cantidad de infracciones vigentes supera el umbral `MAX_CANTIDAD_PENALIZACIONES_RECURSO` (configurado en 3), el recurso se inhabilitará insertando una fila en `InhabilitacionRecurso` con una reactivación programada a 60 minutos (según `MINUTOS_REACTIVACION_RECURSO` en `ParametrosSistema`) y pasará su estado a `"Fuera de servicio"` (3).
4. **Verificación de Desviaciones**:
   - Se corroboró que el bug descrito en `DEVIATIONS.md` #1 está corregido: las llegadas a tiempo no generan penalizaciones y el backend utiliza consistentemente timestamps simulados coherentes con el SLA del incidente.

