-- =============================================================================
-- SIMULACION 06 - CASO AVANZADO: PENALIZACIONES POR DEMORA
-- =============================================================================
-- Demuestra la regla pendiente de penalización automática por demora:
-- si un recurso llega después del SLA del incidente, debe registrarse una
-- penalización de demora para ese recurso.
--
-- Este script NO implementa la regla. Queda preparado para fallar hasta que la
-- regla activa sea agregada a la base.
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
    v_penalizaciones INT;
BEGIN
    INSERT INTO Incidente (
        fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id,
        fk_zona_id, descripcion, prioridad
    )
    SELECT ti.id_tipo_incidente, g.id_gravedad, ei.id_estado_incidente,
           z.id_zona, 'SIM-06 penalizacion por demora', 1
    FROM TipoIncidente ti, Gravedad g, EstadoIncidente ei, Zona z
    WHERE ti.nombre = 'Emergencia médica'
      AND g.nombre = 'Baja'
      AND ei.nombre = 'Pendiente'
      AND z.nombre = 'Centro'
    RETURNING id_incidente INTO v_incidente;

    SELECT id_asignacion, fk_recurso_id
    INTO v_asignacion, v_recurso
    FROM Asignacion
    WHERE fk_incidente_id = v_incidente
    LIMIT 1;

    IF v_asignacion IS NULL THEN
        RAISE EXCEPTION 'SIM-06 precondición fallida: no se creó asignación automática.';
    END IF;

    UPDATE Asignacion
    SET timestamp_llegada = timestamp_asignacion + INTERVAL '90 minutes'
    WHERE id_asignacion = v_asignacion;

    SELECT COUNT(*) INTO v_penalizaciones
    FROM Penalizacion p
    JOIN TipoPenalizacion tp ON tp.id_tipo_penalizacion = p.fk_tipo_penalizacion_id
    WHERE p.fk_recurso_id = v_recurso
      AND (tp.nombre ILIKE 'Demora%' OR p.motivo ILIKE '%demora%');

    IF v_penalizaciones < 1 THEN
        RAISE EXCEPTION 'SIM-06 regla pendiente: la llegada tarde no generó penalización de demora para el recurso %.', v_recurso;
    END IF;

    RAISE NOTICE 'SIM-06 OK: llegada tarde generó % penalización(es) de demora para el recurso %.', v_penalizaciones, v_recurso;
END;
$$;

\echo 'SIM-06: evidencia final'
SELECT p.id_penalizacion, p.fk_recurso_id, tp.nombre AS tipo_penalizacion, tp.puntaje, p.motivo
FROM Penalizacion p
JOIN TipoPenalizacion tp ON tp.id_tipo_penalizacion = p.fk_tipo_penalizacion_id
WHERE p.motivo ILIKE '%demora%' OR tp.nombre ILIKE 'Demora%'
ORDER BY p.id_penalizacion;

ROLLBACK;
