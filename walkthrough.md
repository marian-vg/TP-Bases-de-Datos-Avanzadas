# Walkthrough - Implementación de Reglas 10 y 11

Este archivo registra el progreso de la implementación de las reglas de validación R10 y R11.

---

## Tareas

- [x] Analizar complejidad de R10 y R11 (Completado - Ver `implementation_plan.md`)
- [x] Implementar la regla R10 en `database/triggers/reglas-validadoras.sql` (Completado)
- [x] Implementar la regla R11 en `database/triggers/reglas-validadoras.sql` (Completado)
- [x] Validar sintaxis de las funciones y triggers creados (Completado)

---

## Detalle de Ejecución

### 1. Análisis de Complejidad
Realizado en [implementation_plan.md](file:///C:/Users/Administrador/herd/tp-bda/implementation_plan.md). Ambas reglas tienen complejidad Baja-Media.
- R10: Requiere verificar zonas habilitadas de recursos y manejar el bypass `my.bypass_zona`.
- R11: Requiere buscar duplicados en un rango de tiempo ajustable por parámetro del sistema, excluyendo incidentes cancelados.

### 2. Implementación de R10
Implementado en [reglas-validadoras.sql](file:///C:/Users/Administrador/herd/tp-bda/database/triggers/reglas-validadoras.sql#L137-L181).
- Función: `fn_valida_zona_recurso()`
- Trigger: `trg_valida_zona_recurso`
- Respeta la convención `"nombre_tabla.columna_tabla"` (ej. `ZonaRecurso.id_recurso` e `Incidente.fk_zona_id`).
- Integra soporte de rebalanceo de emergencia (bypass `my.bypass_zona`).

### 3. Implementación de R11
Implementado en [reglas-validadoras.sql](file:///C:/Users/Administrador/herd/tp-bda/database/triggers/reglas-validadoras.sql#L183-L226).
- Función: `fn_valida_duplicacion_incidente()`
- Trigger: `trg_valida_duplicacion_incidente`
- Evita IDs hardcodeados al validar contra `EstadoIncidente.nombre IS DISTINCT FROM 'Cancelado'`.
- Utiliza la tabla de parámetros `ParametrosSistema` para buscar `MINUTOS_DUPLICADO_INCIDENTE`.
