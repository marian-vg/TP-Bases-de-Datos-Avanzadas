-- =============================================================================
-- SIMULACION 07 - CASO AVANZADO: RECURSOS BLOQUEADOS Y REBALANCEO
-- =============================================================================
-- Demuestra dos comportamientos ante recursos no disponibles:
--
--   A) Si no existe ningún recurso compatible disponible, el incidente queda
--      Pendiente y sin asignación. Además, una asignación manual a un recurso
--      Fuera de servicio debe ser rechazada.
--
--   B) Si la zona no tiene recursos propios disponibles, pero otra zona sí tiene
--      uno compatible, R15 debe habilitar/rebalancear un recurso ajeno, asignarlo
--      al incidente y registrar la decisión. Al finalizar la intervención, el
--      recurso vuelve a estado Disponible y su puntaje mejora por éxito.
--
-- Todo ocurre dentro de una transacción y se revierte con ROLLBACK.
-- =============================================================================

\set ON_ERROR_STOP on
BEGIN;

DELETE FROM Asignacion;
DELETE FROM Penalizacion;
DELETE FROM Incidente;
DELETE FROM Evento;
UPDATE Recurso
SET fk_estado_recurso_id = (SELECT id_estado_recurso FROM EstadoRecurso WHERE nombre = 'Disponible'),
    puntaje = 0
WHERE fk_estado_recurso_id <> (SELECT id_estado_recurso FROM EstadoRecurso WHERE nombre = 'Disponible')
   OR puntaje <> 0;
DELETE FROM Log;

-- -----------------------------------------------------------------------------
-- ESCENARIO A: todos los recursos compatibles están Fuera de servicio.
-- -----------------------------------------------------------------------------
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
    SELECT id_tipo_incidente INTO v_tipo_incidente FROM TipoIncidente WHERE nombre = 'Accidente de tránsito';
    SELECT id_gravedad INTO v_gravedad FROM Gravedad WHERE nombre = 'Baja';
    SELECT id_estado_incidente INTO v_pendiente FROM EstadoIncidente WHERE nombre = 'Pendiente';
    SELECT id_zona INTO v_zona FROM Zona WHERE nombre = 'Centro';
    SELECT id_estado_recurso INTO v_estado_fuera FROM EstadoRecurso WHERE nombre = 'Fuera de servicio';

    -- Bloqueamos TODOS los recursos compatibles para evitar que R15 pueda
    -- rebalancear desde otra zona en este primer escenario.
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
        RAISE EXCEPTION 'SIM-07A precondición fallida: no se pudo preparar un recurso Fuera de servicio compatible.';
    END IF;

    INSERT INTO Incidente (
        fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id,
        fk_zona_id, descripcion, prioridad
    )
    VALUES (
        v_tipo_incidente, v_gravedad, v_pendiente, v_zona,
        'SIM-07A incidente sin recursos disponibles', 1
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
        RAISE EXCEPTION 'SIM-07A fallo: se esperaban 0 asignaciones y estado Pendiente; hubo %, estado %.',
            v_asignaciones, v_estado_incidente;
    END IF;

    v_bloqueado := FALSE;
    BEGIN
        INSERT INTO Asignacion (fk_recurso_id, fk_incidente_id)
        VALUES (v_recurso_bloqueado, v_incidente);
    EXCEPTION WHEN OTHERS THEN
        v_bloqueado := TRUE;
        RAISE NOTICE 'SIM-07A: asignación manual rechazada correctamente: %', SQLERRM;
    END;

    IF NOT v_bloqueado THEN
        RAISE EXCEPTION 'SIM-07A fallo R8: se permitió asignar manualmente el recurso Fuera de servicio %.', v_recurso_bloqueado;
    END IF;

    -- Lo dejamos en evidencia, pero lo envejecemos para que no choque con R11
    -- cuando el escenario B inserte otro incidente del mismo tipo/zona.
    UPDATE Incidente
    SET fecha_hora_registro = CURRENT_TIMESTAMP - INTERVAL '20 minutes'
    WHERE id_incidente = v_incidente;

    RAISE NOTICE 'SIM-07A OK: sin recursos compatibles disponibles, el incidente queda Pendiente y sin asignación.';
END;
$$;

-- -----------------------------------------------------------------------------
-- ESCENARIO B: la zona pide un recurso ajeno por R15 y lo devuelve disponible.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_tipo_incidente INT;
    v_tipo_recurso INT;
    v_gravedad INT;
    v_pendiente INT;
    v_zona INT;
    v_estado_disponible INT;
    v_estado_fuera INT;
    v_incidente INT;
    v_asignacion INT;
    v_recurso INT;
    v_zona_base INT;
    v_puntaje_antes INT;
    v_puntaje_despues INT;
    v_estado_recurso TEXT;
    v_estado_incidente TEXT;
BEGIN
    SELECT id_tipo_incidente INTO v_tipo_incidente FROM TipoIncidente WHERE nombre = 'Accidente de tránsito';
    SELECT id_gravedad INTO v_gravedad FROM Gravedad WHERE nombre = 'Baja';
    SELECT id_estado_incidente INTO v_pendiente FROM EstadoIncidente WHERE nombre = 'Pendiente';
    SELECT id_zona INTO v_zona FROM Zona WHERE nombre = 'Centro';
    SELECT id_estado_recurso INTO v_estado_disponible FROM EstadoRecurso WHERE nombre = 'Disponible';
    SELECT id_estado_recurso INTO v_estado_fuera FROM EstadoRecurso WHERE nombre = 'Fuera de servicio';

    -- Restauramos disponibilidad después del escenario A; todo sigue dentro
    -- de la misma transacción y se revierte al final.
    UPDATE Recurso
    SET fk_estado_recurso_id = v_estado_disponible,
        puntaje = 0;

    -- Elegimos un tipo de recurso compatible que tenga al menos un candidato de
    -- otra zona todavía NO habilitado en Centro. Así forzamos R15 de verdad.
    SELECT titr.fk_tipo_recurso_id INTO v_tipo_recurso
    FROM TipoIncidenteTipoRecurso titr
    WHERE titr.fk_tipo_incidente_id = v_tipo_incidente
      AND EXISTS (
          SELECT 1
          FROM Recurso r
          WHERE r.fk_tipo_recurso_id = titr.fk_tipo_recurso_id
            AND r.fk_estado_recurso_id = v_estado_disponible
            AND r.fk_zona_base_id <> v_zona
            AND NOT EXISTS (
                SELECT 1
                FROM ZonaRecurso zr
                WHERE zr.id_recurso = r.id_recurso
                  AND zr.id_zona = v_zona
            )
      )
    ORDER BY titr.fk_tipo_recurso_id
    LIMIT 1;

    IF v_tipo_recurso IS NULL THEN
        RAISE EXCEPTION 'SIM-07B precondición fallida: no hay candidato externo para rebalancear hacia Centro.';
    END IF;

    -- Bloqueamos todos los recursos compatibles que ya están habilitados en
    -- Centro. Los candidatos externos quedan disponibles y R15 puede incorporar
    -- uno o más a ZonaRecurso.
    UPDATE Recurso r
    SET fk_estado_recurso_id = v_estado_fuera
    WHERE EXISTS (
          SELECT 1
          FROM ZonaRecurso zr
          JOIN TipoIncidenteTipoRecurso titr ON titr.fk_tipo_recurso_id = r.fk_tipo_recurso_id
          WHERE zr.id_recurso = r.id_recurso
            AND zr.id_zona = v_zona
            AND titr.fk_tipo_incidente_id = v_tipo_incidente
      );

    INSERT INTO Incidente (
        fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id,
        fk_zona_id, descripcion, prioridad
    )
    VALUES (
        v_tipo_incidente, v_gravedad, v_pendiente, v_zona,
        'SIM-07B incidente con recurso rebalanceado', 1
    )
    RETURNING id_incidente INTO v_incidente;

    SELECT a.id_asignacion, a.fk_recurso_id, r.fk_zona_base_id, r.puntaje
    INTO v_asignacion, v_recurso, v_zona_base, v_puntaje_antes
    FROM Asignacion a
    JOIN Recurso r ON r.id_recurso = a.fk_recurso_id
    WHERE a.fk_incidente_id = v_incidente
    LIMIT 1;

    IF v_asignacion IS NULL THEN
        RAISE EXCEPTION 'SIM-07B fallo R15/R1: no se asignó ningún recurso externo.';
    END IF;

    IF v_zona_base = v_zona THEN
        RAISE EXCEPTION 'SIM-07B fallo R15: se esperaba recurso ajeno a Centro, pero se asignó recurso base Centro (%).', v_recurso;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM ZonaRecurso WHERE id_zona = v_zona AND id_recurso = v_recurso
    ) THEN
        RAISE EXCEPTION 'SIM-07B fallo R15: el recurso % no quedó habilitado en ZonaRecurso para Centro.', v_recurso;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM Log
        WHERE trigger_disparador = 'R15'
          AND idTablaAfectada = v_recurso
          AND detalle->>'regla' = 'R15'
    ) THEN
        RAISE EXCEPTION 'SIM-07B fallo auditoría: no se registró decisión R15 para el recurso %.', v_recurso;
    END IF;

    UPDATE Asignacion
    SET timestamp_llegada = timestamp_asignacion + INTERVAL '1 minute',
        estado_exito = TRUE,
        timestamp_finalizacion = timestamp_asignacion + INTERVAL '2 minutes'
    WHERE id_asignacion = v_asignacion;

    SELECT er.nombre, r.puntaje
    INTO v_estado_recurso, v_puntaje_despues
    FROM Recurso r
    JOIN EstadoRecurso er ON er.id_estado_recurso = r.fk_estado_recurso_id
    WHERE r.id_recurso = v_recurso;

    SELECT ei.nombre INTO v_estado_incidente
    FROM Incidente i
    JOIN EstadoIncidente ei ON ei.id_estado_incidente = i.fk_estado_incidente_id
    WHERE i.id_incidente = v_incidente;

    IF v_estado_recurso <> 'Disponible' THEN
        RAISE EXCEPTION 'SIM-07B fallo devolución: el recurso % debía volver Disponible, quedó %.', v_recurso, v_estado_recurso;
    END IF;

    IF v_estado_incidente <> 'Resuelto' THEN
        RAISE EXCEPTION 'SIM-07B fallo cierre: el incidente debía quedar Resuelto, quedó %.', v_estado_incidente;
    END IF;

    IF v_puntaje_despues <= v_puntaje_antes THEN
        RAISE EXCEPTION 'SIM-07B fallo puntaje: recurso % debía mejorar puntaje; antes %, después %.', v_recurso, v_puntaje_antes, v_puntaje_despues;
    END IF;

    RAISE NOTICE 'SIM-07B OK: recurso ajeno % atendió, volvió Disponible y mejoró puntaje de % a %.',
        v_recurso, v_puntaje_antes, v_puntaje_despues;
END;
$$;

\echo 'SIM-07: evidencia escenario A'
SELECT i.id_incidente, i.descripcion, ei.nombre AS estado_incidente,
       COUNT(a.id_asignacion) AS asignaciones
FROM Incidente i
JOIN EstadoIncidente ei ON ei.id_estado_incidente = i.fk_estado_incidente_id
LEFT JOIN Asignacion a ON a.fk_incidente_id = i.id_incidente
WHERE i.descripcion LIKE 'SIM-07A%'
GROUP BY i.id_incidente, i.descripcion, ei.nombre;

\echo 'SIM-07: evidencia escenario B - recurso ajeno asignado, devuelto y puntuado'
SELECT i.id_incidente, i.descripcion, ei.nombre AS estado_incidente,
       a.id_asignacion, r.id_recurso, z_base.nombre AS zona_base_recurso,
       z_inc.nombre AS zona_incidente, er.nombre AS estado_recurso,
       0 AS puntaje_antes, r.puntaje AS puntaje_despues, r.puntaje - 0 AS diferencia_puntaje,
       a.timestamp_llegada, a.timestamp_finalizacion, a.estado_exito
FROM Incidente i
JOIN EstadoIncidente ei ON ei.id_estado_incidente = i.fk_estado_incidente_id
JOIN Zona z_inc ON z_inc.id_zona = i.fk_zona_id
JOIN Asignacion a ON a.fk_incidente_id = i.id_incidente
JOIN Recurso r ON r.id_recurso = a.fk_recurso_id
JOIN Zona z_base ON z_base.id_zona = r.fk_zona_base_id
JOIN EstadoRecurso er ON er.id_estado_recurso = r.fk_estado_recurso_id
WHERE i.descripcion = 'SIM-07B incidente con recurso rebalanceado';

\echo 'SIM-07: evidencia R15 en Log'
SELECT timestamp, operacion, trigger_disparador, idTablaAfectada, detalle
FROM Log
WHERE trigger_disparador = 'R15'
ORDER BY timestamp DESC
LIMIT 5;

ROLLBACK;
