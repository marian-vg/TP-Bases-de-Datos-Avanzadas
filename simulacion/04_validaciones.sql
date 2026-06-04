\echo '>>> 04 - VALIDACIONES DE INTEGRIDAD'

SELECT pg_temp.sim_reset_operativo();

DO $$
DECLARE
    v_pendiente INT := pg_temp.sim_id_catalogo('EstadoIncidente', 'id_estado_incidente', 'Pendiente');
    v_resuelto INT := pg_temp.sim_id_catalogo('EstadoIncidente', 'id_estado_incidente', 'Resuelto');
    v_fuera INT := pg_temp.sim_id_catalogo('EstadoRecurso', 'id_estado_recurso', 'Fuera de servicio');
    v_tipo INT := pg_temp.sim_id_catalogo('TipoIncidente', 'id_tipo_incidente', 'Accidente de tránsito');
    v_baja INT := pg_temp.sim_id_catalogo('Gravedad', 'id_gravedad', 'Baja');
    v_zona INT;
    v_incidente INT;
    v_recurso INT;
    v_otro INT;
    v_bloqueado BOOLEAN;
BEGIN
    SELECT zr.id_zona INTO v_zona FROM ZonaRecurso zr JOIN Recurso r ON r.id_recurso = zr.id_recurso
    JOIN TipoIncidenteTipoRecurso x ON x.fk_tipo_recurso_id = r.fk_tipo_recurso_id
    WHERE x.fk_tipo_incidente_id = v_tipo ORDER BY zr.id_zona LIMIT 1;

    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    VALUES (v_tipo, v_baja, v_pendiente, v_zona, 'SIM-PRO-04 validaciones', 0)
    RETURNING id_incidente INTO v_incidente;
    SELECT fk_recurso_id INTO v_recurso FROM Asignacion WHERE fk_incidente_id = v_incidente LIMIT 1;

    v_bloqueado := FALSE;
    BEGIN
        INSERT INTO Asignacion (fk_recurso_id, fk_incidente_id) VALUES (v_recurso, v_incidente);
    EXCEPTION WHEN OTHERS THEN v_bloqueado := TRUE;
    END;
    PERFORM pg_temp.sim_afirmar('04-VALIDACIONES', 'R8 doble asignacion', v_bloqueado,
        'La doble asignacion fue bloqueada.', 'Se permitio una doble asignacion.');

    SELECT r.id_recurso INTO v_otro FROM Recurso r
    JOIN ZonaRecurso zr ON zr.id_recurso = r.id_recurso AND zr.id_zona = v_zona
    JOIN TipoIncidenteTipoRecurso x ON x.fk_tipo_recurso_id = r.fk_tipo_recurso_id AND x.fk_tipo_incidente_id = v_tipo
    WHERE r.id_recurso <> v_recurso AND r.fk_estado_recurso_id <> v_fuera
    ORDER BY r.id_recurso LIMIT 1;
    UPDATE Recurso SET fk_estado_recurso_id = v_fuera WHERE id_recurso = v_otro;
    v_bloqueado := FALSE;
    BEGIN
        INSERT INTO Asignacion (fk_recurso_id, fk_incidente_id) VALUES (v_otro, v_incidente);
    EXCEPTION WHEN OTHERS THEN v_bloqueado := TRUE;
    END;
    PERFORM pg_temp.sim_afirmar('04-VALIDACIONES', 'R8 fuera de servicio', v_bloqueado,
        'El recurso fuera de servicio fue rechazado.', 'Se asigno un recurso fuera de servicio.');

    UPDATE ParametrosSistema SET numero = 0 WHERE nombre_parametro = 'UMBRAL_RECURSOS_ACTIVOS';
    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    SELECT ti.id_tipo_incidente, v_baja, v_pendiente, v_zona, 'SIM-PRO-04 estado invalido', 0
    FROM TipoIncidente ti WHERE ti.nombre <> 'Accidente de tránsito' ORDER BY ti.id_tipo_incidente LIMIT 1
    RETURNING id_incidente INTO v_incidente;
    v_bloqueado := FALSE;
    BEGIN
        UPDATE Incidente SET fk_estado_incidente_id = v_resuelto WHERE id_incidente = v_incidente;
    EXCEPTION WHEN OTHERS THEN v_bloqueado := TRUE;
    END;
    PERFORM pg_temp.sim_afirmar('04-VALIDACIONES', 'R9 transicion invalida', v_bloqueado,
        'Pendiente -> Resuelto fue bloqueado.', 'Se permitio Pendiente -> Resuelto.');

    v_bloqueado := FALSE;
    BEGIN
        INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
        VALUES (v_tipo, v_baja, v_pendiente, v_zona, 'SIM-PRO-04 duplicado', 0);
    EXCEPTION WHEN OTHERS THEN v_bloqueado := TRUE;
    END;
    PERFORM pg_temp.sim_afirmar('04-VALIDACIONES', 'R11 duplicados', v_bloqueado,
        'El duplicado inmediato fue bloqueado.', 'Se permitio un duplicado inmediato.');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.sim_capturar_error('04-VALIDACIONES', 'Escenario completo', SQLERRM);
END;
$$;
