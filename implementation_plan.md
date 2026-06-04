# Plan de Implementación: Procedimientos Almacenados P2 y P3

Este documento detalla la planificación y arquitectura para implementar dos nuevos procedimientos almacenados en la base de datos `smart_city`, fortaleciendo el ciclo de vida operativo de incidentes y sensores de manera consistente y concurrente.

---

## 1. Procedimiento Almacenado `sp_CerrarIncidente` (P2)

### Objetivo y Alcance
Permitir la finalización transaccional de un incidente, cerrando todas las asignaciones activas asociadas y liberando los recursos asignados de vuelta a su base operativa.

### Diseño e Integridad
1. **Bloqueo Concurrente:** Bloquear la fila en la tabla `Incidente` mediante `FOR UPDATE` al inicio de la llamada para asegurar exclusión mutua sobre el estado del incidente.
2. **Validación de Estado Terminal (R9):** Si el incidente ya está en estado `'Resuelto'` o `'Cancelado'`, lanzar una excepción descriptiva.
3. **Manejo de Transición de Estados (R9):**
   * Si el incidente está en `'Pendiente'` (0 recursos asignados), la única transición de finalización válida es a `'Cancelado'`.
   * Si está en `'En proceso'` o `'Escalado'`, la transición correcta de finalización es a `'Resuelto'`.
4. **Liberación de Recursos (R8):**
   * Actualizar las asignaciones activas de la tabla `Asignacion` (`timestamp_finalizacion = CURRENT_TIMESTAMP`, `estado_exito = TRUE`).
   * Esta actualización activará automáticamente el trigger `trg_asignacion_finalizada`, liberando los recursos asociados (su estado en la tabla `Recurso` pasa a `'Disponible'`).
5. **Auditoría:** La actualización del incidente y de las asignaciones activará los triggers de auditoría genéricos (`trg_audit_incidente` y `trg_audit_asignacion`) que persisten el log.

---

## 2. Procedimiento Almacenado `sp_SimularEventoSensor` (P3)

### Objetivo y Alcance
Simular la activación de un sensor físico que reporta un evento, desencadenando la creación automática de incidentes e interactuando con los motores de asignación en un flujo unificado.

### Diseño e Integridad
1. **Bloqueo Concurrente:** Bloquear la fila del sensor en la tabla `Sensor` mediante `FOR UPDATE` para evitar inconsistencias concurrentes de configuración de zona/tipo.
2. **Validación de Catálogos:** Verificar que existan tanto el ID del sensor como el ID del tipo de evento.
3. **Inserción de Evento:** Registrar el evento en la tabla `Evento`.
4. **Interacción con Triggers (Cascada de Negocio):**
   * Al insertar el evento, se ejecutará el trigger `trg_evento_promocion` (motor de promoción).
   * Si el tipo de evento se mapea a un único tipo de incidente (tabla `TipoEventoTipoIncidente`), el trigger intentará insertar un nuevo incidente en estado `'Pendiente'`.
   * Al insertarse el incidente, se ejecutará el trigger `trg_asignacion_automatica`, el cual intentará despachar recursos compatibles.
5. **Verificación de Resultados e Integración con Auditoría:**
   * El SP verificará si el incidente fue creado con éxito.
   * Si fue creado, informará al usuario (ID de incidente generado y cantidad de recursos asignados automáticamente).
   * Si falló (por ejemplo, bloqueado por regla R11 de duplicados), consultará la tabla `Log` para extraer y reportar de manera amigable la regla de negocio que detuvo la promoción.

---

## 3. Cronograma de Tareas

1. **Creación de Scripts:** Escribir los archivos SQL `database/store-procedures/cerrar-incidente.sql` y `database/store-procedures/simular-eventos.sql`.
2. **Actualización de Migración:** Modificar `migrate.sql` para compilar secuencialmente ambos archivos en cascada.
3. **Escribir Pruebas unitarias/integración:** Agregar pruebas para ambos procedimientos en `tests/test-procedures.sql`.
4. **Ejecución y Verificación:** Ejecutar y validar que todas las aserciones e integraciones pasen sin problemas.
5. **Registro en Bitácora:** Actualizar `walkthrough.md` y documentar los resultados del ciclo TDD.
