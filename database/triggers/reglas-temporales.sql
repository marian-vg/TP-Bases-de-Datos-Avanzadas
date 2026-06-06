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
-- Reactivación automática: solo los recursos temporalmente inhabilitados por
-- acumulación de penalizaciones vuelven a "Disponible" al llegar su fecha programada.
-- Otros recursos "Fuera de servicio" quedan fuera del alcance de R17.
-- ============================================================================
CREATE OR REPLACE PROCEDURE sp_ReactivarRecursos()
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado_fuera INT;
    v_estado_disponible INT;
BEGIN
    SELECT id_estado_recurso INTO v_estado_fuera FROM EstadoRecurso WHERE nombre = 'Fuera de servicio';
    SELECT id_estado_recurso INTO v_estado_disponible FROM EstadoRecurso WHERE nombre = 'Disponible';

    UPDATE Recurso r
    SET fk_estado_recurso_id = v_estado_disponible
    WHERE r.fk_estado_recurso_id = v_estado_fuera
      AND EXISTS (
          SELECT 1
          FROM InhabilitacionRecurso ir
          WHERE ir.fk_recurso_id = r.id_recurso
            AND ir.fecha_reactivado IS NULL
            AND ir.fecha_reactivacion_programada <= CURRENT_TIMESTAMP
      );
END;
$$;
