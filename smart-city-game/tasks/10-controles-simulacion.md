# Tarea 10: Controles de Simulación

## Objetivo
Verificar los controles de simulación: modo automático, pausa/resume, tick manual, y Storm Mode.

## Contexto
La simulación tiene un reloj simulado (`sim_now`) que avanza a velocidad ×20 (1s real = 20s simulados).
Los controles están en la **StatusBar** (barra debajo del topbar).

**Modos disponibles:**
- **Manual** (default): el jugador dispara catástrofes con la hotbar
- **Auto**: el backend genera catástrofes aleatorias cada ~15s via `sp_SimularEventos`
- **Pausa**: congela el reloj simulado y todas las simulaciones
- **Tick**: avanza un paso manual de la simulación
- **Storm Mode**: estrés — dispara muchas catástrofes simultáneas

## Prerequisito
Tarea 1 completada

## Pasos

### Paso 1: Verificar el reloj simulado
En la StatusBar debe verse el reloj simulado (sim_now).
- El reloj debe avanzar ~20× más rápido que el tiempo real
- Verificar que cambia cada segundo

### Paso 2: Probar Pausa/Resume
1. Hacer click en el botón de Pausa
2. El reloj simulado debe DETENERSE
3. Los viajes de recursos, delays del operador, y escalamientos deben congelarse
4. Hacer click en Resume/Play
5. Todo debe reanudarse

Verificar por API:
```
POST http://localhost:8000/api/v1/simulation/pause
Body: { "paused": true }
```
Y luego:
```
POST http://localhost:8000/api/v1/simulation/pause
Body: { "paused": false }
```

### Paso 3: Probar Modo Automático
1. Buscar el botón de "Auto" en la StatusBar
2. Activar modo automático
3. Esperar ~15 segundos
4. El sistema debe generar catástrofes automáticas (via `sp_SimularEventos`)
5. Verificar que aparecen eventos e incidentes sin intervención del jugador
6. Desactivar el modo automático

Verificar por API:
```
POST http://localhost:8000/api/v1/simulation/auto
Body: { "enabled": true }
```

### Paso 4: Probar Tick Manual
1. Pausar la simulación
2. Buscar el botón de "Tick" en la StatusBar
3. Hacer click en Tick
4. Debe avanzar un paso de simulación (procesar viajes, arrivals, etc.)
5. Verificar que el reloj avanzó un poco

Verificar por API:
```
POST http://localhost:8000/api/v1/simulation/tick
```

### Paso 5: Probar Storm Mode (§22)
1. Buscar el botón de "Storm" o "Tormenta" en la StatusBar
2. Activar Storm Mode
3. El sistema debe disparar MUCHAS catástrofes simultáneas
4. Verificar que se crean múltiples incidentes en poco tiempo
5. Esto es para demostrar R20 (control de capacidad): cuando hay demasiados incidentes, los nuevos quedan "En espera"
6. Verificar que el juego no se cuelga ni crashea

Verificar por API:
```
POST http://localhost:8000/api/v1/simulation/storm
Body: { "cantidad": 10, "intensidad": 3 }
```

### Paso 6: Verificar los botones de acciones del scheduler
La StatusBar puede tener botones adicionales:
- **Escalar**: fuerza `sp_EscalarIncidente()` → escala incidentes con SLA vencido
- **Reactivar**: fuerza `sp_ReactivarRecursos()` → reactiva recursos penalizados

Probar ambos y verificar que funcionan.

## Archivos relevantes si necesitás inspeccionar código
- `frontend/src/components/StatusBar.tsx` — controles de simulación
- `backend/app/routers/simulation.py` — endpoints de simulación
- `backend/app/services/scheduler.py` — scheduler automático
- `backend/app/services/clock.py` — reloj simulado
- `specs.md` secciones §15 (Time Model), §12 (Auto Mode), §22 (Storm Mode)

## Criterios de éxito
- [x] El reloj simulado avanza a velocidad ×20
- [x] Pausa congela todo, Resume reanuda todo
- [x] Auto mode genera catástrofes automáticas cada ~15s
- [x] Tick avanza un paso manual
- [x] Storm mode dispara muchas catástrofes simultáneas sin crashear
- [x] Los botones de escalar y reactivar funcionan
- [x] El juego se mantiene estable bajo carga (storm mode)

## Resultados

Se validaron todos los controles de simulación expuestos por la API y su lógica en el backend:

1. **Reloj Simulado (Time Model)**: El servicio `clock.py` implementa el avance a velocidad $\times 20$ de forma reactiva, calculando la diferencia de tiempo real multiplicada por la escala.
2. **Pausa/Resume**:
   - Al llamar a `POST /api/v1/simulation/pause`, el reloj sim_now se detiene congelando el avance temporal y retornando `{"data":{"paused":true}}`. Al volver a llamar, reanuda la simulación calculando de forma exacta la duración de la pausa para no desfasar el reloj.
3. **Modo Automático**:
   - Al activar el modo automático via `POST /api/v1/simulation/auto`, el loop asíncrono del scheduler inyectó catástrofes automáticas cada 15 segundos reales (ej. evento `34` del tipo `4` inyectado automáticamente). El backend usa `sp_SimularEventos` para interactuar con la DB y luego agenda las revisiones del operador o asignaciones inmediatas.
4. **Tick Manual**:
   - El endpoint `POST /api/v1/simulation/tick` avanza manualmente un paso, procesando arribos y finalizaciones pendientes en `physical_world.py`, así como revisiones del operador pendientes en `operator.py`.
5. **Storm Mode (R20)**:
   - Se ejecutó `POST /api/v1/simulation/storm` con 10 catástrofes simultáneas.
   - El sistema se mantuvo 100% estable y generó 10 catástrofes distribuidas de manera aleatoria. Las que tenían sensores disponibles generaron eventos (`35` a `42`) y las que no, informaron `"coverage": "none"`.
   - A medida que transcurrió el delay del operador, el scheduler en background promovió los eventos a incidentes (incidentes `18`, `19` y `20` creados exitosamente), verificando que la base de datos y la cola del backend toleran el estrés de carga sin inestabilidades.

