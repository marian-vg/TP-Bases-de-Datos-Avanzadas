-- =============================================================================
-- SIMULACION 05 - CASO AVANZADO: ESCALAMIENTO AUTOMATICO POR SLA
-- =============================================================================
-- Demuestra que un incidente activo que supera su SLA pasa a Escalado al ejecutar
-- el procedimiento temporal sp_EscalarIncidente().
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
    v_estado TEXT;
    v_gravedad TEXT;
BEGIN
    INSERT INTO Incidente (
        fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id,
        fk_zona_id, descripcion, prioridad
    )
    SELECT ti.id_tipo_incidente, g.id_gravedad, ei.id_estado_incidente,
           z.id_zona, 'SIM-05 escalamiento SLA', 1
    FROM TipoIncidente ti, Gravedad g, EstadoIncidente ei, Zona z
    WHERE ti.nombre = 'Accidente de tránsito'
      AND g.nombre = 'Alta'
      AND ei.nombre = 'Pendiente'
      AND z.nombre = 'Centro'
    RETURNING id_incidente INTO v_incidente;

    IF NOT EXISTS (SELECT 1 FROM Asignacion WHERE fk_incidente_id = v_incidente AND timestamp_finalizacion IS NULL) THEN
        RAISE EXCEPTION 'SIM-05 precondición fallida: el incidente no quedó activo con asignación.';
    END IF;

    UPDATE Incidente
    SET fecha_hora_registro = CURRENT_TIMESTAMP - INTERVAL '20 minutes'
    WHERE id_incidente = v_incidente;

    CALL sp_EscalarIncidente();

    SELECT ei.nombre, g.nombre INTO v_estado, v_gravedad
    FROM Incidente i
    JOIN EstadoIncidente ei ON ei.id_estado_incidente = i.fk_estado_incidente_id
    JOIN Gravedad g ON g.id_gravedad = i.fk_gravedad_id
    WHERE i.id_incidente = v_incidente;

    IF v_estado <> 'Escalado' THEN
        RAISE EXCEPTION 'SIM-05 fallo R16: el incidente debía quedar Escalado, quedó %.', v_estado;
    END IF;

    IF v_gravedad <> 'Crítica' THEN
        RAISE EXCEPTION 'SIM-05 fallo P2: la gravedad debía subir de Alta a Crítica, quedó %.', v_gravedad;
    END IF;

    RAISE NOTICE 'SIM-05 OK: incidente % escalado por SLA y gravedad incrementada.', v_incidente;
END;
$$;

\echo 'SIM-05: evidencia final'
SELECT i.id_incidente, i.descripcion, ei.nombre AS estado_incidente, g.nombre AS gravedad,
       ROUND(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - i.fecha_hora_registro)) / 60) AS minutos_transcurridos
FROM Incidente i
JOIN EstadoIncidente ei ON ei.id_estado_incidente = i.fk_estado_incidente_id
JOIN Gravedad g ON g.id_gravedad = i.fk_gravedad_id
WHERE i.descripcion = 'SIM-05 escalamiento SLA';

ROLLBACK;
