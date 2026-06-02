-- =============================================================================================================
-- DOCUMENTACION
-- =============================================================================================================
--
-- NOTA: en la carpeta /documentacion deje apuntes sobre las variables especiales de pl/pgsql 
-- y tambien extras como el marcador de posicion "%"
-- "%" -> marcador de posicion para dar formato dinamico y mas friendly a los mensajes de error.


-- =============================================================================================================
-- R8. Validación de disponibilidad de recursos
-- No se podrá asignar un recurso que ya esté ocupado.
--
-- TOC -> BEFORE.
-- Granularidad -> FOR EACH ROW.
-- FOR UPDATE -> evitar problemas de concurrencia mediante el bloqueo de la fila.
-- TG_OP -> variable especial que nos da PL/pgsql para ver la accion DML que disparo el trigger.

CREATE OR REPLACE FUNCTION fn_valida_disponibilidad_recurso()
RETURNS TRIGGER AS $$
DECLARE
    v_estado_nombre VARCHAR(50);
BEGIN
    -- Si es un UPDATE y no cambia el recurso asignado, no es necesario validar disponibilidad.
    IF TG_OP = 'UPDATE'
        AND OLD.fk_recurso_id = NEW.fk_recurso_id THEN
            RETURN NEW;
    END IF;

    SELECT EstadoRecurso.nombre 
    INTO v_estado_nombre
    FROM Recurso
    JOIN EstadoRecurso ON Recurso.fk_estado_recurso_id = EstadoRecurso.id_estado_recurso
    WHERE Recurso.id_recurso = NEW.fk_recurso_id
    FOR UPDATE;

    -- Validamos la disponibilidad.
    IF v_estado_nombre IS DISTINCT FROM 'Disponible' THEN
        RAISE EXCEPTION 'No se puede asignar el recurso % porque no se encuentra disponible.', 
            NEW.fk_recurso_id;
    END IF;

    -- Validamos que no este en una asignacion activa.
    IF EXISTS (
        SELECT 1 
        FROM Asignacion 
        WHERE fk_recurso_id = NEW.fk_recurso_id 
          AND timestamp_finalizacion IS NULL
          AND id_asignacion IS DISTINCT FROM NEW.id_asignacion
    ) THEN
        RAISE EXCEPTION 'No se puede asignar el recurso % porque ya cuenta con una asignación activa en curso.', 
            NEW.fk_recurso_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_valida_disponibilidad_recurso
BEFORE INSERT OR UPDATE OF fk_recurso_id ON Asignacion
FOR EACH ROW
EXECUTE FUNCTION fn_valida_disponibilidad_recurso();

-- =============================================================================================================

-- R9. Validación de coherencia de estados
-- Se deberán evitar cambios de estado inválidos.
--
-- TOC -> BEFORE
-- Granularidad -> FOR EACH ROW
--
-- Las dos primeras condicionales son para determinar los cambios mas criticos de transiciones
-- y para retornar un mensaje apropiado a las mismas.

CREATE OR REPLACE FUNCTION fn_valida_coherencia_estados_incidente()
RETURNS TRIGGER AS $$
DECLARE
    v_estado_old VARCHAR(50);
    v_estado_new VARCHAR(50);
BEGIN
    IF OLD.fk_estado_incidente_id IS DISTINCT FROM NEW.fk_estado_incidente_id THEN
        
        -- Obtener los nombres de los estados involucrados
        SELECT nombre 
        INTO v_estado_old 
        FROM EstadoIncidente 
        WHERE id_estado_incidente = OLD.fk_estado_incidente_id;

        SELECT nombre 
        INTO v_estado_new 
        FROM EstadoIncidente 
        WHERE id_estado_incidente = NEW.fk_estado_incidente_id;

        -- No se puede modificar el estado si ya está 'Resuelto' o 'Cancelado'.
        IF v_estado_old = 'Resuelto' OR v_estado_old = 'Cancelado' THEN
            RAISE EXCEPTION 'No se permite modificar el estado de un incidente que ya ha sido Resuelto o Cancelado.';
        END IF;
        
        -- No se puede pasar de 'Pendiente' directamente a 'Resuelto'.
        IF v_estado_old = 'Pendiente' AND v_estado_new = 'Resuelto' THEN
            RAISE EXCEPTION 'Transición de estado inválida: No se puede pasar de Pendiente directamente a Resuelto.';
        END IF;

        -- Validacion mediante una whitelist sobre el resto de transiciones de estados.

        -- Pendiente -> En proceso, Escalado, En espera, Cancelado
        -- En proceso -> Resuelto, Escalado, Cancelado
        -- Escalado -> En proceso, Resuelto, Cancelado
        -- En espera -> Pendiente, En proceso, Cancelado

        IF NOT (
            (v_estado_old = 'Pendiente' AND v_estado_new IN ('En proceso', 'Escalado', 'En espera', 'Cancelado')) 
            OR
            (v_estado_old = 'En proceso' AND v_estado_new IN ('Resuelto', 'Escalado', 'Cancelado')) 
            OR
            (v_estado_old = 'Escalado' AND v_estado_new IN ('En proceso', 'Resuelto', 'Cancelado')) 
            OR
            (v_estado_old = 'En espera' AND v_estado_new IN ('Pendiente', 'En proceso', 'Cancelado'))
        ) THEN
            RAISE EXCEPTION 'Transición de estado de incidente no permitida por regla de negocio: % -> %', 
                v_estado_old, v_estado_new;
        END IF;

    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_valida_coherencia_estados_incidente
BEFORE UPDATE OF fk_estado_incidente_id ON Incidente
FOR EACH ROW
EXECUTE FUNCTION fn_valida_coherencia_estados_incidente();

-- =============================================================================================================

-- R10. Validación de zona del recurso
-- Un recurso solo podrá asignarse a incidentes dentro de su zona habilitada.

-- =============================================================================================================

-- R11. Validación de duplicación de incidentes
-- Se deberá evitar registrar incidentes duplicados en un corto período (misma zona y tipo).