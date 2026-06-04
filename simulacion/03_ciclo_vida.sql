\echo '>>> 03 - CICLO DE VIDA OPERATIVO'

SELECT pg_temp.sim_reset_operativo();

DO $$
DECLARE
    v_pendiente INT := pg_temp.sim_id_catalogo('EstadoIncidente', 'id_estado_incidente', 'Pendiente');
    v_tipo INT := pg_temp.sim_id_catalogo('TipoIncidente', 'id_tipo_incidente', 'Emergencia médica');
    v_baja INT := pg_temp.sim_id_catalogo('Gravedad', 'id_gravedad', 'Baja');
    v_zona INT;
    v_incidente INT;
    v_asignacion INT;
    v_recurso INT;
    v_estado_inc TEXT;
    v_estado_rec TEXT;
BEGIN
    SELECT zr.id_zona INTO v_zona
    FROM ZonaRecurso zr JOIN Recurso r ON r.id_recurso = zr.id_recurso
    JOIN TipoIncidenteTipoRecurso x ON x.fk_tipo_recurso_id = r.fk_tipo_recurso_id
    WHERE x.fk_tipo_incidente_id = v_tipo
    ORDER BY zr.id_zona LIMIT 1;

    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    VALUES (v_tipo, v_baja, v_pendiente, v_zona, 'SIM-PRO-03 cierre exitoso', 0)
    RETURNING id_incidente INTO v_incidente;

    SELECT id_asignacion, fk_recurso_id INTO v_asignacion, v_recurso
    FROM Asignacion WHERE fk_incidente_id = v_incidente LIMIT 1;

    UPDATE Asignacion
    SET timestamp_llegada = timestamp_asignacion + INTERVAL '2 minutes',
        estado_exito = TRUE,
        timestamp_finalizacion = timestamp_asignacion + INTERVAL '8 minutes'
    WHERE id_asignacion = v_asignacion;

    SELECT ei.nombre INTO v_estado_inc FROM Incidente i JOIN EstadoIncidente ei ON ei.id_estado_incidente = i.fk_estado_incidente_id WHERE i.id_incidente = v_incidente;
    SELECT er.nombre INTO v_estado_rec FROM Recurso r JOIN EstadoRecurso er ON er.id_estado_recurso = r.fk_estado_recurso_id WHERE r.id_recurso = v_recurso;

    PERFORM pg_temp.sim_afirmar('03-CICLO', 'R7 cierre automatico', v_estado_inc = 'Resuelto',
        'El incidente finalizo Resuelto.', format('Estado final inesperado: %s.', v_estado_inc));
    PERFORM pg_temp.sim_afirmar('03-CICLO', 'R8 liberacion de recurso', v_estado_rec = 'Disponible',
        'El recurso volvio a Disponible.', format('Estado final del recurso: %s.', v_estado_rec));
    PERFORM pg_temp.sim_afirmar('03-CICLO', 'R3 auditoria de cierre',
        EXISTS (SELECT 1 FROM Log WHERE lower(tablaAfectada) = 'asignacion' AND idTablaAfectada = v_asignacion AND operacion = 'UPDATE'),
        'La finalizacion fue auditada.', 'No se encontro auditoria de la finalizacion.');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.sim_capturar_error('03-CICLO', 'Flujo exitoso', SQLERRM);
END;
$$;

SELECT pg_temp.sim_reset_operativo();

DO $$
DECLARE
    v_pendiente INT := pg_temp.sim_id_catalogo('EstadoIncidente', 'id_estado_incidente', 'Pendiente');
    v_tipo INT := pg_temp.sim_id_catalogo('TipoIncidente', 'id_tipo_incidente', 'Accidente de tránsito');
    v_alta INT := pg_temp.sim_id_catalogo('Gravedad', 'id_gravedad', 'Alta');
    v_zona INT;
    v_incidente INT;
    v_asignacion INT;
    v_recurso INT;
    v_total INT;
    v_abiertas INT;
BEGIN
    SELECT zr.id_zona INTO v_zona FROM ZonaRecurso zr JOIN Recurso r ON r.id_recurso = zr.id_recurso
    JOIN TipoIncidenteTipoRecurso x ON x.fk_tipo_recurso_id = r.fk_tipo_recurso_id
    WHERE x.fk_tipo_incidente_id = v_tipo ORDER BY zr.id_zona LIMIT 1;

    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    VALUES (v_tipo, v_alta, v_pendiente, v_zona, 'SIM-PRO-03 falla y reasignacion', 0)
    RETURNING id_incidente INTO v_incidente;

    SELECT id_asignacion, fk_recurso_id INTO v_asignacion, v_recurso
    FROM Asignacion WHERE fk_incidente_id = v_incidente ORDER BY id_asignacion LIMIT 1;
    UPDATE Asignacion SET estado_exito = FALSE WHERE id_asignacion = v_asignacion;

    SELECT count(*), count(*) FILTER (WHERE timestamp_finalizacion IS NULL)
    INTO v_total, v_abiertas FROM Asignacion WHERE fk_incidente_id = v_incidente;

    PERFORM pg_temp.sim_afirmar('03-CICLO', 'R4 reasignacion por falla', v_total = 3 AND v_abiertas = 2,
        'La falla cerro una asignacion y genero su reemplazo.', format('Totales inesperados: %s total / %s abiertas.', v_total, v_abiertas));
    PERFORM pg_temp.sim_afirmar('03-CICLO', 'Penalizacion por falla',
        EXISTS (SELECT 1 FROM Penalizacion WHERE fk_recurso_id = v_recurso),
        'El recurso fallido fue penalizado.', 'No se genero penalizacion por falla.');
    PERFORM pg_temp.sim_medir('03-CICLO', 'reasignaciones_por_falla', v_total - 2);
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.sim_capturar_error('03-CICLO', 'Flujo de falla', SQLERRM);
END;
$$;
