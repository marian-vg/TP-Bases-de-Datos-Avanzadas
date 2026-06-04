-- =============================================================================
-- SIMULACION 07 - CASO AVANZADO: RECURSOS BLOQUEADOS / FUERA DE SERVICIO
-- =============================================================================
-- Demuestra cómo se comporta la base cuando una zona recibe un incidente pero
-- todos los recursos compatibles están bloqueados operativamente, es decir,
-- en estado "Fuera de servicio".
--
-- La simulación valida dos cosas:
--   1) la asignación automática no debe usar recursos Fuera de servicio;
--   2) una asignación manual a un recurso Fuera de servicio debe ser rechazada.
--
-- No prueba bloqueo por puntaje acumulado porque eso no forma parte explícita
-- del modelo acordado para esta simulación.
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
    v_tipo_incidente INT;
    v_gravedad INT;
    v_pendiente INT;
    v_zona INT;
    v_estado_fuera INT;
    v_incidente INT;
    v_recurso_bloqueado INT;
    v_estado_incidente TEXT;
    v_asignaciones INT;
    v_bloqueado BOOLEAN;
BEGIN
    SELECT id_tipo_incidente INTO v_tipo_incidente FROM TipoIncidente WHERE nombre = 'Emergencia médica';
    SELECT id_gravedad INTO v_gravedad FROM Gravedad WHERE nombre = 'Baja';
    SELECT id_estado_incidente INTO v_pendiente FROM EstadoIncidente WHERE nombre = 'Pendiente';
    SELECT id_zona INTO v_zona FROM Zona WHERE nombre = 'Centro';
    SELECT id_estado_recurso INTO v_estado_fuera FROM EstadoRecurso WHERE nombre = 'Fuera de servicio';

    -- Dejamos fuera de servicio todos los recursos compatibles con el tipo de
    -- incidente, no solo los de la zona. Esto evita que R15 rebalancee un
    -- recurso equivalente desde otra zona y vuelva no determinístico el caso.
    -- El UPDATE es transaccional y se revierte.
    UPDATE Recurso r
    SET fk_estado_recurso_id = v_estado_fuera
    WHERE EXISTS (
        SELECT 1
        FROM TipoIncidenteTipoRecurso titr
        WHERE titr.fk_tipo_recurso_id = r.fk_tipo_recurso_id
          AND titr.fk_tipo_incidente_id = v_tipo_incidente
    );

    SELECT r.id_recurso INTO v_recurso_bloqueado
    FROM Recurso r
    JOIN ZonaRecurso zr ON zr.id_recurso = r.id_recurso AND zr.id_zona = v_zona
    JOIN TipoIncidenteTipoRecurso titr ON titr.fk_tipo_recurso_id = r.fk_tipo_recurso_id
    WHERE titr.fk_tipo_incidente_id = v_tipo_incidente
      AND r.fk_estado_recurso_id = v_estado_fuera
    ORDER BY r.id_recurso
    LIMIT 1;

    IF v_recurso_bloqueado IS NULL THEN
        RAISE EXCEPTION 'SIM-07 precondición fallida: no se pudo preparar un recurso Fuera de servicio compatible.';
    END IF;

    INSERT INTO Incidente (
        fk_tipo_incidente_id,
        fk_gravedad_id,
        fk_estado_incidente_id,
        fk_zona_id,
        descripcion,
        prioridad
    )
    VALUES (
        v_tipo_incidente,
        v_gravedad,
        v_pendiente,
        v_zona,
        'SIM-07 incidente con recursos bloqueados',
        1
    )
    RETURNING id_incidente INTO v_incidente;

    SELECT COUNT(*) INTO v_asignaciones
    FROM Asignacion
    WHERE fk_incidente_id = v_incidente;

    SELECT ei.nombre INTO v_estado_incidente
    FROM Incidente i
    JOIN EstadoIncidente ei ON ei.id_estado_incidente = i.fk_estado_incidente_id
    WHERE i.id_incidente = v_incidente;

    IF v_asignaciones <> 0 OR v_estado_incidente <> 'Pendiente' THEN
        RAISE EXCEPTION 'SIM-07 fallo: con recursos Fuera de servicio se esperaban 0 asignaciones y estado Pendiente; hubo %, estado %.',
            v_asignaciones, v_estado_incidente;
    END IF;

    -- Además validamos que tampoco se pueda forzar una asignación manual al
    -- recurso bloqueado. La regla validadora debe rechazarla.
    v_bloqueado := FALSE;
    BEGIN
        INSERT INTO Asignacion (fk_recurso_id, fk_incidente_id)
        VALUES (v_recurso_bloqueado, v_incidente);
    EXCEPTION WHEN OTHERS THEN
        v_bloqueado := TRUE;
        RAISE NOTICE 'SIM-07: asignación manual rechazada correctamente: %', SQLERRM;
    END;

    IF NOT v_bloqueado THEN
        RAISE EXCEPTION 'SIM-07 fallo R8: se permitió asignar manualmente el recurso Fuera de servicio %.', v_recurso_bloqueado;
    END IF;

    RAISE NOTICE 'SIM-07 OK: el incidente quedó Pendiente sin asignación y el recurso Fuera de servicio no pudo asignarse manualmente.';
END;
$$;

\echo 'SIM-07: evidencia final'
SELECT i.id_incidente, i.descripcion, ei.nombre AS estado_incidente,
       COUNT(a.id_asignacion) AS asignaciones
FROM Incidente i
JOIN EstadoIncidente ei ON ei.id_estado_incidente = i.fk_estado_incidente_id
LEFT JOIN Asignacion a ON a.fk_incidente_id = i.id_incidente
WHERE i.descripcion = 'SIM-07 incidente con recursos bloqueados'
GROUP BY i.id_incidente, i.descripcion, ei.nombre;

SELECT r.id_recurso, tr.nombre AS tipo_recurso, er.nombre AS estado_recurso
FROM Recurso r
JOIN TipoRecurso tr ON tr.id_tipo_recurso = r.fk_tipo_recurso_id
JOIN EstadoRecurso er ON er.id_estado_recurso = r.fk_estado_recurso_id
JOIN ZonaRecurso zr ON zr.id_recurso = r.id_recurso
JOIN TipoIncidenteTipoRecurso titr ON titr.fk_tipo_recurso_id = r.fk_tipo_recurso_id
JOIN TipoIncidente ti ON ti.id_tipo_incidente = titr.fk_tipo_incidente_id
JOIN Zona z ON z.id_zona = zr.id_zona
WHERE ti.nombre = 'Emergencia médica'
  AND z.nombre = 'Centro'
  AND er.nombre = 'Fuera de servicio'
ORDER BY r.id_recurso
LIMIT 10;

ROLLBACK;
