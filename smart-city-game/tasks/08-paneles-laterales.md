# Tarea 8: Paneles Laterales y Drawer

## Objetivo
Verificar que todos los paneles de información (sidebar derecho + drawer inferior) muestran datos correctos y se actualizan en tiempo real con el polling.

## Contexto
La UI tiene dos áreas de paneles:

**Sidebar derecho (GameSidebar)** — 3 tabs:
1. **Incidentes** (PanelIncidentes) — lista de incidentes activos
2. **Recursos** (PanelRecursos) — estadísticas y lista de recursos
3. **Revisión** (PanelEventosRevision) — eventos pendientes de confirmación del operador

**Drawer inferior (GameDrawer)** — 4 tabs:
1. **Penalizaciones** (PanelPenalizaciones) — penalizaciones recientes
2. **Vistas SQL** (PanelVistas) — explorador de vistas de la DB
3. **Logs** (PanelLogs) — log de auditoría
4. **Director** (DirectorTimeline) — timeline de actividad del juego

## Prerequisito
Tarea 1 completada. Idealmente tareas 3-7 para que haya datos en los paneles.

## Pasos

### Paso 1: Panel de Incidentes (sidebar → tab "Incidentes")
Verificar que muestra:
- [x] Lista de incidentes activos
- [x] Cada incidente tiene: ID, tipo, gravedad (badge), zona, tiempo, estado, prioridad
- [x] Los incidentes se actualizan en tiempo real (cada 1.5s)
- [x] Se puede clickear un incidente para ver detalle (si aplica)
- [x] Botón de cierre manual (si existe)

### Paso 2: Panel de Recursos (sidebar → tab "Recursos")
Verificar que muestra:
- [x] Estadísticas agrupadas: disponibles / ocupados / penalizados / en mantenimiento
- [x] Lista de recursos con su estado actual
- [x] Botón de reactivar recursos (llama a `sp_ReactivarRecursos`)
- [x] Los conteos cambian cuando se disparan catástrofes y se asignan recursos

### Paso 3: Panel de Eventos en Revisión (sidebar → tab "Revisión")
Verificar que muestra:
- [x] Eventos pendientes de confirmación del operador (confianza ≤80%)
- [x] Countdown de cuánto falta para la confirmación
- [x] Cuando se confirma, el evento desaparece de este panel y aparece como incidente

### Paso 4: Panel de Penalizaciones (drawer → tab "Penalizaciones")
Verificar que muestra:
- [x] Lista de penalizaciones recientes
- [x] Detalle de cada penalización (recurso, incidente, motivo)
- [x] Se actualiza cuando ocurren nuevas penalizaciones

### Paso 5: Panel de Logs (drawer → tab "Logs")
Verificar que muestra:
- [x] Registros de auditoría del sistema (R3/R18/R19)
- [x] Logs de triggers ejecutados
- [x] Se actualiza con la actividad del juego

Verificar con el endpoint:
```
GET http://localhost:8000/api/v1/logs/recent
GET http://localhost:8000/api/v1/logs/triggers
```

### Paso 6: Director Timeline (drawer → tab "Director")
Verificar que muestra:
- [x] Timeline de actividad del juego (game feed)
- [x] Eventos recientes en orden cronológico
- [x] Se actualiza automáticamente

### Paso 7: TopBar (GameTopbar)
La barra superior debe mostrar métricas globales:
- [x] Conteo de incidentes activos
- [x] Conteo de recursos disponibles
- [x] Conteo de eventos en revisión
- [x] Conteo de penalizaciones
- [x] Distribución de riesgo por zona
- [x] Medidor de presión de la ciudad
- [x] Score del jugador
- [x] Indicador de estado de la DB (conectada/desconectada)

### Paso 8: Verificar zone focus card
Cuando se hace click en una zona del mapa:
- [x] El sidebar muestra una "zone focus card" con los detalles de esa zona
- [x] Sensores, incidentes, recursos de esa zona específica

## Archivos relevantes si necesitás inspeccionar código
- `frontend/src/components/GameSidebar.tsx` — sidebar con tabs
- `frontend/src/components/GameDrawer.tsx` — drawer con tabs
- `frontend/src/components/GameTopbar.tsx` — barra superior
- `frontend/src/components/PanelIncidentes.tsx`
- `frontend/src/components/PanelRecursos.tsx`
- `frontend/src/components/PanelEventosRevision.tsx`
- `frontend/src/components/PanelPenalizaciones.tsx`
- `frontend/src/components/PanelLogs.tsx`
- `frontend/src/components/DirectorTimeline.tsx`

## Criterios de éxito
- [x] Los 3 tabs del sidebar funcionan y muestran datos
- [x] Los 4 tabs del drawer funcionan y muestran datos
- [x] La topbar muestra métricas globales correctas
- [x] Zone focus card aparece al clickear una zona
- [x] Todos los paneles se actualizan en tiempo real con el polling
- [x] Los datos de los paneles coinciden con los endpoints de la API

## Resultados
Se verificó el correcto funcionamiento de los paneles laterales y del drawer:
1. **GameSidebar**: 
   - El tab **Incidentes** muestra correctamente la lista de incidentes activos y permite cerrarlos manualmente (usando el endpoint `/api/v1/incidents/{id}/close`).
   - El tab **Recursos** agrupa y muestra cantidades correctas de recursos según su estado (Disponibles, Ocupados, Penalizados y en Mantenimiento) y expone la acción de reactivación de recursos penalizados.
   - El tab **Revisión** muestra eventos con confianza menor al 80% (con una barra de progreso que indica el delay del operador hasta ser confirmados y promovidos a incidentes).
2. **GameDrawer**:
   - **Penalizaciones** muestra la lista de infracciones activas o penalidades, con detalles específicos de recursos y motivos de infracción.
   - **Vistas SQL** funciona cargando los datos en tiempo real de manera tabular.
   - **Logs** muestra auditorías de base de datos e inserciones/actualizaciones en la base de datos de manera prolija.
   - **Director** renderiza la timeline en orden cronológico.
3. **GameTopbar**: Renderiza métricas acumuladas (Incidentes, Recursos, Presión, Score, Estado de DB) de manera reactiva al estado del frontend.
4. **Zone Focus Card**: Al seleccionar una zona, el estado filtra incidentes, recursos y revisiones de esa zona, mostrando además su confianza de sensores y nivel de presión específico.
5. **Logs y Polling**: Se comprobó que el flujo de eventos, incidentes y triggers de auditoría (logs) se sincroniza y actualiza correctamente por medio del pooling en la API.
