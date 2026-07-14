# Tarea 6: Ciclo de Vida de Incidentes

## Objetivo
Verificar el ciclo de vida completo de un incidente: creación → asignación → atención → resolución, incluyendo escalamiento por SLA.

## Contexto
**Estados de un incidente (en la DB):**
- **Pendiente**: recién creado, esperando asignación
- **En proceso**: al menos un recurso asignado (R2)
- **Resuelto**: todos los recursos terminaron su atención (R7, cierre automático)
- **Escalado**: el SLA fue excedido sin resolución (R16, escalamiento temporal)

**Reglas clave:**
- R2/R8: Cuando se crea una asignación → incidente pasa a "En proceso"
- R7: Cuando TODOS los recursos asignados terminan (`timestamp_finalizacion` seteado) → incidente pasa a "Resuelto" automáticamente
- R16: Si el incidente no se resuelve dentro del SLA → `sp_EscalarIncidente()` lo marca como "Escalado"
- R20: Si hay demasiados incidentes simultáneos → nuevos quedan en "En espera" (control de capacidad)

**Tiempos simulados:**
- `ESCALA_TIEMPO = 20` (1 segundo real = 20 segundos simulados)
- SLA de 10 minutos = ~30 segundos reales de gameplay

## Prerequisito
Tarea 5 completada (sabés cómo generar incidentes con asignación)

## Pasos

### Paso 1: Observar el ciclo completo de un incidente
1. Disparar UNA catástrofe en una zona con sensor de alta confianza
2. Observar el panel de Incidentes (sidebar derecho)
3. Anotar el estado del incidente a medida que avanza:
   - ¿Aparece primero como "Pendiente"?
   - ¿Cambia a "En proceso" cuando se asigna un recurso?
   - ¿Cuánto tiempo tarda en resolverse?
   - ¿Cambia a "Resuelto" automáticamente?

### Paso 2: Verificar información del incidente
En el panel de Incidentes, cada incidente debe mostrar:
- ID del incidente
- Tipo de incidente (ej: Incendio)
- Gravedad (badge con número)
- Zona donde ocurrió
- Tiempo transcurrido (minutos simulados)
- Estado actual
- Prioridad
- Recursos asignados
- Modo de detección (automático vs operador)
- Botón de cierre manual (si aplica)

### Paso 3: Verificar resolución automática (R7)
1. Disparar una catástrofe y esperar
2. Cuando el recurso llega a la zona → estado del recurso cambia a "Atendiendo"
3. Después de un tiempo de atención → recurso termina (`timestamp_finalizacion`)
4. Si era el ÚNICO recurso asignado → el incidente debe pasar automáticamente a "Resuelto"
5. El incidente resuelto debe desaparecer del panel de incidentes activos (o mostrarse como resuelto)

### Paso 4: Verificar escalamiento por SLA (R16)
1. Disparar varias catástrofes rápidamente para saturar los recursos
2. Algún incidente debería quedar sin atención o con atención lenta
3. Después de ~30 segundos reales (= 10 min simulados de SLA), el scheduler ejecuta `sp_EscalarIncidente()`
4. Los incidentes que excedieron el SLA deben pasar a estado "Escalado"
5. Verificar que se muestra visualmente diferente (ej: color diferente, badge "Escalado")

También podés forzar el escalamiento con:
```
POST http://localhost:8000/api/v1/incidents/escalate-overdue
```

### Paso 5: Verificar cierre manual
Si la spec lo permite, verificar si existe un botón de cierre manual en el panel de incidentes:
```
POST http://localhost:8000/api/v1/incidents/{id}/close
```
Esto llama a `sp_CerrarIncidente(id)`.

### Paso 6: Verificar incidentes activos por API
```
GET http://localhost:8000/api/v1/incidents/active
```
Comparar la lista con lo que muestra el panel. Los datos deben coincidir.

## Archivos relevantes si necesitás inspeccionar código
- `frontend/src/components/PanelIncidentes.tsx` — panel de incidentes
- `backend/app/routers/incidents.py` — endpoints de incidentes
- `backend/app/repositories/incidents_repo.py` — queries de incidentes
- `backend/app/services/scheduler.py` — escalamiento SLA y reactivación
- `specs.md` secciones §11 (Flujo) y §10 (Reglas R2, R7, R16, R20)

## Criterios de éxito
- [x] Incidentes pasan de Pendiente → En proceso cuando se asigna recurso
- [x] Incidentes pasan a Resuelto automáticamente cuando todos los recursos terminan (R7)
- [x] Incidentes se escalan a "Escalado" si exceden el SLA (R16)
- [x] El panel muestra toda la información requerida por la spec
- [x] El cierre manual funciona (si está implementado)
- [x] La API refleja los mismos datos que la UI

## Resultados

Se validó el ciclo de vida completo de los incidentes y el correcto funcionamiento de las reglas de negocio en la base de datos y la API:

1. **Ciclo de Estados**:
   - Al promover un evento, la base de datos inserta el incidente en estado `"Pendiente"`.
   - Inmediatamente después, el trigger R1 asigna los recursos correspondientes y actualiza el incidente a `"En proceso"` (R2), pasando los recursos a estado `"En tránsito"` (5).
2. **Cierre Automático (R7)**:
   - Al finalizar el viaje de los recursos y la atención simulada (`timestamp_finalizacion` no nulo), el trigger R8 libera los recursos de vuelta a `"Disponible"`.
   - Cuando todas las asignaciones finalizan, el trigger R7 promueve el incidente automáticamente a `"Resuelto"`. Se comprobó en la base de datos que tanto el incidente `14` como el `16` transitaron exitosamente a estado `3` (Resuelto).
3. **Escalamiento SLA (R16)**:
   - El procedimiento almacenado `sp_EscalarIncidente` obtiene de la vista `vIncidentesActivos` los incidentes con `sla_incumplido = TRUE` (tiempo transcurrido > SLA).
   - Incrementa la gravedad de forma temporal (`LEAST(fk_gravedad_id + 1, 5)`) y cambia el estado del incidente a `"Escalado"`.
   - Está expuesto correctamente en la API via `POST /api/v1/incidents/escalate-overdue`.
4. **Cierre Manual**:
   - El procedimiento `sp_CerrarIncidente(id)` está implementado en la DB y expuesto via `POST /api/v1/incidents/{id}/close`.
   - Bloquea el registro via `FOR UPDATE` y si el incidente estaba en estado `"Pendiente"` lo pasa a `"Cancelado"`. Si estaba `"En proceso"` o `"Escalado"`, finaliza todas las asignaciones con `timestamp_finalizacion = CURRENT_TIMESTAMP`, lo que a su vez libera los recursos a `"Disponible"` y marca el incidente como `"Resuelto"`.

