-- =============================================================================
-- SIMULACION 03 - CASO INTERMEDIO: FALTA DE RECURSOS
-- =============================================================================
-- Demuestra que si no hay recursos compatibles disponibles para atender un nuevo
-- incidente, el incidente queda Pendiente y sin asignación.
--
-- Para que el escenario sea determinístico, dentro de la transacción se dejan
-- fuera de servicio todos los recursos compatibles con Emergencia médica salvo uno.
-- El primer incidente consume ese único recurso; el segundo queda en espera.
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
    v_disponible INT;
    v_fuera_servicio INT;
    v_recurso_unico INT;
    v_incidente_1 INT;
    v_incidente_2 INT;
    v_estado_1 TEXT;
    v_estado_2 TEXT;
    v_asig_1 INT;
    v_asig_2 INT;
BEGIN
    SELECT id_tipo_incidente INTO v_tipo_incidente FROM TipoIncidente WHERE nombre = 'Emergencia médica';
    SELECT id_gravedad INTO v_gravedad FROM Gravedad WHERE nombre = 'Baja';
    SELECT id_estado_incidente INTO v_pendiente FROM EstadoIncidente WHERE nombre = 'Pendiente';
    SELECT id_zona INTO v_zona FROM Zona WHERE nombre = 'Centro';
    SELECT id_estado_recurso INTO v_disponible FROM EstadoRecurso WHERE nombre = 'Disponible';
    SELECT id_estado_recurso INTO v_fuera_servicio FROM EstadoRecurso WHERE nombre = 'Fuera de servicio';

    SELECT r.id_recurso INTO v_recurso_unico
    FROM Recurso r
    JOIN ZonaRecurso zr ON zr.id_recurso = r.id_recurso AND zr.id_zona = v_zona
    JOIN TipoIncidenteTipoRecurso titr ON titr.fk_tipo_recurso_id = r.fk_tipo_recurso_id
    WHERE titr.fk_tipo_incidente_id = v_tipo_incidente
    ORDER BY r.id_recurso
    LIMIT 1;

    IF v_recurso_unico IS NULL THEN
        RAISE EXCEPTION 'SIM-03 precondición fallida: no hay recurso compatible para Emergencia médica en Centro.';
    END IF;

    UPDATE Recurso r
    SET fk_estado_recurso_id = v_fuera_servicio
    WHERE EXISTS (
        SELECT 1
        FROM TipoIncidenteTipoRecurso titr
        WHERE titr.fk_tipo_incidente_id = v_tipo_incidente
          AND titr.fk_tipo_recurso_id = r.fk_tipo_recurso_id
    );

    UPDATE Recurso
    SET fk_estado_recurso_id = v_disponible
    WHERE id_recurso = v_recurso_unico;

    INSERT INTO Incidente (
        fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id,
        fk_zona_id, fecha_hora_registro, descripcion, prioridad
    )
    VALUES (v_tipo_incidente, v_gravedad, v_pendiente, v_zona,
            CURRENT_TIMESTAMP - INTERVAL '20 minutes', 'SIM-03 consume unico recurso', 1)
    RETURNING id_incidente INTO v_incidente_1;

    INSERT INTO Incidente (
        fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id,
        fk_zona_id, descripcion, prioridad
    )
    VALUES (v_tipo_incidente, v_gravedad, v_pendiente, v_zona,
            'SIM-03 sin recurso disponible', 1)
    RETURNING id_incidente INTO v_incidente_2;

    SELECT COUNT(*) INTO v_asig_1 FROM Asignacion WHERE fk_incidente_id = v_incidente_1;
    SELECT COUNT(*) INTO v_asig_2 FROM Asignacion WHERE fk_incidente_id = v_incidente_2;

    SELECT ei.nombre INTO v_estado_1
    FROM Incidente i JOIN EstadoIncidente ei ON ei.id_estado_incidente = i.fk_estado_incidente_id
    WHERE i.id_incidente = v_incidente_1;

    SELECT ei.nombre INTO v_estado_2
    FROM Incidente i JOIN EstadoIncidente ei ON ei.id_estado_incidente = i.fk_estado_incidente_id
    WHERE i.id_incidente = v_incidente_2;

    IF v_asig_1 <> 1 OR v_estado_1 <> 'En proceso' THEN
        RAISE EXCEPTION 'SIM-03 fallo primer incidente: asignaciones %, estado %.', v_asig_1, v_estado_1;
    END IF;

    IF v_asig_2 <> 0 OR v_estado_2 <> 'Pendiente' THEN
        RAISE EXCEPTION 'SIM-03 fallo falta de recursos: asignaciones %, estado %.', v_asig_2, v_estado_2;
    END IF;

    RAISE NOTICE 'SIM-03 OK: primer incidente atendido; segundo queda Pendiente sin asignación por falta de recursos.';
END;
$$;

\echo 'SIM-03: evidencia final'
SELECT i.id_incidente, i.descripcion, ei.nombre AS estado_incidente, COUNT(a.id_asignacion) AS asignaciones
FROM Incidente i
JOIN EstadoIncidente ei ON ei.id_estado_incidente = i.fk_estado_incidente_id
LEFT JOIN Asignacion a ON a.fk_incidente_id = i.id_incidente
WHERE i.descripcion LIKE 'SIM-03%'
GROUP BY i.id_incidente, i.descripcion, ei.nombre
ORDER BY i.id_incidente;

ROLLBACK;
