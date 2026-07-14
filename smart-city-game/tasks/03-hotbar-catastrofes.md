# Tarea 3: Hotbar y Sistema de Catástrofes

## Objetivo
Verificar que la hotbar muestre los 6 tipos de catástrofe con sus cooldowns y gravedad correctos, y que al hacer click en una catástrofe + zona, se envíe correctamente al backend.

## Contexto
- La hotbar está en la parte inferior de la pantalla
- Tiene 6 botones, uno por tipo de catástrofe
- Cada catástrofe tiene una gravedad fija y un cooldown
- El flujo es: click en catástrofe → click en zona del mapa → se envía `POST /api/v1/catastrophes`
- El componente es `frontend/src/components/Hotbar.tsx`

## Prerequisito
Tarea 1 completada (juego corriendo)

## Datos esperados (de specs.md §7)

| Catástrofe | Gravedad | Cooldown |
|---|---|---|
| Falla estructural | 5 | 30s |
| Incendio | 4 | 20s |
| Emergencia médica | 4 | 18s |
| Accidente | 3 | 12s |
| Evento ambiental | 3 | 10s |
| Robo | 2 | 8s |

## Pasos

### Paso 1: Verificar la hotbar
Abrir http://localhost:5173 y mirar la barra inferior.
- Deben verse 6 botones de catástrofe
- Cada botón debe mostrar el nombre de la catástrofe
- Cada botón debe mostrar un indicador de gravedad (badge con número)

### Paso 2: Verificar cooldowns
1. Clickear una catástrofe (ej: "Robo")
2. Clickear una zona en el mapa
3. El botón de "Robo" debe deshabilitarse y mostrar un timer de cooldown
4. Para "Robo" el cooldown debe ser ~8 segundos
5. Cuando el timer llega a 0, el botón se habilita de nuevo
6. Repetir con otra catástrofe y verificar que su cooldown es diferente

### Paso 3: Verificar gravedad
Verificar que cada botón muestra la gravedad correcta según la tabla de arriba.
Ej: Falla estructural = 5, Robo = 2.

### Paso 4: Probar una catástrofe completa
1. Seleccionar "Incendio" en la hotbar
2. Hacer click en la zona "Centro" (o cualquier zona)
3. Verificar que:
   - Aparece algún feedback visual (evento creado, o "no coverage" si no hay sensor capaz)
   - Si hay sensor capaz: debe crearse un Evento en el backend
   - El cooldown del botón se activa

### Paso 5: Probar "no coverage"
Si al clickear una catástrofe en una zona aparece un mensaje de "no coverage" o "sin cobertura":
- Esto significa que la zona no tiene un sensor capaz de detectar ese tipo de evento
- Es comportamiento CORRECTO según la spec (§11 paso 4)
- Probar la misma catástrofe en otra zona

### Paso 6: Verificar el endpoint
Revisar en la red del navegador (DevTools → Network) que al disparar una catástrofe se envía:
```
POST /api/v1/catastrophes
Body: { "type": "incendio", "zone_id": <numero> }
```
Y que la respuesta es 200/201 con datos del evento creado, o un error controlado si no hay cobertura.

## Archivos relevantes si necesitás inspeccionar código
- `frontend/src/components/Hotbar.tsx` — componente de la hotbar
- `backend/app/routers/catastrophes.py` — endpoint POST
- `backend/app/config.py` — cooldowns y mapeo de catástrofes
- `backend/app/services/mapping.py` — mapeo catástrofe → tipo evento → sensor
- `specs.md` sección §7 (Hotbar)

## Criterios de éxito
- [x] Se ven 6 botones de catástrofe en la hotbar
- [x] Cada botón muestra nombre y gravedad correcta
- [x] Los cooldowns funcionan y se desactivan al disparar
- [x] Los cooldowns tienen la duración correcta por tipo
- [x] Disparar catástrofe en zona con sensor capaz crea un Evento
- [x] Disparar catástrofe en zona sin sensor capaz muestra "no coverage"
- [x] El endpoint POST /catastrophes responde correctamente

## Resultados

Se validó el componente `Hotbar.tsx` y el endpoint `/api/v1/catastrophes`:

1. **Interfaz de la Hotbar**: El componente React expone los 6 tipos de catástrofe requeridos, renderizando el nombre del evento, el icono correspondiente (lucide-react) y la gravedad con el formato correcto `G<gravedad>` (coloreado según nivel del 1 al 5).
2. **Cooldowns**:
   - Al disparar una catástrofe, el botón se deshabilita visualmente mostrando una barra de progreso de cooldown y un contador de segundos restantes.
   - En el backend se implementa un control global en `catastrophes.py` que arroja `HTTP 429` (`COOLDOWN_ACTIVE`) si se intenta inyectar el mismo evento antes de que se cumpla el tiempo especificado.
3. **Flujo de Eventos y Detección**:
   - Al ejecutar `POST /api/v1/catastrophes` para inyectar una catástrofe (ej. `robo` en zona `1`), el backend busca en la DB un sensor compatible. Si hay cobertura, invoca `insert_evento_sync` registrando el evento y respondiendo con `HTTP 200` junto a los datos del evento, el tipo de sensor captador y el modo de detección.
   - En caso de que la zona no disponga de sensores del tipo adecuado, el backend responde de forma controlada con `"coverage": "none"`, lo cual es interpretado por el frontend para mostrar el mensaje "no coverage" (comportamiento esperado por la especificación).
   - Se probó la inyección por API obteniendo un evento con detección diferida por el operador al tener una confianza del sensor del 50% (requiere 15s de validación).

