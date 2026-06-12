# Cumplimiento de `top_secret/specs.md`

Este archivo deja trazabilidad directa entre el plan secreto y la implementacion ubicada en
`pulse-city-game/`. La capa del juego es complementaria al TP: no reemplaza la BD, no cambia su
esquema y no agrega tablas, triggers ni procedures.

## Decisiones duras respetadas

| Punto de `/top_secret/specs.md` | Estado | Evidencia |
|---|---|---|
| Juego separado, por encima del TP | Cumplido | Todo vive dentro de `pulse-city-game/`, carpeta aislada del repo original. |
| No modificar esquema de la BD | Cumplido | No hay DDL en `pulse-city-game/`; solo lectura, `INSERT Evento`, `INSERT Incidente` del operador y timestamps de `Asignacion`. |
| BD como fuente de verdad | Cumplido | Las reglas de negocio se observan leyendo la BD y sus vistas; el backend no decide asignaciones ni penalizaciones. |
| Backend delgado FastAPI | Cumplido | Routers, repositories y services separados; sin ORM ni modelo paralelo de dominio. |
| React + Vite, mapa 2D simple | Cumplido | Frontend SPA con grafo SVG y polling. No usa Unity, Phaser ni motor externo. |
| Polling 1-2 s | Cumplido | `frontend/src/api/client.ts` consulta el snapshot de estado periodicamente. |
| Hotbar con catastrofes, gravedad y cooldown | Cumplido | Catalogo en `backend/app/services/mapping.py`; UI en `Hotbar.tsx`. |
| Catastrofe -> Evento -> sensor capaz -> Incidente | Cumplido | `POST /catastrofes` busca sensor compatible, inserta `Evento` y lee de vuelta si la BD creo incidente. |
| Sensor sin cobertura | Cumplido | Respuesta `coverage: "none"` sin inventar incidente. |
| Confianza R21 y operador 15-60 s | Cumplido | Si no hay incidente inmediato, `operator.py` agenda revision automatica. |
| Movimiento visual de recursos | Cumplido | `RecursoEnMovimiento.tsx` dibuja viajes activos desde el snapshot. |
| Scheduler para SLA/reactivacion | Cumplido | `scheduler.py` llama procedures temporales (`sp_EscalarIncidente`, `sp_ReactivarRecursos`). |
| Modo auto via `sp_SimularEventos` | Cumplido | `events_repo.call_simular_eventos_sync()` llama `CALL sp_SimularEventos(...)`. |
| Vistas TP con lista blanca | Cumplido | `views_repo.py` valida la vista antes de consultar. |
| Rutas tentativas del plan | Cumplido | Existen las rutas literales `/estado`, `/zonas`, `/sensores`, `/catastrofes`, `/incidentes/activos`, `/recursos`, `/penalizaciones/recientes`, `/eventos/recientes`, `/eventos/en-revision`, `/vistas/{nombre}`, `/simulacion/auto`, `/simulacion/tick`, `/simulacion/pausa`. Tambien se conserva `/api/v1/...`. |
| Sin auth, ranking, multiusuario o persistencia de partidas | Cumplido | No se implementaron esos no-objetivos. |

## Pruebas ejecutadas

```powershell
python -m compileall -f pulse-city-game\backend\app
npm run build
docker compose build
docker compose up -d
```

Endpoints verificados con HTTP 200:

```text
GET  /api/v1/health
GET  /api/v1/health/db
GET  /estado
GET  /zonas
GET  /sensores
GET  /catastrofes
POST /catastrofes
GET  /incidentes/activos
GET  /recursos
GET  /penalizaciones/recientes
GET  /eventos/recientes
GET  /eventos/en-revision
GET  /vistas/vIncidentesActivos
POST /simulacion/auto
POST /simulacion/tick
POST /simulacion/pausa
GET  http://localhost:5173
```

Estado final observado:

```text
frontend: 200
backend: 200
db health: 200
scheduler.auto: false
clock.paused: false
scheduler.lastErrors: 0
```

## Limites intencionales

- Las consultas a vistas usan `SELECT *` cuando el objetivo es mostrar la vista completa del TP.
  Esto es deliberado y esta acotado por lista blanca.
- El compose del juego no crea otra base: se conecta a la base del TP ya levantada. Esto evita
  duplicar datos o esconder fallas detras de una BD paralela.
- `resources/` queda disponible para assets; v1 prioriza el grafo funcional y desacoplado, tal
  como recomienda el propio plan.
