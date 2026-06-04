\echo '>>> 05 - SENSORES IOT'

SELECT pg_temp.sim_reset_operativo();

DO $$
DECLARE
    v_umbral NUMERIC;
    v_sensor_alto INT;
    v_sensor_bajo INT;
    v_evento_unico INT;
    v_evento_ambiguo INT;
    v_evento INT;
    v_evento_2 INT;
BEGIN
    SELECT numero INTO v_umbral FROM ParametrosSistema WHERE nombre_parametro = 'SENSOR_UMBRAL_CONFIANZA_MINIMO';
    SELECT id_sensor INTO v_sensor_alto FROM Sensor WHERE fn_confianza_sensor(id_sensor) > v_umbral ORDER BY id_sensor LIMIT 1;
    SELECT id_sensor INTO v_sensor_bajo FROM Sensor WHERE fn_confianza_sensor(id_sensor) <= v_umbral ORDER BY id_sensor LIMIT 1;
    SELECT fk_tipo_evento_id INTO v_evento_unico FROM TipoEventoTipoIncidente GROUP BY fk_tipo_evento_id HAVING count(*) = 1 ORDER BY fk_tipo_evento_id LIMIT 1;
    SELECT fk_tipo_evento_id INTO v_evento_ambiguo FROM TipoEventoTipoIncidente GROUP BY fk_tipo_evento_id HAVING count(*) > 1 ORDER BY fk_tipo_evento_id LIMIT 1;

    IF v_sensor_alto IS NULL OR v_evento_unico IS NULL THEN
        PERFORM pg_temp.sim_registrar('05-IOT', 'Evento confiable', 'SKIP', 'Falta sensor confiable o mapeo unico.');
    ELSE
        INSERT INTO Evento (fk_sensor_id, fk_tipo_evento_id) VALUES (v_sensor_alto, v_evento_unico) RETURNING id_evento INTO v_evento;
        PERFORM pg_temp.sim_afirmar('05-IOT', 'R21 promocion confiable',
            EXISTS (SELECT 1 FROM Incidente WHERE fk_evento_id = v_evento),
            'El evento confiable genero incidente.', 'El evento confiable no genero incidente.');

        INSERT INTO Evento (fk_sensor_id, fk_tipo_evento_id) VALUES (v_sensor_alto, v_evento_unico) RETURNING id_evento INTO v_evento_2;
        PERFORM pg_temp.sim_afirmar('05-IOT', 'R11 duplicado desde IoT',
            NOT EXISTS (SELECT 1 FROM Incidente WHERE fk_evento_id = v_evento_2)
            AND EXISTS (SELECT 1 FROM Log WHERE idTablaAfectada = v_evento_2 AND detalle ? 'error'),
            'El segundo evento quedo registrado sin duplicar incidente.', 'El duplicado IoT no fue gestionado correctamente.');
    END IF;

    IF v_sensor_bajo IS NULL THEN
        PERFORM pg_temp.sim_registrar('05-IOT', 'Evento poco confiable', 'SKIP', 'El dataset no contiene sensores bajo el umbral.');
    ELSE
        INSERT INTO Evento (fk_sensor_id, fk_tipo_evento_id) VALUES (v_sensor_bajo, v_evento_unico) RETURNING id_evento INTO v_evento;
        PERFORM pg_temp.sim_afirmar('05-IOT', 'R21 rechazo por confianza',
            NOT EXISTS (SELECT 1 FROM Incidente WHERE fk_evento_id = v_evento)
            AND EXISTS (SELECT 1 FROM Log WHERE idTablaAfectada = v_evento AND detalle->>'motivo' LIKE '%baja fiabilidad%'),
            'El evento poco confiable solo fue auditado.', 'El evento poco confiable fue procesado incorrectamente.');
    END IF;

    IF v_sensor_alto IS NULL OR v_evento_ambiguo IS NULL THEN
        PERFORM pg_temp.sim_registrar('05-IOT', 'Mapeo ambiguo', 'SKIP', 'Falta sensor confiable o evento ambiguo.');
    ELSE
        INSERT INTO Evento (fk_sensor_id, fk_tipo_evento_id) VALUES (v_sensor_alto, v_evento_ambiguo) RETURNING id_evento INTO v_evento;
        PERFORM pg_temp.sim_afirmar('05-IOT', 'R21 mapeo ambiguo',
            NOT EXISTS (SELECT 1 FROM Incidente WHERE fk_evento_id = v_evento),
            'El sistema no adivino ante un mapeo ambiguo.', 'Un evento ambiguo genero incidente.');
    END IF;
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.sim_capturar_error('05-IOT', 'Escenario completo', SQLERRM);
END;
$$;
