# Plan de Implementación - Reglas Validadoras R10 y R11

Este plan describe el análisis de complejidad y la estrategia para implementar las reglas de validación R10 y R11 en el archivo [reglas-validadoras.sql](file:///C:/Users/Administrador/herd/tp-bda/database/triggers/reglas-validadoras.sql).

---

## 1. Análisis de Complejidad de las Reglas

### R10. Validación de zona del recurso
* **Enunciado**: *Un recurso solo podrá asignarse a incidentes dentro de su zona habilitada.*
* **Complejidad**: **Baja-Media**.
* **Detalle técnico**:
  - Se ejecuta mediante un trigger `BEFORE INSERT OR UPDATE` sobre la tabla `Asignacion`.
  - Debe obtener la zona del incidente a través de una consulta a la tabla `Incidente` (`Incidente.fk_zona_id`).
  - Debe validar si existe la habilitación en la tabla de asociación `ZonaRecurso`.
  - **Excepción/Bypass (R15)**: Debe contemplar el bypass `my.bypass_zona = '1'` que se utiliza para rebalanceos de emergencia geográficos (regla R15). Si está activo, se permite la asignación aunque el recurso no esté formalmente habilitado en esa zona.
  - **Convención**: Usar nombres de tabla completos para calificar las columnas (ej. `ZonaRecurso.id_recurso` y `Incidente.id_incidente`).

### R11. Validación de duplicación de incidentes
* **Enunciado**: *Se deberá evitar registrar incidentes duplicados en un corto período (misma zona y tipo).*
* **Complejidad**: **Baja-Media**.
* **Detalle técnico**:
  - Se ejecuta mediante un trigger `BEFORE INSERT` sobre la tabla `Incidente`.
  - Debe buscar el parámetro `MINUTOS_DUPLICADO_INCIDENTE` en la tabla `ParametrosSistema` (con un valor por defecto de 10 minutos si no existe).
  - Debe verificar si en la tabla `Incidente` ya existe un registro con la misma zona (`Incidente.fk_zona_id`) y mismo tipo de incidente (`Incidente.fk_tipo_incidente_id`), que no esté en estado `Cancelado` (validando contra la tabla `EstadoIncidente`), y cuya fecha de registro (`Incidente.fecha_hora_registro`) esté dentro del intervalo definido (`fecha_hora_registro >= CURRENT_TIMESTAMP - (v_minutos * INTERVAL '1 minute')`).
  - **Convención**: Usar nombres de tabla completos para calificar las columnas y evitar IDs hardcodeados para el estado "Cancelado" mediante joins dinámicos con `EstadoIncidente`.

---

## 2. Estrategia de Implementación

Modificaremos el archivo [reglas-validadoras.sql](file:///C:/Users/Administrador/herd/tp-bda/database/triggers/reglas-validadoras.sql) reemplazando los placeholders correspondientes a R10 y R11 con:
1. `fn_valida_zona_recurso()` y su trigger `trg_valida_zona_recurso`.
2. `fn_valida_duplicacion_incidente()` y su trigger `trg_valida_duplicacion_incidente`.

Ambas funciones de trigger seguirán las convenciones del usuario.
