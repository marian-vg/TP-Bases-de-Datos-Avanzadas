# Smart City Game — Tareas de Revisión

## Contexto

Este juego es una capa visual sobre un TP de Bases de Datos Activas. La DB es INTOCABLE. El backend es un orquestador fino (FastAPI). El frontend es React + Vite.

**Objetivo**: Revisar que el juego implementado cumpla con las specs (`specs.md`) y funcione correctamente.

**Regla de oro**: NO modificar la base de datos. NO agregar funcionalidades nuevas a la DB. El backend solo habla con la DB y simula cosas (viajes, operador, reloj).

## Archivos de referencia clave

| Archivo | Qué contiene |
|---------|-------------|
| `specs.md` | Especificación completa del juego (603 líneas) |
| `DEVIATIONS.md` | Desviaciones documentadas respecto a la spec |
| `INSTRUCCIONES_PARA_JUGAR.md` | Cómo levantar el juego |
| `SECRET_COMPLIANCE.md` | Tracker de cumplimiento de la spec |

## Orden de ejecución de tareas

Ejecutar EN ORDEN. Cada tarea depende de que las anteriores estén OK.

| # | Archivo | Descripción | Dependencia |
|---|---------|-------------|-------------|
| 1 | `01-setup-y-health.md` | Levantar el juego y verificar que todo corra | Ninguna |
| 2 | `02-mapa-y-zonas.md` | Verificar el mapa SVG, las 12 zonas y conexiones | Tarea 1 |
| 3 | `03-hotbar-catastrofes.md` | Probar los 6 tipos de catástrofe, cooldowns y gravedad | Tarea 1 |
| 4 | `04-flujo-deteccion.md` | Probar R21: detección por confianza del sensor (>80% y ≤80%) | Tarea 3 |
| 5 | `05-asignacion-y-movimiento.md` | Verificar asignación automática de recursos y animación de viaje | Tarea 4 |
| 6 | `06-ciclo-incidentes.md` | Verificar estados del incidente: pendiente → en proceso → resuelto/escalado | Tarea 5 |
| 7 | `07-penalizaciones.md` | Verificar que llegadas tarde generen penalizaciones | Tarea 5 |
| 8 | `08-paneles-laterales.md` | Revisar todos los paneles: incidentes, recursos, revisión, penalizaciones, logs | Tarea 1 |
| 9 | `09-vistas-sql.md` | Verificar las 10 vistas SQL expuestas en el panel de Vistas | Tarea 1 |
| 10 | `10-controles-simulacion.md` | Probar auto mode, pausa, tick, storm mode | Tarea 1 |
| 11 | `11-resumen-final.md` | Compilar hallazgos y generar reporte de estado | Todas |

## Cómo usar estas tareas

1. Leé el archivo `.md` de la tarea actual COMPLETO antes de empezar.
2. Seguí los pasos en orden.
3. Anotá los resultados (✅ pasa / ❌ falla + detalle) al final de cada tarea.
4. Si una tarea falla en algo crítico, reportalo y pasá a la siguiente igualmente.
5. Al final, completá la tarea 11 con el resumen.
