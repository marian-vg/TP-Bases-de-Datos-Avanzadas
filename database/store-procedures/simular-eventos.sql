-- ============================================================================
-- P3. sp_SimularEventoSensor
--
-- • Simula la activación de un sensor físico que reporta un tipo de evento.
-- • Valida existencia de sensor y tipo de evento.
-- • Aplica bloqueo FOR UPDATE sobre el sensor.
-- • Inserta el evento en Evento, lo que dispara el trigger trg_evento_promocion.
-- • Verifica si se creó el incidente correspondiente o si falló por validaciones (R11).
-- ============================================================================

CREATE OR REPLACE PROCEDURE sp_SimularEventoSensor(
    p_id_sensor INT,
    p_id_tipo_evento INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_sensor_existe INT;
    v_tipo_evento_existe INT;
    v_id_evento INT;
    v_id_incidente INT;
    v_recursos_asignados INT;
    v_error_log TEXT;
    v_motivo_log TEXT;
BEGIN
    SELECT id_sensor INTO v_sensor_existe
    FROM Sensor
    WHERE id_sensor = p_id_sensor
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El sensor con ID % no existe.', p_id_sensor;
    END IF;

    -- 2. Validar existencia del tipo de evento
    SELECT id_tipo_evento INTO v_tipo_evento_existe
    FROM TipoEvento
    WHERE id_tipo_evento = p_id_tipo_evento;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El tipo de evento con ID % no existe.', p_id_tipo_evento;
    END IF;

    -- 3. Insertar el evento de sensor
    --    Esto gatillará trg_evento_promocion, el cual intentará crear el incidente automáticamente.
    INSERT INTO Evento (fk_sensor_id, fk_tipo_evento_id, fecha_evento, hora_evento)
    VALUES (p_id_sensor, p_id_tipo_evento, CURRENT_DATE, CURRENT_TIME)
    RETURNING id_evento INTO v_id_evento;

    SELECT id_incidente INTO v_id_incidente
    FROM Incidente
    WHERE fk_evento_id = v_id_evento;

    IF v_id_incidente IS NOT NULL THEN
        -- Contar cuántos recursos fueron asignados
        SELECT COUNT(*) INTO v_recursos_asignados
        FROM Asignacion
        WHERE fk_incidente_id = v_id_incidente;

        RAISE NOTICE 'Evento #% simulado con éxito. Se creó automáticamente el incidente #% con % recursos asignados.',
            v_id_evento, v_id_incidente, v_recursos_asignados;
    ELSE

        SELECT detalle->>'error', detalle->>'motivo'
        INTO v_error_log, v_motivo_log
        FROM Log
        WHERE LOWER(tablaAfectada) = 'evento'
          AND idTablaAfectada = v_id_evento
          AND trigger_disparador = 'trg_evento_promocion'
        ORDER BY id_log DESC
        LIMIT 1;

        IF v_error_log IS NOT NULL THEN
            RAISE NOTICE 'Evento #% registrado. No se pudo crear el incidente automático debido a validación de negocio: %',
                v_id_evento, v_error_log;
        ELSE
            RAISE NOTICE 'Evento #% registrado. No se promovió a incidente. Motivo: %',
                v_id_evento, COALESCE(v_motivo_log, 'Mapeo de evento no configurado o de baja fiabilidad.');
        END IF;
    END IF;
END;
$$;
