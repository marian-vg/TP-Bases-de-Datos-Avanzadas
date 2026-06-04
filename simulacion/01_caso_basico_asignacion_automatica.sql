-- =============================================================================
-- SIMULACION 01 - CASO BASICO: ASIGNACION AUTOMATICA
-- =============================================================================
-- Demuestra que al insertar un incidente Pendiente, los triggers:
--   1) crean una asignación automática;
--   2) pasan el incidente a "En proceso";
--   3) marcan el recurso asignado como "Ocupado".
-- =============================================================================

\set ON_ERROR_STOP on
BEGIN;

DELETE FROM Asignacion;
DELETE FROM Penalizacion;
DELETE FROM Incidente;
DELETE FROM Evento;
UPDATE Recurso
SET fk_estado_recurso_id = (SELECT id_estado_recurso FROM EstadoRecurso WHERE nombre = 'Disponible')
WHERE fk_estado_recurso_id <> (SELECT id_estado_recurso FROM EstadoRecurso WHERE nombre = 'Disponible');
DELETE FROM Log;

\echo 'SIM-01: recursos candidatos antes de insertar el incidente'
SELECT r.id_recurso, tr.nombre AS tipo_recurso, er.nombre AS estado
FROM Recurso r
JOIN EstadoRecurso er ON er.id_estado_recurso = r.fk_estado_recurso_id
JOIN TipoRecurso tr ON tr.id_tipo_recurso = r.fk_tipo_recurso_id
JOIN ZonaRecurso zr ON zr.id_recurso = r.id_recurso
JOIN TipoIncidenteTipoRecurso titr ON titr.fk_tipo_recurso_id = r.fk_tipo_recurso_id
JOIN TipoIncidente ti ON ti.id_tipo_incidente = titr.fk_tipo_incidente_id
JOIN Zona z ON z.id_zona = zr.id_zona
WHERE er.nombre = 'Disponible'
  AND ti.nombre = 'Emergencia médica'
  AND z.nombre = 'Centro'
ORDER BY r.id_recurso
LIMIT 10;

DO $$
DECLARE
    v_incidente INT;
    v_asignaciones INT;
    v_ocupados INT;
    v_estado_incidente TEXT;
BEGIN
    INSERT INTO Incidente (
        fk_tipo_incidente_id,
        fk_gravedad_id,
        fk_estado_incidente_id,
        fk_zona_id,
        descripcion,
        prioridad
    )
    SELECT ti.id_tipo_incidente, g.id_gravedad, ei.id_estado_incidente,
           z.id_zona, 'SIM-01 emergencia medica', 1
    FROM TipoIncidente ti, Gravedad g, EstadoIncidente ei, Zona z
    WHERE ti.nombre = 'Emergencia médica'
      AND g.nombre = 'Baja'
      AND ei.nombre = 'Pendiente'
      AND z.nombre = 'Centro'
    RETURNING id_incidente INTO v_incidente;

    SELECT COUNT(*) INTO v_asignaciones
    FROM Asignacion
    WHERE fk_incidente_id = v_incidente
      AND timestamp_finalizacion IS NULL;

    IF v_asignaciones <> 1 THEN
        RAISE EXCEPTION 'SIM-01 fallo R1/R5: se esperaba 1 asignación abierta, se obtuvieron %.', v_asignaciones;
    END IF;

    SELECT ei.nombre INTO v_estado_incidente
    FROM Incidente i
    JOIN EstadoIncidente ei ON ei.id_estado_incidente = i.fk_estado_incidente_id
    WHERE i.id_incidente = v_incidente;

    IF v_estado_incidente <> 'En proceso' THEN
        RAISE EXCEPTION 'SIM-01 fallo R2: el incidente debía quedar En proceso, quedó %.', v_estado_incidente;
    END IF;

    SELECT COUNT(*) INTO v_ocupados
    FROM Asignacion a
    JOIN Recurso r ON r.id_recurso = a.fk_recurso_id
    JOIN EstadoRecurso er ON er.id_estado_recurso = r.fk_estado_recurso_id
    WHERE a.fk_incidente_id = v_incidente
      AND er.nombre = 'Ocupado';

    IF v_ocupados <> 1 THEN
        RAISE EXCEPTION 'SIM-01 fallo R8: el recurso asignado debía quedar Ocupado, ocupados %.', v_ocupados;
    END IF;

    RAISE NOTICE 'SIM-01 OK: incidente %, 1 asignación automática, estado En proceso y recurso Ocupado.', v_incidente;
END;
$$;

\echo 'SIM-01: evidencia final'
SELECT i.id_incidente, ti.nombre AS tipo_incidente, g.nombre AS gravedad,
       ei.nombre AS estado_incidente, z.nombre AS zona, i.descripcion
FROM Incidente i
JOIN TipoIncidente ti ON ti.id_tipo_incidente = i.fk_tipo_incidente_id
JOIN Gravedad g ON g.id_gravedad = i.fk_gravedad_id
JOIN EstadoIncidente ei ON ei.id_estado_incidente = i.fk_estado_incidente_id
JOIN Zona z ON z.id_zona = i.fk_zona_id
WHERE i.descripcion = 'SIM-01 emergencia medica';

SELECT a.id_asignacion, a.fk_recurso_id, tr.nombre AS tipo_recurso, er.nombre AS estado_recurso
FROM Asignacion a
JOIN Incidente i ON i.id_incidente = a.fk_incidente_id
JOIN Recurso r ON r.id_recurso = a.fk_recurso_id
JOIN TipoRecurso tr ON tr.id_tipo_recurso = r.fk_tipo_recurso_id
JOIN EstadoRecurso er ON er.id_estado_recurso = r.fk_estado_recurso_id
WHERE i.descripcion = 'SIM-01 emergencia medica';

ROLLBACK;
