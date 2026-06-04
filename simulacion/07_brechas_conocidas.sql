\echo '>>> 07 - BRECHAS CONOCIDAS'

SELECT pg_temp.sim_reset_operativo();

DO $$
DECLARE
    v_codigo TEXT;
    v_instalado BOOLEAN;
BEGIN
    FOREACH v_codigo IN ARRAY ARRAY['R6', 'P3', 'P4', 'P5']
    LOOP
        SELECT COALESCE(objeto_instalado, FALSE) INTO v_instalado FROM sim_cobertura WHERE codigo = v_codigo;
        UPDATE sim_cobertura
        SET estado = CASE WHEN v_instalado THEN 'XPASS' ELSE 'XFAIL' END,
            detalle = CASE WHEN v_instalado THEN 'La capacidad aparecio instalada y requiere revision.'
                           ELSE 'Capacidad requerida por la consigna no implementada.' END
        WHERE codigo = v_codigo;
        PERFORM pg_temp.sim_brecha('07-BRECHAS', v_codigo || ' ausente', NOT v_instalado,
            'Capacidad requerida no instalada.', 'La capacidad ahora aparece instalada; revisar cobertura.');
    END LOOP;

    FOREACH v_codigo IN ARRAY ARRAY['R16', 'R17', 'R20', 'P2']
    LOOP
        SELECT COALESCE(objeto_instalado, FALSE) INTO v_instalado FROM sim_cobertura WHERE codigo = v_codigo;
        UPDATE sim_cobertura
        SET estado = CASE WHEN v_instalado THEN 'XPASS' ELSE 'XFAIL' END,
            detalle = CASE WHEN v_instalado THEN 'Objeto instalado en la base evaluada.'
                           ELSE 'Existe codigo fuente relacionado, pero la migracion canonica no lo carga.' END
        WHERE codigo = v_codigo;
        PERFORM pg_temp.sim_brecha('07-BRECHAS', v_codigo || ' no cargada', NOT v_instalado,
            'El objeto no fue cargado por la migracion canonica.', 'El objeto aparece instalado; revisar la migracion utilizada.');
    END LOOP;
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.sim_capturar_error('07-BRECHAS', 'Deteccion de objetos ausentes', SQLERRM);
END;
$$;

DO $$
DECLARE
    v_pendiente INT := pg_temp.sim_id_catalogo('EstadoIncidente', 'id_estado_incidente', 'Pendiente');
    v_tipo INT := pg_temp.sim_id_catalogo('TipoIncidente', 'id_tipo_incidente', 'Emergencia médica');
    v_baja INT := pg_temp.sim_id_catalogo('Gravedad', 'id_gravedad', 'Baja');
    v_zona INT;
    v_incidente INT;
    v_penalizaciones INT;
    v_recurso INT;
    v_umbral NUMERIC;
    v_fuera TEXT;
BEGIN
    SELECT zr.id_zona INTO v_zona FROM ZonaRecurso zr JOIN Recurso r ON r.id_recurso = zr.id_recurso
    JOIN TipoIncidenteTipoRecurso x ON x.fk_tipo_recurso_id = r.fk_tipo_recurso_id
    WHERE x.fk_tipo_incidente_id = v_tipo ORDER BY zr.id_zona LIMIT 1;
    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    VALUES (v_tipo, v_baja, v_pendiente, v_zona, 'SIM-PRO-07 demora sin penalizacion', 0)
    RETURNING id_incidente INTO v_incidente;
    UPDATE Asignacion SET timestamp_llegada = timestamp_asignacion + INTERVAL '90 minutes' WHERE fk_incidente_id = v_incidente;
    SELECT count(*) INTO v_penalizaciones FROM Penalizacion;
    PERFORM pg_temp.sim_brecha('07-BRECHAS', 'Penalizacion automatica por demora', v_penalizaciones = 0,
        'La demora no genero penalizacion automatica.', 'La penalizacion por demora ahora funciona.');

    PERFORM pg_temp.sim_reset_operativo();
    SELECT id_recurso INTO v_recurso FROM Recurso ORDER BY id_recurso LIMIT 1;
    SELECT numero INTO v_umbral FROM ParametrosSistema WHERE nombre_parametro = 'PUNTAJE_BLOQUEO_RECURSO';
    INSERT INTO Penalizacion (fk_recurso_id, fk_tipo_penalizacion_id, motivo)
    SELECT v_recurso, tp.id_tipo_penalizacion, 'SIM-PRO-07 acumulacion #' || s
    FROM LATERAL (
        SELECT id_tipo_penalizacion, puntaje FROM TipoPenalizacion ORDER BY puntaje DESC LIMIT 1
    ) tp
    CROSS JOIN LATERAL generate_series(1, CEIL(v_umbral / NULLIF(tp.puntaje, 0))::int) s;
    SELECT er.nombre INTO v_fuera FROM Recurso r JOIN EstadoRecurso er ON er.id_estado_recurso = r.fk_estado_recurso_id WHERE r.id_recurso = v_recurso;
    PERFORM pg_temp.sim_brecha('07-BRECHAS', 'Bloqueo por penalizaciones acumuladas', v_fuera <> 'Fuera de servicio',
        'Superar el umbral no bloqueo el recurso.', 'El bloqueo por penalizaciones ahora funciona.');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.sim_capturar_error('07-BRECHAS', 'Demostracion de brechas', SQLERRM);
END;
$$;
