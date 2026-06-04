-- ============================================================================
-- P1. sp_AsignarRecurso
--
-- • Busca recursos disponibles.
-- • Aplica criterio de selección (tipo compatible y zona habilitada, R14).
-- • Completa asignaciones pendientes usando recursos ya habilitados en la zona.
-- • Asigna automáticamente al incidente generado.
-- ============================================================================

CREATE OR REPLACE PROCEDURE sp_AsignarRecurso(p_id_incidente INT)
LANGUAGE plpgsql AS $$
DECLARE
    v_estado_incidente INT;
    v_gravedad_incidente INT;
    v_requeridos INT;
    v_asignados_activos INT;
    v_faltantes INT;
    v_insertados INT;
BEGIN

    SELECT fk_estado_incidente_id, fk_gravedad_id
    INTO v_estado_incidente, v_gravedad_incidente
    FROM Incidente
    WHERE id_incidente = p_id_incidente
    FOR UPDATE;

    -- FOUND -> variable local pl/pgsql que retorna true si la consulta anterior encuentra alguna fila.
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El incidente con ID % no existe.', p_id_incidente;
    END IF;

    -- Los incidentes finalizados/inactivos (Resuelto/Cancelado) no admiten nuevas asignaciones
    IF EXISTS (
        SELECT 1 
        FROM EstadoIncidente 
        WHERE id_estado_incidente = v_estado_incidente 
          AND nombre IN ('Resuelto', 'Cancelado')
    ) THEN
        RAISE EXCEPTION 'No se pueden asignar recursos a un incidente en estado finalizado o inactivo (Estado ID: %).', v_estado_incidente;
    END IF;

    v_requeridos := fn_recursos_por_gravedad(v_gravedad_incidente);

    SELECT COUNT(*) INTO v_asignados_activos
    FROM Asignacion
    WHERE fk_incidente_id = p_id_incidente 
      AND timestamp_finalizacion IS NULL;

    v_faltantes := v_requeridos - v_asignados_activos;

    IF v_faltantes > 0 THEN
        v_insertados := fn_asignar_recursos_incidente(p_id_incidente, v_faltantes);
        
        IF v_insertados = 0 AND v_asignados_activos = 0 THEN
            RAISE NOTICE 'No se encontraron recursos disponibles (locales ni globales) para el incidente %.', p_id_incidente;
        ELSE
            RAISE NOTICE 'Se asignaron % recursos adicionales al incidente % (Requeridos: %, Activos antes: %).', 
                v_insertados, p_id_incidente, v_requeridos, v_asignados_activos;
        END IF;
    ELSE
        RAISE NOTICE 'El incidente % ya cuenta con la cantidad requerida de recursos (%) para su gravedad.', 
            p_id_incidente, v_requeridos;
    END IF;
    -- RAISE NOTICE -> dispara un mensaje como RAISE EXCEPTION pero es meramente informativo, no interrumpe el flujo ni hace rollback. Sirve para ver mensajes de success por ejemplo.
END;
$$;
