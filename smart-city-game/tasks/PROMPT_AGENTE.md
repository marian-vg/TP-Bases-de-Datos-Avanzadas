# Prompt para Agente de Revisión — Smart City Game

## Tu Rol

Sos un agente **orquestador**. Tu trabajo es revisar el juego "Smart City Game" verificando que cumple con su especificación. NO vas a hacer todo el trabajo vos solo — vas a **delegar tareas a subagentes** y compilar los resultados.

## Reglas Fundamentales

1. **NO modificar NADA**. Ni la base de datos, ni el backend, ni el frontend. Solo lectura + interacción via browser.
2. **NO agregar funcionalidades**. El juego ya está terminado.
3. **Usá subagentes**. Cada tarea (o grupo de tareas relacionadas) la delega a un subagente. Vos coordinás y compilás.
4. **Reportá resultados** completando la sección "Resultados" de cada archivo de tarea.

## El Proyecto

Es un juego visual construido sobre un TP universitario de Bases de Datos Activas (PostgreSQL). El juego permite al jugador causar catástrofes en una ciudad, y observar cómo la base de datos (via triggers y stored procedures) reacciona automáticamente: asignando recursos, escalando incidentes, penalizando demoras, etc.

**Stack**: PostgreSQL (DB, intocable) + Python FastAPI (backend fino) + React/Vite (frontend)

## Archivos Clave

Todo está dentro de `/home/tomi/Documents/TP-Bases-de-Datos-Avanzadas/smart-city-game/`:

| Archivo | Para qué |
|---------|----------|
| `tasks/00-INDEX.md` | **LEELO PRIMERO** — índice de todas las tareas con orden y dependencias |
| `tasks/01-setup-y-health.md` a `tasks/11-resumen-final.md` | Las 11 tareas individuales de revisión |
| `specs.md` | Especificación completa del juego (603 líneas) — la referencia definitiva |
| `DEVIATIONS.md` | Desviaciones documentadas respecto a la spec |
| `INSTRUCCIONES_PARA_JUGAR.md` | Cómo levantar el juego |
| `SECRET_COMPLIANCE.md` | Tracker de cumplimiento |

## Cómo Levantar el Juego

```bash
# 1. Levantar la DB (desde la raíz del repo)
cd /home/tomi/Documents/TP-Bases-de-Datos-Avanzadas
docker compose up -d

# 2. Esperar ~10s, luego levantar el juego
cd /home/tomi/Documents/TP-Bases-de-Datos-Avanzadas/smart-city-game
cp -n .env.example .env
docker compose up -d --build

# 3. Verificar
# Frontend: http://localhost:5173
# Backend:  http://localhost:8000/api/v1/health
```

## Estrategia de Ejecución

### Fase 1: Setup (hacelo vos mismo, inline)
1. Leé `tasks/00-INDEX.md` para entender el plan completo
2. Ejecutá la tarea 1 (`01-setup-y-health.md`) vos mismo — levantar el juego y verificar health checks
3. Confirmá que todo corre antes de delegar

### Fase 2: Delegación paralela (subagentes)
Una vez que el juego esté corriendo, lanzá subagentes en paralelo para las tareas independientes:

**Lote 1** (se pueden hacer en paralelo):
- Subagente A → Tarea 2 (Mapa y Zonas) + Tarea 3 (Hotbar y Catástrofes)
- Subagente B → Tarea 8 (Paneles Laterales) + Tarea 9 (Vistas SQL)

**Lote 2** (dependen del Lote 1):
- Subagente C → Tarea 4 (Flujo Detección) + Tarea 5 (Asignación y Movimiento)
- Subagente D → Tarea 10 (Controles de Simulación)

**Lote 3** (depende del Lote 2):
- Subagente E → Tarea 6 (Ciclo Incidentes) + Tarea 7 (Penalizaciones)

### Fase 3: Compilación (hacelo vos mismo)
Cuando todos los subagentes reporten:
1. Leé sus resultados
2. Completá `tasks/11-resumen-final.md` con el estado de cada tarea, regla del TP, y requerimiento funcional
3. Listá problemas encontrados clasificados por severidad

## Instrucciones para Subagentes

Cuando delegues a un subagente, incluí en su prompt:

1. **Qué tarea(s)**: el path al archivo `.md` de la tarea (ej: `tasks/02-mapa-y-zonas.md`)
2. **Que lea el archivo de tarea COMPLETO** antes de empezar — ahí están los pasos, criterios, y archivos de código relevantes
3. **Que use el navegador** (http://localhost:5173) para verificar la UI interactivamente
4. **Que también verifique por API** (curl a http://localhost:8000/api/v1/...) cuando la tarea lo indique
5. **Que puede leer código fuente** si necesita entender algo, pero NO modificarlo
6. **Que reporte los resultados** como una lista de criterios ✅/❌ con notas

Ejemplo de prompt para subagente:
```
Sos un tester del juego Smart City Game. El juego ya está corriendo en http://localhost:5173 (frontend) y http://localhost:8000 (backend API).

Tu tarea es completar las verificaciones descritas en:
- /home/tomi/Documents/TP-Bases-de-Datos-Avanzadas/smart-city-game/tasks/02-mapa-y-zonas.md
- /home/tomi/Documents/TP-Bases-de-Datos-Avanzadas/smart-city-game/tasks/03-hotbar-catastrofes.md

Leé cada archivo COMPLETO antes de empezar. Seguí los pasos en orden. 
Usá el navegador para verificar la UI y curl/API para verificar datos.
NO modifiques ningún archivo. Solo lectura + interacción.

Reportá los resultados como lista de criterios ✅/❌ con notas de lo que encontraste.
Si algo falla, describí exactamente qué pasó y qué esperabas.
```

## Qué Reportar al Final

Tu reporte final (en `tasks/11-resumen-final.md`) debe tener:
1. Estado de cada tarea (✅/⚠️/❌)
2. Estado de cada regla del TP (R1-R21) que se pueda verificar desde el juego
3. Estado de cada requerimiento funcional (RF1-RF13)
4. Lista de problemas clasificados: Críticos / Moderados / Menores
5. Conclusión: ¿el juego está listo para la defensa oral?
