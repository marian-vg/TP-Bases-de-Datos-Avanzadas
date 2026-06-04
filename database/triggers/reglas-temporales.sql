-- ============================================================================
-- PROCEDIMIENTOS ALMACENADOS (REGLAS TEMPORALES Y OPERATIVAS)
-- ============================================================================
-- Implementación de reglas basadas en el paso del tiempo (R16, R17).
-- Estos SPs están diseñados para ser ejecutados por un demonio (cron) periódicamente.
-- ============================================================================

-- ============================================================================
-- R16 / P2. sp_EscalarIncidente
-- Control de SLA: Si un incidente supera el tiempo máximo, cambia a "Escalado"
-- y aumenta su gravedad (lo que a su vez recalcula su prioridad por los triggers).
-- ============================================================================
CREATE OR REPLACE PROCEDURE sp_EscalarIncidente()
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado_escalado INT;
BEGIN
    SELECT id_estado_incidente INTO v_estado_escalado FROM EstadoIncidente WHERE nombre = 'Escalado';

    UPDATE Incidente
    SET 
        fk_gravedad_id = LEAST(fk_gravedad_id + 1, 5),
        fk_estado_incidente_id = v_estado_escalado
    WHERE id_incidente IN (
        SELECT id_incidente 
        FROM vIncidentesActivos 
        WHERE sla_incumplido = TRUE
    )
    AND fk_estado_incidente_id <> v_estado_escalado;

END;
$$;


-- ============================================================================
-- R17. sp_ReactivarRecursos
-- Reactivación automática: Un recurso "Fuera de servicio" vuelve a "Disponible"
-- tras superar los minutos definidos en MINUTOS_REACTIVACION_RECURSO.
-- Se ancla a la ÚLTIMA salida registrada en el Log (MAX timestamp) para evitar
-- que una salida vieja de un ciclo anterior dispare la reactivación de inmediato.
-- ============================================================================
CREATE OR REPLACE PROCEDURE sp_ReactivarRecursos()
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado_fuera INT;
    v_estado_disponible INT;
    v_minutos NUMERIC;
BEGIN
    SELECT id_estado_recurso INTO v_estado_fuera FROM EstadoRecurso WHERE nombre = 'Fuera de servicio';
    SELECT id_estado_recurso INTO v_estado_disponible FROM EstadoRecurso WHERE nombre = 'Disponible';

    SELECT COALESCE(
        (SELECT numero FROM ParametrosSistema WHERE nombre_parametro = 'MINUTOS_REACTIVACION_RECURSO'),
        60
    ) INTO v_minutos;

    UPDATE Recurso r
    SET fk_estado_recurso_id = v_estado_disponible
    WHERE fk_estado_recurso_id = v_estado_fuera
      AND (
          SELECT MAX(l.timestamp)
          FROM Log l
          WHERE l.tablaAfectada = 'recurso'
            AND l.idTablaAfectada = r.id_recurso
            AND l.operacion = 'UPDATE'
            AND (l.detalle->'despues'->>'fk_estado_recurso_id')::int = v_estado_fuera
      ) <= CURRENT_TIMESTAMP - (v_minutos * INTERVAL '1 minute');
END;
$$;