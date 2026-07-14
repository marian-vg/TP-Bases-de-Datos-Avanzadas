# Tarea 9: Vistas SQL

## Objetivo
Verificar que las 10 vistas SQL del TP están correctamente expuestas y accesibles desde el panel de Vistas del juego.

## Contexto
- El TP requiere al menos 5 vistas SQL (la implementación expone 10)
- Se acceden via `GET /api/v1/views/{nombre}` con una allowlist en el backend
- El panel PanelVistas tiene un dropdown para seleccionar la vista y renderiza los resultados como tabla HTML
- Las vistas son de SOLO LECTURA — muestran datos de la DB sin modificarla

## Prerequisito
Tarea 1 completada. Idealmente haber generado algo de actividad (catástrofes, incidentes) para que las vistas tengan datos.

## Las 10 vistas

| Vista | Qué muestra |
|-------|------------|
| `vIncidentesActivos` | Incidentes que no están resueltos |
| `vRecursosDisponibles` | Recursos en estado Disponible |
| `vRecursosOcupados` | Recursos actualmente ocupados |
| `vIncidentesCriticos` | Incidentes de alta gravedad o escalados |
| `vHistorialIncidentes` | Historial completo de incidentes |
| `vRecursosPenalizados` | Recursos con penalizaciones |
| `vRecursosCandidatos` | Recursos candidatos para asignación (R14) |
| `vHistorialAsignaciones` | Historial de todas las asignaciones |
| `vHistorialTriggers` | Log de triggers ejecutados |
| `vZonasIncidentadas` | Zonas con incidentes activos |

## Pasos

### Paso 1: Abrir el panel de Vistas
- [x] Abrir el drawer inferior (GameDrawer) y seleccionar la tab "Vistas SQL".
Debe verse un dropdown/selector con las vistas disponibles.

### Paso 2: Probar cada vista
Para CADA una de las 10 vistas:
- [x] Seleccionarla del dropdown
- [x] Verificar que se carga una tabla con datos (o vacía si no hay datos relevantes)
- [x] Verificar que las columnas tienen sentido para esa vista
- [x] Verificar que no hay errores de carga

### Paso 3: Verificar por API
Para cada vista, verificar que el endpoint devuelve datos:
- [x] vIncidentesActivos (HTTP 200)
- [x] vRecursosDisponibles (HTTP 200)
- [x] vRecursosOcupados (HTTP 200)
- [x] vIncidentesCriticos (HTTP 200)
- [x] vHistorialIncidentes (HTTP 200)
- [x] vRecursosPenalizados (HTTP 200)
- [x] vRecursosCandidatos (HTTP 200)
- [x] vHistorialAsignaciones (HTTP 200)
- [x] vHistorialTriggers (HTTP 200)
- [x] vZonasIncidentadas (HTTP 200)

### Paso 4: Verificar la allowlist
Probar un nombre de vista INVÁLIDO:
- [x] curl http://localhost:8000/api/v1/views/tabla_que_no_existe devuelve HTTP 404 (Vista no permitida: tabla_que_no_existe).

### Paso 5: Verificar que las vistas reflejan el estado actual
- [x] Disparar una catástrofe
- [x] Consultar `vIncidentesActivos` → incluye el nuevo incidente
- [x] Consultar `vRecursosDisponibles` → tiene un recurso menos (el que fue asignado)
- [x] Esperar a que se resuelva
- [x] Consultar `vHistorialIncidentes` → incluye el incidente resuelto

## Archivos relevantes si necesitás inspeccionar código
- `frontend/src/components/PanelVistas.tsx` — panel de vistas en el frontend
- `backend/app/routers/views.py` — endpoint genérico de vistas
- `backend/app/repositories/views_repo.py` — query genérico con allowlist
- `backend/app/config.py` — lista de vistas permitidas (allowlist)

## Criterios de éxito
- [x] Panel de Vistas muestra dropdown con las 10 vistas
- [x] Cada vista carga y muestra datos en formato tabla
- [x] Las vistas requeridas por el TP (mínimo 5) están todas presentes
- [x] El endpoint rechaza nombres de vista no permitidos (seguridad)
- [x] Los datos de las vistas reflejan el estado actual de la DB
- [x] No hay errores 500 al consultar ninguna vista

## Resultados
Se completaron las verificaciones para las 10 vistas SQL de la base de datos:
1. **Acceso y Renderizado**: El panel `PanelVistas` renderiza correctamente un selector con las 10 vistas y las dibuja en una tabla HTML dinámica.
2. **Endpoints de la API**: Se comprobó que el endpoint `/api/v1/views/{nombre}` responde con `HTTP 200` y con un array JSON para las 10 vistas:
   - `vIncidentesActivos`, `vRecursosDisponibles`, `vRecursosOcupados`, `vIncidentesCriticos`, `vHistorialIncidentes`, `vRecursosPenalizados`, `vRecursosCandidatos`, `vHistorialAsignaciones`, `vHistorialTriggers`, `vZonasIncidentadas`.
3. **Allowlist de Seguridad**: Al consultar una vista inválida (`tabla_que_no_existe`), el backend responde correctamente con `HTTP 404` (`VIEW_NOT_ALLOWED`), evitando la ejecución de la consulta a la base de datos y previniendo inyecciones de código SQL.
4. **Reactividad**: Se inyectó un `incendio` en la zona 1 (Centro) lo cual generó un evento que fue promovido por el operador a un incidente activo. Se constató que las vistas `vIncidentesActivos`, `vRecursosOcupados` y `vRecursosDisponibles` reflejaron el cambio de estado en tiempo real. Al resolverse el incidente, `vIncidentesActivos` y `vRecursosOcupados` volvieron a quedar vacías, mientras que `vHistorialIncidentes` y `vHistorialAsignaciones` registraron la finalización exitosa.
