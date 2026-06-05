-- =============================================================================================================
-- DOCUMENTACION
-- =============================================================================================================
--
-- NOTA: en la carpeta /documentacion deje apuntes sobre las variables especiales de pl/pgsql
-- y tambien extras como el marcador de posicion "%"
-- "%" -> marcador de posicion para dar formato dinamico y mas friendly a los mensajes de error.
--
-- Este script unifica las reglas validadoras de negocio del Smart City por tabla para optimizar
-- el rendimiento y evitar redundancia de consultas en la base de datos.
--
-- =============================================================================================================

-- =============================================================================================================
-- 0. LIMPIEZA DE TRIGGERS Y FUNCIONES INDIVIDUALES ANTERIORES (OBSOLETOS)
-- =============================================================================================================
-- DROP TRIGGER IF EXISTS trg_valida_disponibilidad_recurso ON Asignacion;
-- DROP TRIGGER IF EXISTS trg_valida_zona_recurso ON Asignacion;
-- DROP TRIGGER IF EXISTS trg_valida_coherencia_estados_incidente ON Incidente;
-- DROP TRIGGER IF EXISTS trg_valida_duplicacion_incidente ON Incidente;

-- DROP FUNCTION IF EXISTS fn_valida_disponibilidad_recurso();
-- DROP FUNCTION IF EXISTS fn_valida_zona_recurso();
-- DROP FUNCTION IF EXISTS fn_valida_coherencia_estados_incidente();
-- DROP FUNCTION IF EXISTS fn_valida_duplicacion_incidente();
-- =============================================================================================================
-- 1. INTEGRIDAD DE ASIGNACIONES (Unifica R8 y R10 + validación de tipo)
-- =============================================================================================================
--
-- R8. Validación de disponibilidad de recursos: No se podrá asignar un recurso que ya esté ocupado.
-- R10. Validación de zona del recurso: Un recurso solo podrá asignarse a incidentes dentro de su zona habilitada.
-- Tipo. Validación de integridad: el tipo de recurso debe ser aplicable al tipo de incidente
--       (TipoIncidenteTipoRecurso). Rescatada de create-triggers al unificar las validaciones aquí.
--
-- TOC -> BEFORE INSERT OR UPDATE
-- Granularidad -> FOR EACH ROW
--
-- Naming -> fn_valida_registro_asignacion y trg_valida_registro_asignacion

CREATE OR REPLACE FUNCTION fn_valida_registro_asignacion()
RETURNS TRIGGER AS $$
DECLARE
    v_estado_nombre VARCHAR(50);
    v_tipo_recurso INT;
    v_zona_incidente INT;
    v_tipo_incidente INT;
BEGIN
    IF TG_OP = 'UPDATE'
        AND OLD.fk_recurso_id = NEW.fk_recurso_id
        AND OLD.fk_incidente_id = NEW.fk_incidente_id THEN
            RETURN NEW;
    END IF;

    SELECT EstadoRecurso.nombre, Recurso.fk_tipo_recurso_id
    INTO v_estado_nombre, v_tipo_recurso
    FROM Recurso
    JOIN EstadoRecurso ON Recurso.fk_estado_recurso_id = EstadoRecurso.id_estado_recurso
    WHERE Recurso.id_recurso = NEW.fk_recurso_id
    FOR UPDATE OF Recurso;

    SELECT Incidente.fk_zona_id, Incidente.fk_tipo_incidente_id
    INTO v_zona_incidente, v_tipo_incidente
    FROM Incidente
    WHERE Incidente.id_incidente = NEW.fk_incidente_id;

    IF v_estado_nombre IS DISTINCT FROM 'Disponible' THEN
        RAISE EXCEPTION 'No se puede asignar el recurso % porque no se encuentra disponible (Estado: %).',
            NEW.fk_recurso_id, v_estado_nombre;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM Asignacion
        WHERE Asignacion.fk_recurso_id = NEW.fk_recurso_id
          AND Asignacion.timestamp_finalizacion IS NULL
          AND Asignacion.id_asignacion IS DISTINCT FROM NEW.id_asignacion
    ) THEN
        RAISE EXCEPTION 'No se puede asignar el recurso % porque ya cuenta con una asignación activa en curso.',
            NEW.fk_recurso_id;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM TipoIncidenteTipoRecurso
        WHERE TipoIncidenteTipoRecurso.fk_tipo_incidente_id = v_tipo_incidente
          AND TipoIncidenteTipoRecurso.fk_tipo_recurso_id = v_tipo_recurso
    ) THEN
        RAISE EXCEPTION 'El recurso % (tipo %) no es aplicable a un incidente de tipo %.',
            NEW.fk_recurso_id, v_tipo_recurso, v_tipo_incidente;
    END IF;

    IF COALESCE(current_setting('my.bypass_zona', true), '') IS DISTINCT FROM '1' THEN
        IF NOT EXISTS (
            SELECT 1
            FROM ZonaRecurso
            WHERE ZonaRecurso.id_recurso = NEW.fk_recurso_id
              AND ZonaRecurso.id_zona = v_zona_incidente
        ) THEN
            RAISE EXCEPTION 'El recurso % no está habilitado para operar en la zona del incidente (Zona %).',
                NEW.fk_recurso_id, v_zona_incidente;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_valida_registro_asignacion ON Asignacion;
CREATE TRIGGER trg_valida_registro_asignacion
BEFORE INSERT OR UPDATE OF fk_recurso_id, fk_incidente_id ON Asignacion
FOR EACH ROW
EXECUTE FUNCTION fn_valida_registro_asignacion();

-- =============================================================================================================
-- 2. CONSISTENCIA DE INCIDENTES (Unifica R9 y R11)
-- =============================================================================================================

CREATE OR REPLACE FUNCTION fn_valida_registro_incidente()
RETURNS TRIGGER AS $$
DECLARE
    v_minutos_duplicado NUMERIC;
    v_estado_old VARCHAR(50);
    v_estado_new VARCHAR(50);
BEGIN
    IF TG_OP = 'INSERT' OR (
        TG_OP = 'UPDATE' AND (
            OLD.fk_zona_id IS DISTINCT FROM NEW.fk_zona_id OR
            OLD.fk_tipo_incidente_id IS DISTINCT FROM NEW.fk_tipo_incidente_id
        )
    ) THEN
        SELECT ParametrosSistema.numero
        INTO v_minutos_duplicado
        FROM ParametrosSistema
        WHERE ParametrosSistema.nombre_parametro = 'MINUTOS_DUPLICADO_INCIDENTE';

        v_minutos_duplicado := COALESCE(v_minutos_duplicado, 10);

        IF EXISTS (
            SELECT 1
            FROM Incidente
            JOIN EstadoIncidente ON Incidente.fk_estado_incidente_id = EstadoIncidente.id_estado_incidente
            WHERE Incidente.fk_zona_id = NEW.fk_zona_id
              AND Incidente.fk_tipo_incidente_id = NEW.fk_tipo_incidente_id
              AND EstadoIncidente.nombre IS DISTINCT FROM 'Cancelado'
              AND Incidente.fecha_hora_registro >= CURRENT_TIMESTAMP - (v_minutos_duplicado * INTERVAL '1 minute')
              AND (TG_OP = 'INSERT' OR Incidente.id_incidente IS DISTINCT FROM NEW.id_incidente)
        ) THEN
            RAISE EXCEPTION 'Ya existe un incidente activo del mismo tipo en la zona dentro de los últimos % minutos.',
                v_minutos_duplicado;
        END IF;
    END IF;

    IF TG_OP = 'UPDATE' AND OLD.fk_estado_incidente_id IS DISTINCT FROM NEW.fk_estado_incidente_id THEN
        SELECT EstadoIncidente.nombre
        INTO v_estado_old
        FROM EstadoIncidente
        WHERE EstadoIncidente.id_estado_incidente = OLD.fk_estado_incidente_id;

        SELECT EstadoIncidente.nombre
        INTO v_estado_new
        FROM EstadoIncidente
        WHERE EstadoIncidente.id_estado_incidente = NEW.fk_estado_incidente_id;

        IF v_estado_old IN ('Resuelto', 'Cancelado') THEN
            RAISE EXCEPTION 'No se permite modificar el estado de un incidente que ya ha sido Resuelto o Cancelado.';
        END IF;

        IF v_estado_old = 'Pendiente' AND v_estado_new = 'Resuelto' THEN
            RAISE EXCEPTION 'Transición de estado inválida: No se puede pasar de Pendiente directamente a Resuelto.';
        END IF;

        IF NOT (
            (v_estado_old = 'Pendiente' AND v_estado_new IN ('En proceso', 'Escalado', 'Cancelado'))
            OR
            (v_estado_old = 'En proceso' AND v_estado_new IN ('Resuelto', 'Escalado', 'Cancelado'))
            OR
            (v_estado_old = 'Escalado' AND v_estado_new IN ('En proceso', 'Resuelto', 'Cancelado'))
        ) THEN
            RAISE EXCEPTION 'Transición de estado de incidente no permitida por regla de negocio: % -> %',
                v_estado_old, v_estado_new;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_valida_registro_incidente ON Incidente;
CREATE TRIGGER trg_valida_registro_incidente
BEFORE INSERT OR UPDATE ON Incidente
FOR EACH ROW
EXECUTE FUNCTION fn_valida_registro_incidente();
