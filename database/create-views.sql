-- ============================================================================
-- SMART CITY - SCRIPT DE CREACIÓN DE VISTAS
-- ============================================================================
-- Este script genera todas las vistas necesarias para el monitoreo operativo,
-- el cruce de datos temporales (SLA) y la toma de decisiones para las 
-- reglas activas del sistema.
--
-- Para ejecutar este script desde la raíz del proyecto:
-- == POWERSHELL COMMAND ==
-- $env:PGPASSWORD="password"; psql -h localhost -U postgres -d db_name -f database/create-views.sql
--
-- == CMD COMMAND ==
-- set PGPASSWORD=password && psql -h localhost -U postgres -d db_name -f database/create-views.sql
-- ============================================================================

-- ============================================================================
-- VISTAS DE INCIDENTES
-- ============================================================================

-- vIncidentesActivos: Incidentes CON recursos pero SIN terminar o cancelar.
CREATE OR REPLACE VIEW vIncidentesActivos AS
SELECT 
    i.id_incidente, 
    i.fecha_hora_registro,
    ROUND(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - i.fecha_hora_registro)) / 60) AS minutos_transcurridos,
    sla.tiempo_respuesta_minutos AS limite_sla_minutos,
    (ROUND(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - i.fecha_hora_registro)) / 60) > sla.tiempo_respuesta_minutos) AS sla_incumplido,
    ti.nombre AS tipo_incidente,
    g.nombre AS gravedad, 
    z.nombre AS zona, 
    ei.nombre AS estado_actual,
    i.descripcion
FROM Incidente i
JOIN EstadoIncidente ei ON i.fk_estado_incidente_id = ei.id_estado_incidente
JOIN TipoIncidente ti ON i.fk_tipo_incidente_id = ti.id_tipo_incidente
JOIN Gravedad g ON i.fk_gravedad_id = g.id_gravedad
JOIN SLA sla ON g.id_gravedad = sla.fk_gravedad_id
JOIN Zona z ON i.fk_zona_id = z.id_zona
WHERE ei.nombre NOT IN ('Resuelto', 'Cancelado') 
  AND EXISTS (
      SELECT 1 FROM Asignacion a 
      WHERE a.fk_incidente_id = i.id_incidente 
      AND a.timestamp_finalizacion IS NULL
  );
-- vIncidentesCriticos: Incidentes de gravedad Alta, Crítica o Catastrófica.
CREATE OR REPLACE VIEW vIncidentesCriticos AS
SELECT 
    i.id_incidente, 
    i.prioridad,
    i.fecha_hora_registro, 
    ti.nombre AS tipo_incidente,
    z.nombre AS zona, 
    ei.nombre AS estado
FROM Incidente i
JOIN Gravedad g ON i.fk_gravedad_id = g.id_gravedad
JOIN TipoIncidente ti ON i.fk_tipo_incidente_id = ti.id_tipo_incidente
JOIN EstadoIncidente ei ON i.fk_estado_incidente_id = ei.id_estado_incidente
JOIN Zona z ON i.fk_zona_id = z.id_zona
WHERE g.nombre IN ('Alta', 'Crítica', 'Catastrófica');

-- vHistorialIncidentes: Detalle completo de todos los incidentes.
CREATE OR REPLACE VIEW vHistorialIncidentes AS
SELECT 
    i.id_incidente, 
    ti.nombre AS tipo_incidente, 
    i.descripcion, 
    i.fecha_hora_registro,
    g.nombre AS gravedad, 
    ei.nombre AS estado, 
    z.nombre AS zona, 
    i.prioridad
FROM Incidente i
JOIN TipoIncidente ti ON i.fk_tipo_incidente_id = ti.id_tipo_incidente
JOIN Gravedad g ON i.fk_gravedad_id = g.id_gravedad
JOIN EstadoIncidente ei ON i.fk_estado_incidente_id = ei.id_estado_incidente
JOIN Zona z ON i.fk_zona_id = z.id_zona;

-- vZonasIncidentadas: Agrupación de zonas por cantidad de incidentes.
CREATE OR REPLACE VIEW vZonasIncidentadas AS
SELECT 
    z.id_zona, 
    z.nombre AS zona, 
    nr.nombre AS nivel_riesgo, 
    COUNT(i.id_incidente) AS total_incidentes
FROM Zona z
JOIN NivelRiesgo nr ON z.fk_nivel_riesgo_id = nr.id_nivel_riesgo
JOIN Incidente i ON z.id_zona = i.fk_zona_id
JOIN EstadoIncidente ei ON i.fk_estado_incidente_id = ei.id_estado_incidente
WHERE ei.nombre NOT IN ('Resuelto', 'Cancelado')
GROUP BY z.id_zona, z.nombre, nr.nombre
ORDER BY total_incidentes DESC;

-- ============================================================================
-- VISTAS DE RECURSOS
-- ============================================================================

-- vRecursosDisponibles: Recursos listos para ser asignados.
CREATE OR REPLACE VIEW vRecursosDisponibles AS
SELECT 
    r.id_recurso, 
    tr.nombre AS tipo_recurso, 
    z.nombre AS zona_base, 
    er.nombre AS estado
FROM Recurso r
JOIN EstadoRecurso er ON r.fk_estado_recurso_id = er.id_estado_recurso
JOIN TipoRecurso tr ON r.fk_tipo_recurso_id = tr.id_tipo_recurso
JOIN Zona z ON r.fk_zona_base_id = z.id_zona
WHERE er.nombre = 'Disponible';

-- vRecursosOcupados: Recursos que actualmente están atendiendo un incidente.
CREATE OR REPLACE VIEW vRecursosOcupados AS
SELECT 
    r.id_recurso, 
    tr.nombre AS tipo_recurso, 
    z_base.nombre AS zona_base, 
    z_incidente.nombre AS zona_actual_asignada,
    er.nombre AS estado,
    i.id_incidente,
    i.descripcion AS descripcion_incidente,
    a.timestamp_asignacion,
    ROUND(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - a.timestamp_asignacion)) / 60) AS minutos_asignado
FROM Recurso r
JOIN EstadoRecurso er ON r.fk_estado_recurso_id = er.id_estado_recurso
JOIN TipoRecurso tr ON r.fk_tipo_recurso_id = tr.id_tipo_recurso
JOIN Zona z_base ON r.fk_zona_base_id = z_base.id_zona
JOIN Asignacion a ON r.id_recurso = a.fk_recurso_id
JOIN Incidente i ON a.fk_incidente_id = i.id_incidente
JOIN Zona z_incidente ON i.fk_zona_id = z_incidente.id_zona
WHERE er.nombre = 'Ocupado'
  AND a.timestamp_finalizacion IS NULL;

-- vRecursosPenalizados: Historial de recursos sancionados.
CREATE OR REPLACE VIEW vRecursosPenalizados AS
SELECT 
    r.id_recurso, 
    tr.nombre AS tipo_recurso,
    er.nombre AS estado_recurso,
    COUNT(p.id_penalizacion) AS cantidad_infracciones,
    SUM(COALESCE(p.puntaje, tp.puntaje)) AS puntos_acumulados,
    MAX(p.fecha) AS ultima_penalizacion,
    (
        SELECT COUNT(*)
        FROM Penalizacion pv
        WHERE pv.fk_recurso_id = r.id_recurso
          AND (pv.fecha + pv.hora) > COALESCE(
              (
                  SELECT MAX(ir2.fecha_reactivado)
                  FROM InhabilitacionRecurso ir2
                  WHERE ir2.fk_recurso_id = r.id_recurso
              ),
              TIMESTAMP '-infinity'
          )
    ) AS penalizaciones_vigentes,
    ir.fecha_inhabilitacion,
    ir.fecha_reactivacion_programada
FROM Recurso r
JOIN Penalizacion p ON r.id_recurso = p.fk_recurso_id
JOIN TipoRecurso tr ON r.fk_tipo_recurso_id = tr.id_tipo_recurso
JOIN EstadoRecurso er ON r.fk_estado_recurso_id = er.id_estado_recurso
JOIN TipoPenalizacion tp ON p.fk_tipo_penalizacion_id = tp.id_tipo_penalizacion
LEFT JOIN InhabilitacionRecurso ir
  ON ir.fk_recurso_id = r.id_recurso
 AND ir.fecha_reactivado IS NULL
GROUP BY r.id_recurso, tr.nombre, er.nombre,
         ir.fecha_inhabilitacion, ir.fecha_reactivacion_programada
ORDER BY puntos_acumulados DESC;

-- vRecursosCandidatos: Cruza la disponibilidad con la carga de trabajo histórica y las penalizaciones.
CREATE OR REPLACE VIEW vRecursosCandidatos AS
SELECT
    r.id_recurso,
    tr.nombre AS tipo_recurso,
    z.nombre AS zona_base,
    (SELECT COUNT(*) FROM Asignacion a WHERE a.fk_recurso_id = r.id_recurso) AS cantidad_asignaciones_historicas,
    COALESCE((
        SELECT SUM(COALESCE(p.puntaje, tp.puntaje))
        FROM Penalizacion p
        JOIN TipoPenalizacion tp ON p.fk_tipo_penalizacion_id = tp.id_tipo_penalizacion
        WHERE p.fk_recurso_id = r.id_recurso
    ), 0) AS puntos_penalizacion
FROM Recurso r
JOIN EstadoRecurso er ON r.fk_estado_recurso_id = er.id_estado_recurso
JOIN TipoRecurso tr ON r.fk_tipo_recurso_id = tr.id_tipo_recurso
JOIN Zona z ON r.fk_zona_base_id = z.id_zona
WHERE er.nombre = 'Disponible'
ORDER BY puntos_penalizacion ASC, cantidad_asignaciones_historicas ASC;

-- ============================================================================
-- VISTAS DE SENSORES
-- ============================================================================

-- vSensoresMantenimiento: confianza derivada de cada sensor (R21) y necesidad de revisión.
-- Confianza = 100 - (decaimiento_semanal * semanas desde la última revisión), con piso en 0.
-- La "última revisión" es el MAX(fecha) en MantenimientoSensor o, si nunca se mantuvo, la fecha de instalación.
CREATE OR REPLACE VIEW vSensoresMantenimiento AS
SELECT
    s.id_sensor,
    s.nombre        AS sensor,
    ts.nombre       AS tipo_sensor,
    z.nombre        AS zona,
    calc.ultima_revision,
    calc.semanas_sin_mantenimiento,
    calc.umbral_confianza,
    (calc.umbral_confianza <= param.umbral_minimo) AS requiere_mantenimiento
FROM Sensor s
JOIN TipoSensor ts ON s.fk_tipo_sensor_id = ts.id_tipo_sensor
JOIN Zona z        ON s.fk_zona_id        = z.id_zona
CROSS JOIN LATERAL (
    SELECT
        COALESCE(
            (SELECT MAX(m.fecha) FROM MantenimientoSensor m WHERE m.fk_sensor_id = s.id_sensor),
            s.fecha_instalado
        ) AS ultima_revision
) ult
CROSS JOIN LATERAL (
    SELECT
        ult.ultima_revision,
        FLOOR((CURRENT_DATE - ult.ultima_revision) / 7) AS semanas_sin_mantenimiento,
        GREATEST(0,
            100 - COALESCE(
                (SELECT numero FROM ParametrosSistema WHERE nombre_parametro = 'SENSOR_DECAIMIENTO_CONFIANZA_SEMANAL'),
                5
            ) * FLOOR((CURRENT_DATE - ult.ultima_revision) / 7)
        ) AS umbral_confianza
) calc
CROSS JOIN LATERAL (
    SELECT COALESCE(
        (SELECT numero FROM ParametrosSistema WHERE nombre_parametro = 'SENSOR_UMBRAL_CONFIANZA_MINIMO'),
        80
    ) AS umbral_minimo
) param
ORDER BY calc.umbral_confianza ASC;

-- ============================================================================
-- VISTAS DE ASIGNACIONES Y AUDITORÍA
-- ============================================================================

-- vHistorialAsignaciones: Detalle operativo de la intervención.
CREATE OR REPLACE VIEW vHistorialAsignaciones AS
SELECT 
    a.id_asignacion, 
    a.fk_incidente_id AS id_incidente, 
    i.descripcion AS descripcion_incidente,
    r.id_recurso, 
    tr.nombre AS tipo_recurso,
    a.timestamp_asignacion, 
    a.timestamp_llegada, 
    a.timestamp_finalizacion,
    CASE
        WHEN a.estado_exito IS NULL THEN 'En Curso'
        WHEN a.estado_exito = TRUE THEN 'Exitoso'
        ELSE 'Fallido'
    END AS estado_intervencion
FROM Asignacion a
JOIN Recurso r ON a.fk_recurso_id = r.id_recurso
JOIN TipoRecurso tr ON r.fk_tipo_recurso_id = tr.id_tipo_recurso
JOIN Incidente i ON a.fk_incidente_id = i.id_incidente;

-- vHistorialTriggers: Filtrado del Log unificado solo para reglas activas (R19).
CREATE OR REPLACE VIEW vHistorialTriggers AS
SELECT 
    id_log, 
    timestamp, 
    tablaAfectada, 
    idTablaAfectada, 
    operacion, 
    trigger_disparador, 
    detalle
FROM Log
WHERE trigger_disparador IS NOT NULL
ORDER BY timestamp DESC;
