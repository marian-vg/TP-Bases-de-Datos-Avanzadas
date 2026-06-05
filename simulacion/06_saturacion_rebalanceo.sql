\if :{?sim_verbose}
\echo '>>> 06 - SATURACION, REBALANCEO Y CAPACIDAD POR ZONA'
\endif

SELECT pg_temp.sim_reset_operativo();

DO $$
DECLARE
    v_pendiente INT := pg_temp.sim_id_catalogo('EstadoIncidente', 'id_estado_incidente', 'Pendiente');
    v_disponible INT := pg_temp.sim_id_catalogo('EstadoRecurso', 'id_estado_recurso', 'Disponible');
    v_fuera INT := pg_temp.sim_id_catalogo('EstadoRecurso', 'id_estado_recurso', 'Fuera de servicio');
    v_tipo INT := pg_temp.sim_id_catalogo('TipoIncidente', 'id_tipo_incidente', 'Accidente de tránsito');
    v_baja INT := pg_temp.sim_id_catalogo('Gravedad', 'id_gravedad', 'Baja');
    v_zona INT;
    v_incidente INT;
    v_asignacion INT;
    v_asignado INT;
    v_zona_base INT;
    v_puntaje_antes INT;
    v_puntaje_despues INT;
    v_estado_recurso TEXT;
    v_estado_incidente TEXT;
BEGIN
    SELECT z.id_zona INTO v_zona
    FROM Zona z
    WHERE EXISTS (
        SELECT 1
        FROM Recurso r
        JOIN ZonaRecurso zr ON zr.id_recurso = r.id_recurso AND zr.id_zona = z.id_zona
        JOIN TipoIncidenteTipoRecurso x
          ON x.fk_tipo_recurso_id = r.fk_tipo_recurso_id
         AND x.fk_tipo_incidente_id = v_tipo
    )
    AND EXISTS (
        SELECT 1
        FROM Recurso r
        JOIN TipoIncidenteTipoRecurso x
          ON x.fk_tipo_recurso_id = r.fk_tipo_recurso_id
         AND x.fk_tipo_incidente_id = v_tipo
        WHERE r.fk_zona_base_id <> z.id_zona
          AND r.fk_estado_recurso_id = v_disponible
          AND NOT EXISTS (
              SELECT 1 FROM ZonaRecurso zr
              WHERE zr.id_zona = z.id_zona AND zr.id_recurso = r.id_recurso
          )
    )
    ORDER BY z.id_zona
    LIMIT 1;

    IF v_zona IS NULL THEN
        PERFORM pg_temp.sim_registrar('06-SATURACION', 'R15 asignacion global', 'SKIP',
            'El dataset no ofrece una zona con candidato externo para rebalancear.');
        RETURN;
    END IF;

    UPDATE Recurso r
    SET fk_estado_recurso_id = v_fuera
    WHERE r.fk_estado_recurso_id = v_disponible
      AND EXISTS (
          SELECT 1 FROM ZonaRecurso zr
          WHERE zr.id_recurso = r.id_recurso AND zr.id_zona = v_zona
      )
      AND EXISTS (
          SELECT 1 FROM TipoIncidenteTipoRecurso x
          WHERE x.fk_tipo_recurso_id = r.fk_tipo_recurso_id
            AND x.fk_tipo_incidente_id = v_tipo
      );

    INSERT INTO Incidente (
        fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id,
        fk_zona_id, descripcion, prioridad
    )
    VALUES (v_tipo, v_baja, v_pendiente, v_zona, 'SIM-PRO-06 recurso externo', 0)
    RETURNING id_incidente INTO v_incidente;

    SELECT a.id_asignacion, a.fk_recurso_id, r.fk_zona_base_id, r.puntaje
    INTO v_asignacion, v_asignado, v_zona_base, v_puntaje_antes
    FROM Asignacion a
    JOIN Recurso r ON r.id_recurso = a.fk_recurso_id
    WHERE a.fk_incidente_id = v_incidente
    ORDER BY a.id_asignacion
    LIMIT 1;

    PERFORM pg_temp.sim_afirmar('06-SATURACION', 'R15 asignacion global',
        v_asignado IS NOT NULL AND v_zona_base <> v_zona,
        format('El recurso externo %s fue prestado desde otra zona.', v_asignado),
        'No se asigno un recurso externo luego de agotar la cobertura local.');
    PERFORM pg_temp.sim_afirmar('06-SATURACION', 'R15 compatibilidad global',
        v_asignado IS NOT NULL AND EXISTS (
            SELECT 1
            FROM Recurso r
            JOIN TipoIncidenteTipoRecurso x ON x.fk_tipo_recurso_id = r.fk_tipo_recurso_id
            WHERE r.id_recurso = v_asignado AND x.fk_tipo_incidente_id = v_tipo
        ), 'El recurso rebalanceado es compatible.', 'El recurso rebalanceado no es compatible.');
    PERFORM pg_temp.sim_afirmar('06-SATURACION', 'R15 habilitacion de zona',
        EXISTS (
            SELECT 1 FROM ZonaRecurso
            WHERE id_zona = v_zona AND id_recurso = v_asignado
        ), 'El recurso externo quedo habilitado en la zona.', 'No se creo la habilitacion de zona.');
    PERFORM pg_temp.sim_afirmar('06-SATURACION', 'R18 log de rebalanceo',
        EXISTS (
            SELECT 1 FROM Log
            WHERE trigger_disparador = 'R15'
              AND idTablaAfectada = v_asignado
              AND detalle->>'regla' = 'R15'
        ), 'La decision R15 quedo auditada.', 'No se encontro el log especifico de R15.');

    IF v_asignacion IS NOT NULL THEN
        UPDATE Asignacion
        SET timestamp_llegada = timestamp_asignacion + INTERVAL '1 minute',
            estado_exito = TRUE,
            timestamp_finalizacion = timestamp_asignacion + INTERVAL '3 minutes'
        WHERE id_asignacion = v_asignacion;

        SELECT er.nombre, r.puntaje INTO v_estado_recurso, v_puntaje_despues
        FROM Recurso r
        JOIN EstadoRecurso er ON er.id_estado_recurso = r.fk_estado_recurso_id
        WHERE r.id_recurso = v_asignado;
        SELECT ei.nombre INTO v_estado_incidente
        FROM Incidente i
        JOIN EstadoIncidente ei ON ei.id_estado_incidente = i.fk_estado_incidente_id
        WHERE i.id_incidente = v_incidente;

        PERFORM pg_temp.sim_afirmar('06-SATURACION', 'Ciclo del recurso rebalanceado',
            v_estado_recurso = 'Disponible'
            AND v_estado_incidente = 'Resuelto'
            AND v_puntaje_despues > v_puntaje_antes,
            'El recurso externo atendio, fue liberado y mejoro su puntaje.',
            format('Resultado inesperado: recurso %s, incidente %s, puntaje %s -> %s.',
                v_estado_recurso, v_estado_incidente, v_puntaje_antes, v_puntaje_despues));
    END IF;
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.sim_capturar_error('06-SATURACION', 'Rebalanceo geografico', SQLERRM);
END;
$$;

SELECT pg_temp.sim_reset_operativo();

DO $$
DECLARE
    v_pendiente INT := pg_temp.sim_id_catalogo('EstadoIncidente', 'id_estado_incidente', 'Pendiente');
    v_tipo INT := pg_temp.sim_id_catalogo('TipoIncidente', 'id_tipo_incidente', 'Accidente de tránsito');
    v_baja INT := pg_temp.sim_id_catalogo('Gravedad', 'id_gravedad', 'Baja');
    v_zona INT := (SELECT id_zona FROM Zona ORDER BY id_zona LIMIT 1);
    v_incidente INT;
    v_estado TEXT;
BEGIN
    UPDATE Zona SET umbral_incidentes_activos = 0 WHERE id_zona = v_zona;
    INSERT INTO Incidente (
        fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id,
        fk_zona_id, descripcion, prioridad
    )
    VALUES (v_tipo, v_baja, v_pendiente, v_zona, 'SIM-PRO-06 capacidad zonal agotada', 0)
    RETURNING id_incidente INTO v_incidente;

    SELECT ei.nombre INTO v_estado
    FROM Incidente i
    JOIN EstadoIncidente ei ON ei.id_estado_incidente = i.fk_estado_incidente_id
    WHERE i.id_incidente = v_incidente;

    PERFORM pg_temp.sim_afirmar('06-SATURACION', 'R20 capacidad por zona',
        v_estado = 'Pendiente'
        AND NOT EXISTS (SELECT 1 FROM Asignacion WHERE fk_incidente_id = v_incidente)
        AND EXISTS (
            SELECT 1 FROM Log
            WHERE trigger_disparador = 'R20'
              AND idTablaAfectada = v_incidente
        ),
        'La zona al limite dejo el incidente Pendiente y registro la decision R20.',
        'El control de capacidad por zona no produjo el resultado esperado.');
    PERFORM pg_temp.sim_afirmar('06-SATURACION', 'R20 criterio Pendiente',
        v_estado = 'Pendiente',
        'El control usa Pendiente como estado de espera operativa, segun decision de diseno.',
        format('Se esperaba Pendiente como espera operativa y se obtuvo %s.', v_estado));
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.sim_capturar_error('06-SATURACION', 'Control de capacidad por zona', SQLERRM);
END;
$$;
