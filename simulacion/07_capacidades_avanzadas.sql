\if :{?sim_verbose}
\echo '>>> 07 - CAPACIDADES TEMPORALES, PENALIZACION Y ALCANCE'
\endif

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
    v_recurso_ajeno INT := (SELECT id_recurso FROM Recurso ORDER BY id_recurso OFFSET 1 LIMIT 1);
    v_fuera INT := pg_temp.sim_id_catalogo('EstadoRecurso', 'id_estado_recurso', 'Fuera de servicio');
    v_disponible INT := pg_temp.sim_id_catalogo('EstadoRecurso', 'id_estado_recurso', 'Disponible');
    v_tipo_penalizacion INT := (
        SELECT id_tipo_penalizacion FROM TipoPenalizacion ORDER BY id_tipo_penalizacion LIMIT 1
    );
    v_estado TEXT;
    v_estado_ajeno TEXT;
    v_umbral INT;
    v_cantidad INT;
    v_historial INT;
BEGIN
    SELECT numero::INT INTO v_umbral
    FROM ParametrosSistema
    WHERE nombre_parametro = 'MAX_CANTIDAD_PENALIZACIONES_RECURSO';

    FOR v_cantidad IN 1..(v_umbral - 1) LOOP
        INSERT INTO Penalizacion (fk_recurso_id, fk_tipo_penalizacion_id, motivo)
        VALUES (v_recurso, v_tipo_penalizacion, 'SIM-07 penalización previa al umbral');
    END LOOP;

    PERFORM pg_temp.sim_afirmar('07-AVANZADAS', 'Bloqueo antes del umbral',
        EXISTS (
            SELECT 1 FROM Recurso
            WHERE id_recurso = v_recurso
              AND fk_estado_recurso_id = v_disponible
              AND cantidad_penalizaciones = v_umbral - 1
        ),
        'El recurso permanecio disponible antes de alcanzar el maximo.',
        'El recurso fue bloqueado antes de alcanzar el maximo configurado.');

    INSERT INTO Penalizacion (fk_recurso_id, fk_tipo_penalizacion_id, motivo)
    VALUES (v_recurso, v_tipo_penalizacion, 'SIM-07 penalización que alcanza el umbral');

    SELECT er.nombre INTO v_estado
    FROM Recurso r
    JOIN EstadoRecurso er ON er.id_estado_recurso = r.fk_estado_recurso_id
    WHERE r.id_recurso = v_recurso;

    SELECT count(*) INTO v_historial
    FROM InhabilitacionRecurso
    WHERE fk_recurso_id = v_recurso
      AND fecha_reactivado IS NULL;

    PERFORM pg_temp.sim_afirmar('07-AVANZADAS', 'Bloqueo por penalizaciones',
        v_estado = 'Fuera de servicio' AND v_historial = 1,
        'Al alcanzar el maximo, el recurso fue inhabilitado y se registro el bloqueo.',
        format('Resultado inesperado: estado %s, inhabilitaciones activas %s.',
            v_estado, v_historial));

    -- Un recurso fuera de servicio por otra causa no pertenece al alcance de R17.
    UPDATE Recurso SET fk_estado_recurso_id = v_fuera WHERE id_recurso = v_recurso_ajeno;

    UPDATE InhabilitacionRecurso
    SET fecha_inhabilitacion = CURRENT_TIMESTAMP - INTERVAL '2 minutes',
        fecha_reactivacion_programada = CURRENT_TIMESTAMP - INTERVAL '1 minute'
    WHERE fk_recurso_id = v_recurso
      AND fecha_reactivado IS NULL;

    CALL sp_ReactivarRecursos();

    SELECT er.nombre INTO v_estado
    FROM Recurso r
    JOIN EstadoRecurso er ON er.id_estado_recurso = r.fk_estado_recurso_id
    WHERE r.id_recurso = v_recurso;

    SELECT er.nombre INTO v_estado_ajeno
    FROM Recurso r
    JOIN EstadoRecurso er ON er.id_estado_recurso = r.fk_estado_recurso_id
    WHERE r.id_recurso = v_recurso_ajeno;

    PERFORM pg_temp.sim_afirmar('07-AVANZADAS', 'R17 reactivacion temporal',
        v_estado = 'Disponible'
        AND EXISTS (
            SELECT 1 FROM Recurso
            WHERE id_recurso = v_recurso
              AND cantidad_penalizaciones = 0
              AND ciclo_penalizaciones = 2
        )
        AND EXISTS (
            SELECT 1 FROM InhabilitacionRecurso
            WHERE fk_recurso_id = v_recurso
              AND fecha_reactivado IS NOT NULL
        ),
        'R17 reactivo el recurso, reinicio sus penalizaciones y conservo el historial.',
        format('La reactivacion no completo el ciclo esperado; estado final %s.', v_estado));

    PERFORM pg_temp.sim_afirmar('07-AVANZADAS', 'R17 ignora otras bajas',
        v_estado_ajeno = 'Fuera de servicio',
        'R17 ignoro el recurso fuera de servicio sin inhabilitacion por penalizaciones.',
        format('R17 modifico indebidamente el recurso ajeno, que quedo %s.', v_estado_ajeno));
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.sim_capturar_error('07-AVANZADAS', 'Bloqueo y reactivacion por penalizaciones', SQLERRM);
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
    v_pendiente INT := pg_temp.sim_id_catalogo('EstadoIncidente', 'id_estado_incidente', 'Pendiente');
    v_tipo INT := pg_temp.sim_id_catalogo('TipoIncidente', 'id_tipo_incidente', 'Emergencia médica');
    v_baja INT := pg_temp.sim_id_catalogo('Gravedad', 'id_gravedad', 'Baja');
    v_zona INT;
    v_umbral_base INT;
    v_incidente INT;
    v_estado TEXT;
BEGIN
    SELECT zr.id_zona INTO v_zona
    FROM ZonaRecurso zr
    JOIN Recurso r ON r.id_recurso = zr.id_recurso
    JOIN EstadoRecurso er ON er.id_estado_recurso = r.fk_estado_recurso_id
    JOIN TipoIncidenteTipoRecurso x ON x.fk_tipo_recurso_id = r.fk_tipo_recurso_id
    WHERE x.fk_tipo_incidente_id = v_tipo AND er.nombre = 'Disponible'
    ORDER BY zr.id_zona
    LIMIT 1;
    SELECT umbral_incidentes_activos INTO v_umbral_base FROM Zona WHERE id_zona = v_zona;
    UPDATE Zona SET umbral_incidentes_activos = 0 WHERE id_zona = v_zona;

    INSERT INTO Incidente (
        fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id,
        fk_zona_id, descripcion, prioridad
    )
    VALUES (v_tipo, v_baja, v_pendiente, v_zona, 'SIM-PRO-07 asignacion diferida P1', 0)
    RETURNING id_incidente INTO v_incidente;

    UPDATE Zona SET umbral_incidentes_activos = v_umbral_base WHERE id_zona = v_zona;
    CALL sp_AsignarRecurso(v_incidente);
    SELECT ei.nombre INTO v_estado
    FROM Incidente i
    JOIN EstadoIncidente ei ON ei.id_estado_incidente = i.fk_estado_incidente_id
    WHERE i.id_incidente = v_incidente;

    PERFORM pg_temp.sim_afirmar('07-AVANZADAS', 'P1 asignacion diferida',
        v_estado = 'En proceso'
        AND EXISTS (SELECT 1 FROM Asignacion WHERE fk_incidente_id = v_incidente),
        'P1 recupero un incidente pendiente y le asigno un recurso.',
        'P1 no pudo recuperar el incidente pendiente.');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.sim_capturar_error('07-AVANZADAS', 'Procedimiento P1', SQLERRM);
END;
$$;

SELECT pg_temp.sim_reset_operativo();

DO $$
DECLARE
    v_pendiente INT := pg_temp.sim_id_catalogo('EstadoIncidente', 'id_estado_incidente', 'Pendiente');
    v_resuelto INT := pg_temp.sim_id_catalogo('EstadoIncidente', 'id_estado_incidente', 'Resuelto');
    v_disponible INT := pg_temp.sim_id_catalogo('EstadoRecurso', 'id_estado_recurso', 'Disponible');
    v_tipo INT := pg_temp.sim_id_catalogo('TipoIncidente', 'id_tipo_incidente', 'Emergencia médica');
    v_baja INT := pg_temp.sim_id_catalogo('Gravedad', 'id_gravedad', 'Baja');
    v_zona INT;
    v_incidente INT;
    v_asignaciones_abiertas INT;
    v_recursos_no_disponibles INT;
BEGIN
    SELECT zr.id_zona INTO v_zona
    FROM ZonaRecurso zr
    JOIN Recurso r ON r.id_recurso = zr.id_recurso
    JOIN EstadoRecurso er ON er.id_estado_recurso = r.fk_estado_recurso_id
    JOIN TipoIncidenteTipoRecurso x ON x.fk_tipo_recurso_id = r.fk_tipo_recurso_id
    WHERE x.fk_tipo_incidente_id = v_tipo
      AND er.nombre = 'Disponible'
    ORDER BY zr.id_zona
    LIMIT 1;

    INSERT INTO Incidente (
        fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id,
        fk_zona_id, descripcion, prioridad
    )
    VALUES (v_tipo, v_baja, v_pendiente, v_zona, 'SIM-PRO-07 cierre manual P3', 0)
    RETURNING id_incidente INTO v_incidente;

    CALL sp_CerrarIncidente(v_incidente);

    SELECT count(*) INTO v_asignaciones_abiertas
    FROM Asignacion
    WHERE fk_incidente_id = v_incidente
      AND timestamp_finalizacion IS NULL;

    SELECT count(*) INTO v_recursos_no_disponibles
    FROM Asignacion a
    JOIN Recurso r ON r.id_recurso = a.fk_recurso_id
    WHERE a.fk_incidente_id = v_incidente
      AND r.fk_estado_recurso_id IS DISTINCT FROM v_disponible;

    PERFORM pg_temp.sim_afirmar('07-AVANZADAS', 'P3 cierre de incidente',
        EXISTS (
            SELECT 1 FROM Incidente
            WHERE id_incidente = v_incidente
              AND fk_estado_incidente_id = v_resuelto
        )
        AND v_asignaciones_abiertas = 0
        AND v_recursos_no_disponibles = 0,
        'P3 resolvio el incidente, finalizo asignaciones y libero recursos.',
        format('P3 no cerro correctamente: asignaciones abiertas %s, recursos no disponibles %s.',
            v_asignaciones_abiertas, v_recursos_no_disponibles));
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.sim_capturar_error('07-AVANZADAS', 'Procedimiento P3', SQLERRM);
END;
$$;

SELECT pg_temp.sim_reset_operativo();

DO $$
DECLARE
    v_umbral NUMERIC;
    v_sensor INT;
    v_tipo_evento INT;
    v_eventos_antes INT;
    v_eventos_despues INT;
    v_evento INT;
    v_incidente INT;
BEGIN
    SELECT numero INTO v_umbral
    FROM ParametrosSistema
    WHERE nombre_parametro = 'SENSOR_UMBRAL_CONFIANZA_MINIMO';

    SELECT id_sensor INTO v_sensor
    FROM Sensor
    WHERE fn_confianza_sensor(id_sensor) > v_umbral
    ORDER BY id_sensor
    LIMIT 1;

    SELECT fk_tipo_evento_id INTO v_tipo_evento
    FROM TipoEventoTipoIncidente
    GROUP BY fk_tipo_evento_id
    HAVING count(*) = 1
    ORDER BY fk_tipo_evento_id
    LIMIT 1;

    SELECT count(*) INTO v_eventos_antes FROM Evento;

    CALL sp_SimularEventos(v_sensor, v_tipo_evento);

    SELECT count(*) INTO v_eventos_despues FROM Evento;
    SELECT id_evento INTO v_evento
    FROM Evento
    WHERE fk_sensor_id = v_sensor
      AND fk_tipo_evento_id = v_tipo_evento
    ORDER BY id_evento DESC
    LIMIT 1;

    SELECT id_incidente INTO v_incidente
    FROM Incidente
    WHERE fk_evento_id = v_evento
    ORDER BY id_incidente DESC
    LIMIT 1;

    PERFORM pg_temp.sim_afirmar('07-AVANZADAS', 'P5 simulacion de eventos',
        v_eventos_despues = v_eventos_antes + 1
        AND v_incidente IS NOT NULL,
        'P5 registro el evento y genero el incidente automatico esperado.',
        format('P5 no genero el flujo esperado: eventos %s -> %s, incidente %s.',
            v_eventos_antes, v_eventos_despues, COALESCE(v_incidente::text, 'NULL')));

    PERFORM pg_temp.sim_afirmar('07-AVANZADAS', 'R6 incidente relacionado',
        EXISTS (
            SELECT 1
            FROM Incidente i
            JOIN Evento e ON e.id_evento = i.fk_evento_id
            JOIN TipoEventoTipoIncidente x
              ON x.fk_tipo_evento_id = e.fk_tipo_evento_id
             AND x.fk_tipo_incidente_id = i.fk_tipo_incidente_id
             AND x.fk_gravedad_id = i.fk_gravedad_id
            WHERE i.id_incidente = v_incidente
        ),
        'El incidente generado quedo relacionado con el evento por el mapeo TipoEventoTipoIncidente.',
        'El incidente generado no respeta el mapeo evento-incidente esperado.');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.sim_capturar_error('07-AVANZADAS', 'Procedimiento P5/R6', SQLERRM);
END;
$$;
