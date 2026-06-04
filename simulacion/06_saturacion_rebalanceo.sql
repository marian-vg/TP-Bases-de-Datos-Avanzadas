\echo '>>> 06 - SATURACION Y REBALANCEO'

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
    v_asignado INT;
BEGIN
    SELECT z.id_zona INTO v_zona
    FROM Zona z
    WHERE EXISTS (
        SELECT 1 FROM Recurso r
        JOIN ZonaRecurso zr ON zr.id_recurso = r.id_recurso AND zr.id_zona = z.id_zona
        JOIN TipoIncidenteTipoRecurso x ON x.fk_tipo_recurso_id = r.fk_tipo_recurso_id AND x.fk_tipo_incidente_id = v_tipo
    )
    ORDER BY z.id_zona LIMIT 1;

    UPDATE Recurso r SET fk_estado_recurso_id = v_fuera
    WHERE r.fk_estado_recurso_id = v_disponible
      AND EXISTS (SELECT 1 FROM ZonaRecurso zr WHERE zr.id_recurso = r.id_recurso AND zr.id_zona = v_zona)
      AND EXISTS (SELECT 1 FROM TipoIncidenteTipoRecurso x WHERE x.fk_tipo_recurso_id = r.fk_tipo_recurso_id AND x.fk_tipo_incidente_id = v_tipo);

    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    VALUES (v_tipo, v_baja, v_pendiente, v_zona, 'SIM-PRO-06 rebalanceo', 0)
    RETURNING id_incidente INTO v_incidente;
    SELECT fk_recurso_id INTO v_asignado FROM Asignacion WHERE fk_incidente_id = v_incidente LIMIT 1;

    PERFORM pg_temp.sim_afirmar('06-SATURACION', 'R15 asignacion global', v_asignado IS NOT NULL,
        'Se encontro recurso fuera de la cobertura local agotada.', 'El incidente quedo sin recurso.');
    PERFORM pg_temp.sim_afirmar('06-SATURACION', 'R15 compatibilidad global',
        v_asignado IS NOT NULL AND EXISTS (
            SELECT 1 FROM Recurso r JOIN TipoIncidenteTipoRecurso x ON x.fk_tipo_recurso_id = r.fk_tipo_recurso_id
            WHERE r.id_recurso = v_asignado AND x.fk_tipo_incidente_id = v_tipo
        ), 'El recurso rebalanceado es compatible.', 'El recurso rebalanceado no es compatible o no existe.');
    PERFORM pg_temp.sim_afirmar('06-SATURACION', 'R18 log de rebalanceo',
        EXISTS (SELECT 1 FROM Log WHERE detalle::text ILIKE '%rebalanceo%'),
        'La decision de rebalanceo fue auditada.', 'No se encontro log de rebalanceo.');
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
BEGIN
    UPDATE ParametrosSistema SET numero = 0 WHERE nombre_parametro = 'UMBRAL_RECURSOS_ACTIVOS';
    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    VALUES (v_tipo, v_baja, v_pendiente, v_zona, 'SIM-PRO-06 capacidad agotada', 0)
    RETURNING id_incidente INTO v_incidente;

    PERFORM pg_temp.sim_afirmar('06-SATURACION', 'Umbral de recursos activos',
        NOT EXISTS (SELECT 1 FROM Asignacion WHERE fk_incidente_id = v_incidente),
        'El incidente quedo pendiente al agotarse la capacidad.', 'Se asignaron recursos pese al umbral cero.');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.sim_capturar_error('06-SATURACION', 'Control por umbral', SQLERRM);
END;
$$;
