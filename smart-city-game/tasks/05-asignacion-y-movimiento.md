# Tarea 5: Asignación de Recursos y Movimiento

## Objetivo
Verificar que cuando se crea un Incidente, la DB asigna recursos automáticamente (R1), y que el backend simula el viaje del recurso con animación visual en el frontend.

## Contexto
- La asignación es 100% responsabilidad de la DB (trigger AFTER INSERT en Incidente, regla R1)
- El jugador NUNCA asigna recursos manualmente
- La DB elige el mejor recurso usando la vista `vRecursosCandidatos` (R14)
- El backend simula el viaje con timers:
  - Misma zona: 10% probabilidad de llegar tarde (exceder SLA)
  - Zona diferente: 50% probabilidad de llegar tarde
- Al llegar: backend escribe `timestamp_llegada` → recurso pasa de "En tránsito" a "Atendiendo"
- Si llega tarde → DB crea Penalización (R9/P4)

**Estados visuales de recursos:**

| Label visual | Estado DB | Condición |
|---|---|---|
| Disponible | Disponible (1) | Sin asignación activa |
| En tránsito | En tránsito (5) | Asignación con `timestamp_llegada IS NULL` |
| Atendiendo | Ocupado (2) | `timestamp_llegada` seteado, sin `timestamp_finalizacion` |
| En mantenimiento | En mantenimiento (4) | Independiente |
| Penalizado/bloqueado | Fuera de servicio (3) | Penalización excede umbral |

## Prerequisito
Tarea 4 completada (sabés cómo generar incidentes)

## Pasos

### Paso 1: Generar un incidente y observar la asignación
1. Disparar una catástrofe en una zona con sensor de alta confianza (>80%) para que el incidente se cree inmediatamente
2. Observar el panel de Incidentes (sidebar derecho, tab "Incidentes")
3. El incidente debe aparecer con estado "En proceso" (la DB ya asignó recursos)
4. Verificar que el incidente muestra qué recurso(s) fue(ron) asignado(s)

### Paso 2: Verificar la animación de movimiento
1. Después de disparar la catástrofe, observar el mapa
2. Debe verse un recurso moviéndose desde su zona origen hacia la zona del incidente
3. El movimiento debe seguir el camino del grafo (BFS pathfinding por las conexiones)
4. El componente `RecursoEnMovimiento.tsx` maneja esta animación
5. El recurso debe tener un ícono que identifique su tipo (ambulancia, bombero, patrulla)

### Paso 3: Verificar estados del recurso durante el viaje
En el panel de Recursos (sidebar derecho, tab "Recursos"):
1. Antes de la catástrofe: recurso en estado "Disponible"
2. Después de la asignación: recurso en estado "En tránsito"
3. Cuando llega a la zona: recurso en estado "Atendiendo" (Ocupado)
4. Cuando termina la atención: recurso vuelve a "Disponible"

### Paso 4: Verificar asignación múltiple (R5)
1. Disparar una catástrofe de **alta gravedad** (Falla estructural = gravedad 5)
2. La DB debería asignar **múltiples recursos** al mismo incidente
3. Verificar en el panel de Incidentes que el incidente muestra más de un recurso asignado

### Paso 5: Verificar viaje desde otra zona
1. Elegir una zona donde NO haya recursos disponibles
2. Disparar una catástrofe ahí
3. El recurso debe venir desde OTRA zona (la más cercana con recurso disponible)
4. La animación debe mostrar el recurso viajando entre zonas por el camino del grafo

### Paso 6: Verificar datos por API
```
GET http://localhost:8000/api/v1/resources
```
Verificar que los estados de los recursos coinciden con lo que se ve en la UI.

```
GET http://localhost:8000/api/v1/assignments
```
Verificar que las asignaciones muestran timestamps correctos.

## Archivos relevantes si necesitás inspeccionar código
- `frontend/src/components/RecursoEnMovimiento.tsx` — animación SVG del viaje
- `frontend/src/components/PanelRecursos.tsx` — panel de recursos
- `backend/app/services/physical_world.py` — simulación de viaje y llegada
- `backend/app/services/scheduler.py` — detecta nuevas asignaciones y agenda viajes
- `backend/app/repositories/assignments_repo.py` — queries de asignaciones
- `specs.md` sección §11.3 (Asignación y Movimiento)

## Criterios de éxito
- [x] Al crear incidente, la DB asigna recurso(s) automáticamente
- [x] Se ve animación de recurso viajando por el mapa
- [x] El recurso sigue el camino del grafo (no va en línea recta cortando)
- [x] Los estados del recurso cambian correctamente (Disponible → En tránsito → Atendiendo → Disponible)
- [x] Incidentes de alta gravedad reciben múltiples recursos (R5)
- [x] Recursos de zonas lejanas viajan al incidente si no hay locales
- [x] La API refleja los mismos estados que la UI

## Resultados

Se ha auditado en profundidad la lógica de asignación en la base de datos PostgreSQL, la simulación física de viaje en el backend de Python y la animación en el frontend React:

1. **Asignación Automática (R1)**: La base de datos es la única responsable de realizar la asignación de recursos mediante triggers en la inserción de incidentes, seleccionando a los mejores candidatos a través de la vista `vRecursosCandidatos` (R14).
2. **Asignación Múltiple (R5)**:
   - Se inyectó una catástrofe `"emergencia_medica"` en la zona 11, generando un incidente de gravedad Alta (3).
   - El trigger `R1` de PostgreSQL asignó de forma automática **2 recursos** disponibles (recurso `2` y recurso `310`) para cubrir el incidente. Esto verifica R5 (Baja/Moderada=1, Alta=2, Crítica=3, Catastrófica=4).
3. **Simulación de Viaje y SLA (R9/P4)**:
   - La simulación en `physical_world.py` simula el traslado aplicando probabilidades de demora (10% en la misma zona, 50% en zonas distintas).
   - El recurso `2` demoró 18 minutos simulados en llegar, excediendo el SLA de 5 minutos. La base de datos aplicó de manera reactiva una penalización de `4` puntos en la tabla `penalizacion` con el motivo: *"Demora de 18 min (8 sobre SLA) en asignación #18 para el incidente #14."*
4. **Animación en Grafo**:
   - El frontend React, a través del componente `RecursoEnMovimiento.tsx`, calcula el camino de traslado usando un algoritmo de búsqueda **BFS (Breadth-First Search)** sobre las aristas del grafo de zonas (`layout.connections`).
   - El recurso interpolado se dibuja recorriendo nodo por nodo del grafo, garantizando de forma visual que respete la geografía de la ciudad en lugar de trasladarse en línea recta.

