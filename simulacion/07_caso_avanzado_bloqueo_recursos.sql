-- =============================================================================
-- SIMULACION 07 - CASO AVANZADO: BLOQUEO POR PENALIZACIONES
-- =============================================================================
-- Demuestra la regla pendiente de bloqueo automático:
-- si un recurso supera PUNTAJE_BLOQUEO_RECURSO por penalizaciones acumuladas,
-- debe pasar a estado "Fuera de servicio".
--
-- Este script NO implementa la regla. Calcula dinámicamente cuántas penalizaciones
-- hacen falta según los puntajes reales del catálogo.
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
    v_recurso INT;
    v_tipo_penalizacion INT;
    v_puntaje_penalizacion INT;
    v_umbral NUMERIC;
    v_necesarias INT;
    v_puntos INT;
    v_estado TEXT;
BEGIN
    SELECT id_recurso INTO v_recurso
    FROM Recurso r
    JOIN EstadoRecurso er ON er.id_estado_recurso = r.fk_estado_recurso_id
    WHERE er.nombre = 'Disponible'
    ORDER BY r.id_recurso
    LIMIT 1;

    SELECT id_tipo_penalizacion, puntaje
    INTO v_tipo_penalizacion, v_puntaje_penalizacion
    FROM TipoPenalizacion
    ORDER BY puntaje DESC, id_tipo_penalizacion
    LIMIT 1;

    SELECT numero INTO v_umbral
    FROM ParametrosSistema
    WHERE nombre_parametro = 'PUNTAJE_BLOQUEO_RECURSO';

    IF v_recurso IS NULL OR v_tipo_penalizacion IS NULL OR COALESCE(v_puntaje_penalizacion, 0) <= 0 THEN
        RAISE EXCEPTION 'SIM-07 precondición fallida: recurso o tipo de penalización inválido.';
    END IF;

    v_umbral := COALESCE(v_umbral, 75);
    v_necesarias := floor(v_umbral / v_puntaje_penalizacion)::INT + 1;

    INSERT INTO Penalizacion (fk_recurso_id, fk_tipo_penalizacion_id, motivo)
    SELECT v_recurso, v_tipo_penalizacion, 'SIM-07 penalizacion acumulada #' || s
    FROM generate_series(1, v_necesarias) AS s;

    SELECT COALESCE(SUM(tp.puntaje), 0) INTO v_puntos
    FROM Penalizacion p
    JOIN TipoPenalizacion tp ON tp.id_tipo_penalizacion = p.fk_tipo_penalizacion_id
    WHERE p.fk_recurso_id = v_recurso;

    SELECT er.nombre INTO v_estado
    FROM Recurso r
    JOIN EstadoRecurso er ON er.id_estado_recurso = r.fk_estado_recurso_id
    WHERE r.id_recurso = v_recurso;

    IF v_puntos <= v_umbral THEN
        RAISE EXCEPTION 'SIM-07 fallo de preparación: puntos % no superan umbral %.', v_puntos, v_umbral;
    END IF;

    IF v_estado <> 'Fuera de servicio' THEN
        RAISE EXCEPTION 'SIM-07 regla pendiente: recurso % acumuló % puntos (> %) pero quedó en estado %.', v_recurso, v_puntos, v_umbral, v_estado;
    END IF;

    RAISE NOTICE 'SIM-07 OK: recurso % bloqueado con % puntos acumulados.', v_recurso, v_puntos;
END;
$$;

\echo 'SIM-07: evidencia final'
SELECT r.id_recurso, tr.nombre AS tipo_recurso, er.nombre AS estado_recurso,
       COALESCE(SUM(tp.puntaje), 0) AS puntos_acumulados
FROM Recurso r
JOIN TipoRecurso tr ON tr.id_tipo_recurso = r.fk_tipo_recurso_id
JOIN EstadoRecurso er ON er.id_estado_recurso = r.fk_estado_recurso_id
LEFT JOIN Penalizacion p ON p.fk_recurso_id = r.id_recurso
LEFT JOIN TipoPenalizacion tp ON tp.id_tipo_penalizacion = p.fk_tipo_penalizacion_id
WHERE p.motivo LIKE 'SIM-07%'
GROUP BY r.id_recurso, tr.nombre, er.nombre
ORDER BY r.id_recurso;

ROLLBACK;
