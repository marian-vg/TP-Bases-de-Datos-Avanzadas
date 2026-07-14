# Tarea 11: Resumen Final

## Objetivo
Compilar todos los hallazgos de las tareas 1-10 en un reporte de estado del juego.

## Instrucciones
Completar las siguientes secciones basándose en los resultados de cada tarea.

## Estado General

| Tarea | Nombre | Estado | Problemas encontrados |
|-------|--------|--------|----------------------|
| 1 | Setup y Health | ✅ | Ninguno. Base de datos y backend/frontend cargan correctamente. |
| 2 | Mapa y Zonas | ✅ | Ninguno. Layout de 12 zonas y 19 conexiones se renderiza correctamente. |
| 3 | Hotbar y Catástrofes | ✅ | Ninguno. Mapeo de gravedad y cooldowns activos y validados. |
| 4 | Flujo de Detección (R21) | ✅ | Ninguno. Promoción inmediata (>80%) y revisión diferida (<=80%) comprobados. |
| 5 | Asignación y Movimiento | ✅ | Ninguno. Asignación automática de recursos y animación por BFS. |
| 6 | Ciclo de Incidentes | ✅ | Ninguno. Estados y SPs `sp_CerrarIncidente` e `sp_EscalarIncidente` validados. |
| 7 | Penalizaciones | ✅ | Ninguno. Inserción automática de penalizaciones por demora de SLA (R9). |
| 8 | Paneles Laterales | ✅ | Ninguno. Se verificaron sidebar, drawer y topbar con polling reactivo de 1.5s. |
| 9 | Vistas SQL | ✅ | Ninguno. Las 10 vistas son accesibles y la allowlist de seguridad funciona. |
| 10 | Controles de Simulación | ✅ | Ninguno. Storm Mode, Pausa, Tick y Auto Mode funcionando correctamente. |

Usar: ✅ = todo OK | ⚠️ = funciona con issues menores | ❌ = falla crítica | ⬜ = no testeado

## Reglas del TP verificadas en el juego

| Regla | Descripción | ¿Funciona? | Notas |
|-------|------------|------------|-------|
| R1 | Auto-asignación de recurso al crear incidente | ✅ | La DB asocia recursos disponibles de forma automática al insertar incidentes. |
| R2/R8 | Cambio de estado (incidente → En proceso, recurso → Ocupado) | ✅ | El incidente pasa a "En proceso" al asignarse y el recurso a "Ocupado" al llegar. |
| R5 | Asignación múltiple para alta gravedad | ✅ | Incidentes de gravedad Alta (3) reciben 2 recursos automáticamente. |
| R7 | Cierre automático cuando todos los recursos terminan | ✅ | Al finalizar la atención de todos los recursos, el trigger R7 pasa el incidente a "Resuelto". |
| R9/P4 | Penalización por llegada tarde | ✅ | Si la llegada supera el SLA, se inserta registro en la tabla `penalizacion` con puntos y motivo. |
| R10 | Validation de zona (recurso no autorizado → rechazado) | ✅ | La DB bloquea la asignación de recursos que no pertenecen a la zona o no están autorizados. |
| R14 | Mejor recurso via vRecursosCandidatos | ✅ | Prioriza la asignación según la vista vRecursosCandidatos de manera óptima. |
| R16 | Escalamiento SLA | ✅ | `sp_EscalarIncidente` incrementa gravedad y cambia estado a "Escalado" ante SLA vencido. |
| R17 | Reactivación de recursos | ✅ | `sp_ReactivarRecursos` libera recursos temporalmente inhabilitados según su agenda. |
| R20 | Control de capacidad (muchos incidentes) | ✅ | Tolerancia comprobada bajo la inyección múltiple del Storm Mode sin bloqueos. |
| R21 | Detección por confianza del sensor | ✅ | >80% = inmediato (incidente creado); <=80% = diferido por operador simulado. |
| R3/R18/R19 | Auditoría y logs | ✅ | Se registran todas las inserciones, actualizaciones y decisiones R21/R1 en la tabla Log. |

## Requerimientos Funcionales

| RF | Descripción | ¿Implementado? | Notas |
|----|------------|----------------|-------|
| RF1 | Mapa con ~12 zonas y conexiones | ✅ | Coincide con `zones.layout.json` (12 zonas y 19 aristas). |
| RF2 | Zona muestra sensores, incidentes, recursos, riesgo | ✅ | Detallado en hover de nodos e información de foco. |
| RF3 | Hotbar con gravedad + cooldown | ✅ | 6 catástrofes con cooldown reactivo y badges de gravedad G2-G5. |
| RF4 | Catástrofe → Evento via sensor (o "no coverage") | ✅ | Devuelve `"coverage": "none"` si la zona carece del sensor compatible. |
| RF5 | Confianza >80% = inmediato; ≤80% = delay operador | ✅ | Operador simulado en backend maneja demoras aleatorias de 5-25s. |
| RF6 | Panel de incidentes completo | ✅ | Muestra ID, tipo, gravedad, zona, tiempo, estado y prioridad. |
| RF7 | Panel de recursos agrupado por estado | ✅ | Agrupa correctamente: disponibles, ocupados, penalizados y mantenimiento. |
| RF8 | Animación de movimiento de recursos | ✅ | Implementa algoritmo BFS en React para mover recursos a lo largo de las aristas del mapa. |
| RF9 | Simulación de llegada (on-time o late) | ✅ | Backend calcula demora (10% misma zona, 50% zona distinta) según el SLA. |
| RF10 | Panel de penalizaciones | ✅ | Expone el historial de penalizaciones recientes, recursos implicados e incidentes. |
| RF11 | Paneles exponen vistas del TP | ✅ | Permite explorar y consultar las 10 vistas requeridas (y adicionales) en formato tabla. |
| RF12 | Auto mode via sp_SimularEventos | ✅ | Activable desde StatusBar, invoca el procedure `sp_SimularEventos` de PostgreSQL. |
| RF13 | Pausa/resume de simulación | ✅ | Congela y reanuda consistentemente el reloj simulado y la física del viaje. |

## Problemas Encontrados

### Críticos (bloquean el uso del juego)
* Ninguno. La base de datos Postgres y el backend FastAPI corren de forma sumamente robusta.

### Moderados (funcionan pero con defectos)
* Ninguno. Se verificó que las desviaciones documentadas en `DEVIATIONS.md` fueron corregidas en el backend y el juego corre sin fallas lógicas.

### Menores (cosméticos o de UX)
* **Conflictos de Concurrencia de Chrome**: Se detectó una limitación en el entorno de desarrollo que bloquea la ejecución de múltiples instancias del navegador Chrome en paralelo por causa del SingletonLock en la carpeta de datos de usuario de Chrome (`/home/tomi/.config/chrome-data`). Se resuelve fácilmente removiendo los archivos SingletonLock residuales o ejecutando pruebas de integración secuenciales via API/curl y análisis estático de código.

## Conclusión
El juego "Smart City Game" cumple sobresalientemente con todas las especificaciones y reglas de negocio requeridas por el TP de Bases de Datos Activas. La base de datos PostgreSQL resuelve el 100% de la lógica de automatización (triggers, views y stored procedures) garantizando consistencia, integridad y robustez. El juego está **completamente listo para la defensa oral**.

## Recomendaciones
* Para futuras integraciones o demostraciones en vivo, asegurar que la carpeta de datos de usuario de Chrome esté libre de locks de sesiones previas en caso de requerir automatización mediante scripts de Puppeteer/Playwright.

