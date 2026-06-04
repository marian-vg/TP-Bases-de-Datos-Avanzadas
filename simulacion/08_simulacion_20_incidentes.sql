-- =============================================================================
-- SIMULACION 08 - OBLIGATORIA (20 incidentes simultaneos)
-- =============================================================================
-- Que demuestra:
--   Carga masiva de 20 incidentes y como reacciona el motor:
--     - asignacion automatica donde hay recursos
--     - incidentes "Pendiente" si se supera capacidad del sistema
--     - rebalanceo desde otras zonas (R15) registrado en Log
--
-- Se baja temporalmente UMBRAL_INCIDENTES_ACTIVOS a 10 para forzar
-- cola de espera con solo 20 inserts (sin necesitar cientos de filas).
-- =============================================================================

DELETE FROM Asignacion;
DELETE FROM Penalizacion;
DELETE FROM Incidente;
DELETE FROM Evento;
DELETE FROM Log;

UPDATE Recurso SET fk_estado_recurso_id = 1 WHERE fk_estado_recurso_id <> 1;


-- Guardar umbral original y usar uno bajo para la demostracion

UPDATE ParametrosSistema
SET numero = 10
WHERE nombre_parametro = 'UMBRAL_INCIDENTES_ACTIVOS';


-- 20 incidentes: tipos y zonas distintas (evita regla anti-duplicado R11)

INSERT INTO Incidente (
    fk_tipo_incidente_id,
    fk_gravedad_id,
    fk_estado_incidente_id,
    fk_zona_id,
    descripcion,
    prioridad
)
SELECT
    ((s - 1) % 10) + 1,
    1,
    1,
    ((s - 1) % 12) + 1,
    'SIM-08 incidente simultaneo #' || s,
    1
FROM generate_series(1, 20) AS s;


-- Restaurar umbral del sistema

UPDATE ParametrosSistema
SET numero = 50
WHERE nombre_parametro = 'UMBRAL_INCIDENTES_ACTIVOS';


-- Resumen por estado

SELECT
    ei.nombre AS estado_incidente,
    COUNT(*) AS cantidad
FROM Incidente i
JOIN EstadoIncidente ei ON i.fk_estado_incidente_id = ei.id_estado_incidente
WHERE i.descripcion LIKE 'SIM-08 incidente simultaneo #%'
GROUP BY ei.nombre
ORDER BY ei.nombre;


-- Incidentes en cola (Pendiente sin asignacion = capacidad superada)

SELECT
    i.id_incidente,
    i.descripcion,
    z.nombre AS zona,
    ei.nombre AS estado
FROM Incidente i
JOIN Zona z ON i.fk_zona_id = z.id_zona
JOIN EstadoIncidente ei ON i.fk_estado_incidente_id = ei.id_estado_incidente
WHERE i.descripcion LIKE 'SIM-08 incidente simultaneo #%'
  AND ei.nombre = 'Pendiente'
  AND NOT EXISTS (
      SELECT 1 FROM Asignacion a WHERE a.fk_incidente_id = i.id_incidente
  )
ORDER BY i.id_incidente;


-- Incidentes ya atendidos (En proceso con asignacion)

SELECT
    i.id_incidente,
    i.descripcion,
    z.nombre AS zona,
    COUNT(a.id_asignacion) AS asignaciones_abiertas
FROM Incidente i
JOIN Zona z ON i.fk_zona_id = z.id_zona
JOIN Asignacion a
  ON a.fk_incidente_id = i.id_incidente AND a.timestamp_finalizacion IS NULL
WHERE i.descripcion LIKE 'SIM-08 incidente simultaneo #%'
GROUP BY i.id_incidente, i.descripcion, z.nombre
ORDER BY i.id_incidente;


-- Rebalanceo geografico (R15) en el log de auditoria

SELECT
    timestamp,
    trigger_disparador,
    detalle
FROM vHistorialTriggers
WHERE detalle::text LIKE '%Rebalanceo%'
   OR detalle::text LIKE '%rebalanceo%'
ORDER BY timestamp DESC
LIMIT 10;


-- Totales generales del lote

SELECT
    COUNT(*) AS total_incidentes,
    SUM(CASE WHEN ei.nombre = 'En proceso' THEN 1 ELSE 0 END) AS en_proceso,
    SUM(CASE WHEN ei.nombre = 'Pendiente' THEN 1 ELSE 0 END) AS pendientes,
    (SELECT COUNT(*) FROM Asignacion a
     JOIN Incidente i ON a.fk_incidente_id = i.id_incidente
     WHERE i.descripcion LIKE 'SIM-08 incidente simultaneo #%') AS total_asignaciones
FROM Incidente i
JOIN EstadoIncidente ei ON i.fk_estado_incidente_id = ei.id_estado_incidente
WHERE i.descripcion LIKE 'SIM-08 incidente simultaneo #%';
