-- =============================================================================
-- SIMULACION 02 - CASO BASICO: CAMBIO DE ESTADOS
-- =============================================================================
-- Demuestra el ciclo operativo de una asignación:
--   1) asignación automática: incidente En proceso y recurso Ocupado;
--   2) llegada al lugar: se registra timestamp_llegada;
--   3) cierre exitoso: incidente Resuelto y recurso Disponible.
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

DO $$
DECLARE
    v_incidente INT;
    v_asignacion INT;
    v_recurso INT;
    v_estado_incidente TEXT;
    v_estado_recurso TEXT;
    v_llegada TIMESTAMP;
BEGIN
    INSERT INTO Incidente (
        fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id,
        fk_zona_id, descripcion, prioridad
    )
    SELECT ti.id_tipo_incidente, g.id_gravedad, ei.id_estado_incidente,
           z.id_zona, 'SIM-02 ciclo estados', 1
    FROM TipoIncidente ti, Gravedad g, EstadoIncidente ei, Zona z
    WHERE ti.nombre = 'Emergencia médica'
      AND g.nombre = 'Baja'
      AND ei.nombre = 'Pendiente'
      AND z.nombre = 'Centro'
    RETURNING id_incidente INTO v_incidente;

    SELECT a.id_asignacion, a.fk_recurso_id
    INTO v_asignacion, v_recurso
    FROM Asignacion a
    WHERE a.fk_incidente_id = v_incidente;

    IF v_asignacion IS NULL THEN
        RAISE EXCEPTION 'SIM-02 fallo: no se creó asignación automática.';
    END IF;

    SELECT ei.nombre, er.nombre
    INTO v_estado_incidente, v_estado_recurso
    FROM Incidente i
    JOIN EstadoIncidente ei ON ei.id_estado_incidente = i.fk_estado_incidente_id
    JOIN Recurso r ON r.id_recurso = v_recurso
    JOIN EstadoRecurso er ON er.id_estado_recurso = r.fk_estado_recurso_id
    WHERE i.id_incidente = v_incidente;

    IF v_estado_incidente <> 'En proceso' OR v_estado_recurso <> 'Ocupado' THEN
        RAISE EXCEPTION 'SIM-02 fallo inicial: incidente %, recurso %.', v_estado_incidente, v_estado_recurso;
    END IF;

    UPDATE Asignacion
    SET timestamp_llegada = CURRENT_TIMESTAMP
    WHERE id_asignacion = v_asignacion;

    SELECT timestamp_llegada INTO v_llegada
    FROM Asignacion
    WHERE id_asignacion = v_asignacion;

    IF v_llegada IS NULL THEN
        RAISE EXCEPTION 'SIM-02 fallo llegada: timestamp_llegada quedó NULL.';
    END IF;

    UPDATE Asignacion
    SET estado_exito = TRUE,
        timestamp_finalizacion = CURRENT_TIMESTAMP
    WHERE id_asignacion = v_asignacion;

    SELECT ei.nombre, er.nombre
    INTO v_estado_incidente, v_estado_recurso
    FROM Incidente i
    JOIN EstadoIncidente ei ON ei.id_estado_incidente = i.fk_estado_incidente_id
    JOIN Recurso r ON r.id_recurso = v_recurso
    JOIN EstadoRecurso er ON er.id_estado_recurso = r.fk_estado_recurso_id
    WHERE i.id_incidente = v_incidente;

    IF v_estado_incidente <> 'Resuelto' OR v_estado_recurso <> 'Disponible' THEN
        RAISE EXCEPTION 'SIM-02 fallo cierre: incidente %, recurso %.', v_estado_incidente, v_estado_recurso;
    END IF;

    RAISE NOTICE 'SIM-02 OK: asignación %, recurso %, incidente Resuelto y recurso Disponible.', v_asignacion, v_recurso;
END;
$$;

\echo 'SIM-02: evidencia final'
SELECT i.descripcion, ei.nombre AS estado_incidente, er.nombre AS estado_recurso,
       a.timestamp_llegada, a.timestamp_finalizacion, a.estado_exito
FROM Incidente i
JOIN EstadoIncidente ei ON ei.id_estado_incidente = i.fk_estado_incidente_id
JOIN Asignacion a ON a.fk_incidente_id = i.id_incidente
JOIN Recurso r ON r.id_recurso = a.fk_recurso_id
JOIN EstadoRecurso er ON er.id_estado_recurso = r.fk_estado_recurso_id
WHERE i.descripcion = 'SIM-02 ciclo estados';

ROLLBACK;
