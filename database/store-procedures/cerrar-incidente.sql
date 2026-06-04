-- ============================================================================
-- P2. sp_CerrarIncidente
--
-- • Finaliza un incidente activo, liberando todos sus recursos asociados.
-- • Aplica exclusión mutua mediante bloqueo FOR UPDATE.
-- • Controla coherencia de transiciones de estado.
-- ============================================================================

CREATE OR REPLACE PROCEDURE sp_CerrarIncidente(p_id_incidente INT)
LANGUAGE plpgsql AS $$
DECLARE
    v_estado_actual INT;
    v_nombre_estado VARCHAR(50);
    v_estado_resuelto INT;
    v_estado_cancelado INT;
    v_recursos_liberados INT := 0;
BEGIN
    -- 0. Validar parámetro de entrada
    IF p_id_incidente IS NULL THEN
        RAISE EXCEPTION 'El ID de incidente provisto no puede ser nulo.';
    END IF;

    -- 1. Obtener y bloquear la fila del incidente para evitar condiciones de carrera
    SELECT fk_estado_incidente_id INTO v_estado_actual
    FROM Incidente
    WHERE id_incidente = p_id_incidente
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El incidente con ID % no existe.', p_id_incidente;
    END IF;

    -- Obtener nombres y IDs de estados en una sola consulta agrupada
    SELECT 
        (SELECT nombre FROM EstadoIncidente WHERE id_estado_incidente = v_estado_actual),
        (SELECT id_estado_incidente FROM EstadoIncidente WHERE nombre = 'Resuelto'),
        (SELECT id_estado_incidente FROM EstadoIncidente WHERE nombre = 'Cancelado')
    INTO v_nombre_estado, v_estado_resuelto, v_estado_cancelado;

    -- Validar que el incidente no este en un estado terminal ya
    IF v_nombre_estado IN ('Resuelto', 'Cancelado') THEN
        RAISE EXCEPTION 'El incidente con ID % ya se encuentra finalizado o inactivo (Estado: %).', 
            p_id_incidente, v_nombre_estado;
    END IF;

    IF v_nombre_estado = 'Pendiente' THEN
        UPDATE Incidente
        SET fk_estado_incidente_id = v_estado_cancelado
        WHERE id_incidente = p_id_incidente;
        
        RAISE NOTICE 'El incidente % (estado Pendiente) fue finalizado y marcado como Cancelado (R9).', p_id_incidente;
    ELSE
        UPDATE Asignacion
        SET timestamp_finalizacion = CURRENT_TIMESTAMP,
            estado_exito = COALESCE(estado_exito, TRUE)
        WHERE fk_incidente_id = p_id_incidente
          AND timestamp_finalizacion IS NULL;

        GET DIAGNOSTICS v_recursos_liberados = ROW_COUNT;

        -- Pasar el estado del incidente a 'Resuelto' si es que no se actualizo por los triggers ya
        UPDATE Incidente
        SET fk_estado_incidente_id = v_estado_resuelto
        WHERE id_incidente = p_id_incidente
          AND fk_estado_incidente_id != v_estado_resuelto;

        RAISE NOTICE 'El incidente % fue cerrado con éxito y se liberaron % recursos asociados.', 
            p_id_incidente, v_recursos_liberados;
    END IF;
END;
$$;
