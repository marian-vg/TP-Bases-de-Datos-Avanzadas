-- ============================================================================
-- R20. Control de capacidad del sistema
-- Si el número de incidentes activos supera el umbral configurado, los nuevos 
-- incidentes se fuerzan al estado "Pendiente" (En espera) para no colapsar.
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_control_capacidad()
RETURNS TRIGGER AS $$
DECLARE
    v_incidentes_activos INT;
    v_umbral INT;
    v_estado_pendiente INT;
BEGIN

    SELECT COALESCE(
        (SELECT numero FROM ParametrosSistema WHERE nombre_parametro = 'UMBRAL_INCIDENTES_ACTIVOS'),
        100
    ) INTO v_umbral;

    SELECT count(*)
    INTO v_incidentes_activos
    FROM Incidente i
    JOIN EstadoIncidente ei ON i.fk_estado_incidente_id = ei.id_estado_incidente
    WHERE ei.nombre IN ('Pendiente', 'En proceso', 'Escalado');

    IF v_incidentes_activos >= v_umbral THEN
        SELECT id_estado_incidente INTO v_estado_pendiente 
        FROM EstadoIncidente 
        WHERE nombre = 'Pendiente';
        
        NEW.fk_estado_incidente_id := v_estado_pendiente;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_control_capacidad ON Incidente;
CREATE TRIGGER trg_control_capacidad
BEFORE INSERT ON Incidente
FOR EACH ROW
EXECUTE FUNCTION fn_control_capacidad();