\echo '>>> 07 - CAPACIDADES TEMPORALES, PENALIZACION Y BRECHAS'

SELECT pg_temp.sim_reset_operativo();

DO $$
DECLARE
    v_pendiente INT := pg_temp.sim_id_catalogo('EstadoIncidente', 'id_estado_incidente', 'Pendiente');
    v_tipo INT := pg_temp.sim_id_catalogo('TipoIncidente', 'id_tipo_incidente', 'Accidente de tránsito');
    v_alta INT := pg_temp.sim_id_catalogo('Gravedad', 'id_gravedad', 'Alta');
    v_zona INT;
    v_incidente INT;
    v_estado TEXT;
    v_gravedad TEXT;
BEGIN
    SELECT zr.id_zona INTO v_zona
    FROM ZonaRecurso zr
    JOIN Recurso r ON r.id_recurso = zr.id_recurso
    JOIN TipoIncidenteTipoRecurso x ON x.fk_tipo_recurso_id = r.fk_tipo_recurso_id
    WHERE x.fk_tipo_incidente_id = v_tipo
    ORDER BY zr.id_zona
    LIMIT 1;

    INSERT INTO Incidente (
        fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id,
        fk_zona_id, descripcion, prioridad
    )
    VALUES (v_tipo, v_alta, v_pendiente, v_zona, 'SIM-PRO-07 escalamiento SLA', 0)
    RETURNING id_incidente INTO v_incidente;

    UPDATE Incidente
    SET fecha_hora_registro = CURRENT_TIMESTAMP - INTERVAL '20 minutes'
    WHERE id_incidente = v_incidente;

    CALL sp_EscalarIncidente();

    SELECT ei.nombre, g.nombre INTO v_estado, v_gravedad
    FROM Incidente i
    JOIN EstadoIncidente ei ON ei.id_estado_incidente = i.fk_estado_incidente_id
    JOIN Gravedad g ON g.id_gravedad = i.fk_gravedad_id
    WHERE i.id_incidente = v_incidente;

    PERFORM pg_temp.sim_afirmar('07-AVANZADAS', 'R16 escalamiento por SLA',
        v_estado = 'Escalado',
        'El incidente fuera de SLA paso a Escalado.',
        format('El incidente quedo en estado %s.', v_estado));
    PERFORM pg_temp.sim_afirmar('07-AVANZADAS', 'P2 incremento de gravedad',
        v_gravedad = 'Crítica',
        'P2 incremento la gravedad de Alta a Critica.',
        format('La gravedad final fue %s.', v_gravedad));
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.sim_capturar_error('07-AVANZADAS', 'Escalamiento temporal', SQLERRM);
END;
$$;

SELECT pg_temp.sim_reset_operativo();

DO $$
DECLARE
    v_recurso INT := (SELECT id_recurso FROM Recurso ORDER BY id_recurso LIMIT 1);
    v_fuera INT := pg_temp.sim_id_catalogo('EstadoRecurso', 'id_estado_recurso', 'Fuera de servicio');
    v_estado TEXT;
    v_minutos NUMERIC;
BEGIN
    SELECT numero INTO v_minutos
    FROM ParametrosSistema
    WHERE nombre_parametro = 'MINUTOS_REACTIVACION_RECURSO';

    UPDATE Recurso SET fk_estado_recurso_id = v_fuera WHERE id_recurso = v_recurso;
    UPDATE Log
    SET timestamp = CURRENT_TIMESTAMP - ((v_minutos + 1) * INTERVAL '1 minute')
    WHERE lower(tablaAfectada) = 'recurso'
      AND idTablaAfectada = v_recurso
      AND operacion = 'UPDATE'
      AND (detalle->'despues'->>'fk_estado_recurso_id')::int = v_fuera;

    CALL sp_ReactivarRecursos();

    SELECT er.nombre INTO v_estado
    FROM Recurso r
    JOIN EstadoRecurso er ON er.id_estado_recurso = r.fk_estado_recurso_id
    WHERE r.id_recurso = v_recurso;

    PERFORM pg_temp.sim_afirmar('07-AVANZADAS', 'R17 reactivacion temporal',
        v_estado = 'Disponible',
        'El recurso fue reactivado luego del tiempo configurado.',
        format('El recurso quedo en estado %s.', v_estado));
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.sim_capturar_error('07-AVANZADAS', 'Reactivacion temporal', SQLERRM);
END;
$$;

SELECT pg_temp.sim_reset_operativo();

DO $$
DECLARE
    v_pendiente INT := pg_temp.sim_id_catalogo('EstadoIncidente', 'id_estado_incidente', 'Pendiente');
    v_ocupado INT := pg_temp.sim_id_catalogo('EstadoRecurso', 'id_estado_recurso', 'Ocupado');
    v_tipo INT := pg_temp.sim_id_catalogo('TipoIncidente', 'id_tipo_incidente', 'Emergencia médica');
    v_baja INT := pg_temp.sim_id_catalogo('Gravedad', 'id_gravedad', 'Baja');
    v_zona INT;
    v_incidente INT;
    v_asignacion INT;
    v_recurso INT;
    v_sla INT;
    v_tramo INT;
    v_puntos_esperados INT := 3;
    v_puntos_obtenidos INT;
    v_puntaje_antes INT;
    v_puntaje_despues INT;
    v_llegada TIMESTAMP;
BEGIN
    SELECT zr.id_zona INTO v_zona
    FROM ZonaRecurso zr
    JOIN Recurso r ON r.id_recurso = zr.id_recurso
    JOIN TipoIncidenteTipoRecurso x ON x.fk_tipo_recurso_id = r.fk_tipo_recurso_id
    WHERE x.fk_tipo_incidente_id = v_tipo
    ORDER BY zr.id_zona
    LIMIT 1;

    INSERT INTO Incidente (
        fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id,
        fk_zona_id, descripcion, prioridad
    )
    VALUES (v_tipo, v_baja, v_pendiente, v_zona, 'SIM-PRO-07 arribo y demora proporcional', 0)
    RETURNING id_incidente INTO v_incidente;

    SELECT a.id_asignacion, a.fk_recurso_id, r.puntaje
    INTO v_asignacion, v_recurso, v_puntaje_antes
    FROM Asignacion a
    JOIN Recurso r ON r.id_recurso = a.fk_recurso_id
    WHERE a.fk_incidente_id = v_incidente
    ORDER BY a.id_asignacion
    LIMIT 1;

    UPDATE Recurso SET fk_estado_recurso_id = v_ocupado WHERE id_recurso = v_recurso;
    SELECT timestamp_llegada INTO v_llegada FROM Asignacion WHERE id_asignacion = v_asignacion;
    PERFORM pg_temp.sim_afirmar('07-AVANZADAS', 'R8 arribo operativo',
        v_llegada IS NOT NULL,
        'En transito -> Ocupado registro automaticamente la llegada.',
        'El cambio a Ocupado no registro la llegada.');

    SELECT s.tiempo_respuesta_minutos, s.minutos_por_punto_demora
    INTO v_sla, v_tramo
    FROM SLA s
    WHERE s.fk_gravedad_id = v_baja;

    UPDATE Asignacion
    SET timestamp_llegada = timestamp_asignacion
        + (v_sla + v_tramo * v_puntos_esperados + 0.5) * INTERVAL '1 minute'
    WHERE id_asignacion = v_asignacion;
    CALL sp_CalcularPenalizacion(v_asignacion);

    SELECT p.puntaje INTO v_puntos_obtenidos
    FROM Penalizacion p
    WHERE p.fk_recurso_id = v_recurso
      AND p.motivo ILIKE '%Demora%'
    ORDER BY p.id_penalizacion DESC
    LIMIT 1;
    SELECT puntaje INTO v_puntaje_despues FROM Recurso WHERE id_recurso = v_recurso;

    PERFORM pg_temp.sim_afirmar('07-AVANZADAS', 'P4 penalizacion proporcional',
        v_puntos_obtenidos = v_puntos_esperados
        AND v_puntaje_despues = v_puntaje_antes - v_puntos_esperados,
        format('La demora genero %s puntos y actualizo el ranking del recurso.', v_puntos_obtenidos),
        format('Resultado inesperado: puntos %s, puntaje %s -> %s.',
            v_puntos_obtenidos, v_puntaje_antes, v_puntaje_despues));
    PERFORM pg_temp.sim_afirmar('07-AVANZADAS', 'R18 decision de penalizacion',
        EXISTS (
            SELECT 1 FROM Log
            WHERE trigger_disparador = 'P4'
              AND idTablaAfectada = v_recurso
              AND operacion = 'DECISION'
        ), 'La penalizacion proporcional dejo una decision auditable.',
        'No se encontro la decision P4 en el log.');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.sim_capturar_error('07-AVANZADAS', 'Arribo y penalizacion proporcional', SQLERRM);
END;
$$;

SELECT pg_temp.sim_reset_operativo();

DO $$
DECLARE
    v_codigo TEXT;
    v_instalado BOOLEAN;
    v_recurso INT;
    v_umbral NUMERIC;
    v_estado TEXT;
BEGIN
    FOREACH v_codigo IN ARRAY ARRAY['R6', 'P3', 'P5']
    LOOP
        SELECT COALESCE(objeto_instalado, FALSE) INTO v_instalado
        FROM sim_cobertura WHERE codigo = v_codigo;
        UPDATE sim_cobertura
        SET estado = CASE WHEN v_instalado THEN 'XPASS' ELSE 'XFAIL' END,
            detalle = CASE WHEN v_instalado THEN 'La capacidad aparecio instalada y requiere revision.'
                           ELSE 'Capacidad requerida por la consigna no implementada.' END
        WHERE codigo = v_codigo;
        PERFORM pg_temp.sim_brecha('07-BRECHAS', v_codigo || ' ausente', NOT v_instalado,
            'Capacidad requerida no instalada.', 'La capacidad ahora aparece instalada; revisar cobertura.');
    END LOOP;

    SELECT id_recurso INTO v_recurso FROM Recurso ORDER BY id_recurso LIMIT 1;
    SELECT numero INTO v_umbral
    FROM ParametrosSistema WHERE nombre_parametro = 'PUNTAJE_BLOQUEO_RECURSO';
    INSERT INTO Penalizacion (fk_recurso_id, fk_tipo_penalizacion_id, motivo)
    SELECT v_recurso, tp.id_tipo_penalizacion, 'SIM-PRO-07 acumulacion #' || s
    FROM LATERAL (
        SELECT id_tipo_penalizacion, puntaje
        FROM TipoPenalizacion
        WHERE puntaje > 0
        ORDER BY puntaje DESC
        LIMIT 1
    ) tp
    CROSS JOIN LATERAL generate_series(1, CEIL(v_umbral / tp.puntaje)::int) s;
    SELECT er.nombre INTO v_estado
    FROM Recurso r
    JOIN EstadoRecurso er ON er.id_estado_recurso = r.fk_estado_recurso_id
    WHERE r.id_recurso = v_recurso;
    PERFORM pg_temp.sim_brecha('07-BRECHAS', 'Bloqueo por penalizaciones acumuladas',
        v_estado <> 'Fuera de servicio',
        'Superar el umbral no bloqueo automaticamente el recurso.',
        'El bloqueo por penalizaciones ahora funciona.');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.sim_capturar_error('07-BRECHAS', 'Brechas restantes', SQLERRM);
END;
$$;
