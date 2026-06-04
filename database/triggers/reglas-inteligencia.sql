-- =============================================================================================================
-- REGLAS DE INTELIGENCIA — Smart City (PostgreSQL 16)
-- =============================================================================================================
--
-- Implementación de R12, R13, R14 y R15.
-- 
-- Mapa de reglas:
--   R12: Priorización automática por gravedad (Gravedad * 10).
--   R13: Bonus de prioridad por ocurrir en zonas de alto riesgo.
--   R14: Selección del mejor recurso mediante sistema de puntajes histórico.
--   R15: Rebalanceo automático de recursos hacia zonas desabastecidas (sin romper R10).
--
-- Orden de carga: create-tables.sql -> carga-dataset.sql -> reglas-validadoras.sql ->
--                 reglas-inteligencia.sql -> reglas-automatizacion.sql
-- =============================================================================================================


-- =============================================================================================================
-- 1. fn_puntaje_por_penalizacion / trg_puntaje_por_penalizacion — R14 (resta)
-- =============================================================================================================

CREATE OR REPLACE FUNCTION fn_puntaje_por_penalizacion()
RETURNS TRIGGER AS $$
DECLARE
    v_resta INT;
BEGIN
    SELECT COALESCE(puntaje, 0)
    INTO v_resta
    FROM TipoPenalizacion
    WHERE id_tipo_penalizacion = NEW.fk_tipo_penalizacion_id;

    UPDATE Recurso
    SET puntaje = puntaje - v_resta
    WHERE id_recurso = NEW.fk_recurso_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_puntaje_por_penalizacion ON Penalizacion;
CREATE TRIGGER trg_puntaje_por_penalizacion
AFTER INSERT ON Penalizacion
FOR EACH ROW
EXECUTE FUNCTION fn_puntaje_por_penalizacion();


-- =============================================================================================================
-- 2. fn_puntaje_por_exito / trg_puntaje_por_exito — R14 (suma: éxito + racha + SLA)
-- =============================================================================================================
--
-- Se dispara SOLO en la transición estado_exito -> TRUE. Es deliberado: la Rama 1 de
-- fn_asignacion_finalizada (R4) cierra las asignaciones FALLIDAS seteando timestamp_finalizacion,
-- así que gatillar por la finalización premiaría a un fracaso. Gatillando por el éxito, un fallo
-- nunca entra acá, aunque haya llegado dentro del SLA.
--
-- En el momento del éxito suma, en un único UPDATE:
--   a) +1 base.
--   b) +1 de racha si la cantidad de éxitos consecutivos del recurso es múltiplo de 3.
--   c) + id_gravedad si la asignación cumplió el SLA (requiere timestamp_llegada cargado).

CREATE OR REPLACE FUNCTION fn_puntaje_por_exito()
RETURNS TRIGGER AS $$
DECLARE
    v_racha        INT;
    v_bonus_racha  INT := 0;
    v_bonus_sla    INT := 0;
    v_gravedad     INT;
    v_sla_minutos  INT;
    v_minutos      NUMERIC;
BEGIN
    IF OLD.estado_exito IS DISTINCT FROM TRUE AND NEW.estado_exito = TRUE THEN

        -- b) Racha: cuántos éxitos consecutivos lleva el recurso. Como el motor nunca le da una
        --    asignación nueva mientras tenga otra abierta, las asignaciones de un recurso son
        --    secuenciales y el id_asignacion refleja su orden. Contamos los éxitos posteriores
        --    a su último fallo; la fila recién marcada (NEW) ya es visible y entra en la cuenta.
        SELECT count(*)
        INTO v_racha
        FROM Asignacion
        WHERE fk_recurso_id = NEW.fk_recurso_id
          AND estado_exito = TRUE
          AND id_asignacion > COALESCE(
              (SELECT max(id_asignacion)
               FROM Asignacion
               WHERE fk_recurso_id = NEW.fk_recurso_id
                 AND estado_exito = FALSE),
              0
          );

        IF v_racha > 0 AND (v_racha % 3) = 0 THEN
            v_bonus_racha := 1;
        END IF;

        -- c) SLA: solo si el operador cargó la llegada. Comparamos el tiempo de respuesta real
        --    (asignación -> llegada) contra el SLA pactado para la gravedad del incidente.
        SELECT i.fk_gravedad_id, s.tiempo_respuesta_minutos
        INTO v_gravedad, v_sla_minutos
        FROM Incidente i
        JOIN SLA s ON s.fk_gravedad_id = i.fk_gravedad_id
        WHERE i.id_incidente = NEW.fk_incidente_id;

        IF NEW.timestamp_llegada IS NOT NULL AND v_sla_minutos IS NOT NULL THEN
            v_minutos := EXTRACT(EPOCH FROM (NEW.timestamp_llegada - NEW.timestamp_asignacion)) / 60;
            IF v_minutos <= v_sla_minutos THEN
                v_bonus_sla := v_gravedad;   -- a mayor gravedad atendida a tiempo, mayor premio
            END IF;
        END IF;

        -- a) +1 base, más los bonus calculados. Un solo UPDATE.
        UPDATE Recurso
        SET puntaje = puntaje + 1 + v_bonus_racha + v_bonus_sla
        WHERE id_recurso = NEW.fk_recurso_id;

    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_puntaje_por_exito ON Asignacion;
CREATE TRIGGER trg_puntaje_por_exito
AFTER UPDATE ON Asignacion
FOR EACH ROW
EXECUTE FUNCTION fn_puntaje_por_exito();

-- =============================================================================================================
-- 3. fn_prioridad_incidente / trg_prioridad_incidente — R12 y R13
-- =============================================================================================================

CREATE OR REPLACE FUNCTION fn_prioridad_incidente()
RETURNS TRIGGER AS $$
DECLARE
    v_bonus NUMERIC := 0;
    v_riesgo_valor INT;
BEGIN
    -- R12: La prioridad base es la gravedad multiplicada por 10 (ej. Gravedad 3 -> Prioridad 30)
    NEW.prioridad := NEW.fk_gravedad_id * 10;

    -- R13: Evaluamos el nivel de riesgo de la zona
    SELECT nr.valor INTO v_riesgo_valor
    FROM Zona z
    JOIN NivelRiesgo nr ON z.fk_nivel_riesgo_id = nr.id_nivel_riesgo
    WHERE z.id_zona = NEW.fk_zona_id;

    -- Si la zona es de alto riesgo (valor >= 3), aplicamos el bonus
    IF v_riesgo_valor >= 3 THEN
        SELECT COALESCE(
            (SELECT numero FROM ParametrosSistema WHERE nombre_parametro = 'BONUS_PRIORIDAD_ZONA_RIESGO'),
            10
        ) INTO v_bonus;
        
        NEW.prioridad := NEW.prioridad + v_bonus;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_prioridad_incidente ON Incidente;
CREATE TRIGGER trg_prioridad_incidente
BEFORE INSERT OR UPDATE OF fk_gravedad_id, fk_zona_id ON Incidente
FOR EACH ROW
EXECUTE FUNCTION fn_prioridad_incidente();


-- =============================================================================================================
-- 4. fn_rebalanceo_recursos / trg_rebalanceo_recursos — R15
-- =============================================================================================================

CREATE OR REPLACE FUNCTION fn_rebalanceo_recursos()
RETURNS TRIGGER AS $$
DECLARE
    v_zona_recurso RECORD;
    v_disponibles INT;
    v_recurso_prestado INT;
BEGIN
    -- Solo actuamos si el recurso dejó de estar 'Disponible'
    IF OLD.fk_estado_recurso_id = 1 AND NEW.fk_estado_recurso_id <> 1 THEN
        
        -- Analizamos TODAS las zonas en las que este recurso operaba
        FOR v_zona_recurso IN (SELECT id_zona FROM ZonaRecurso WHERE id_recurso = NEW.id_recurso) LOOP
            
            -- Verificamos cuántos recursos disponibles de este MISMO TIPO quedan en la zona afectada
            SELECT COUNT(r.id_recurso) INTO v_disponibles
            FROM Recurso r
            JOIN ZonaRecurso zr ON r.id_recurso = zr.id_recurso
            WHERE zr.id_zona = v_zona_recurso.id_zona
              AND r.fk_tipo_recurso_id = NEW.fk_tipo_recurso_id
              AND r.fk_estado_recurso_id = 1;

            -- Si la zona se quedó sin cobertura para este tipo de emergencia, rebalanceamos
            IF v_disponibles = 0 THEN
                
                -- Buscamos un reemplazo del mismo tipo, priorizando zonas de bajo riesgo y luego el mejor puntaje (R14)
                SELECT r.id_recurso INTO v_recurso_prestado
                FROM Recurso r
                JOIN Zona z ON r.fk_zona_base_id = z.id_zona
                JOIN NivelRiesgo nr ON z.fk_nivel_riesgo_id = nr.id_nivel_riesgo
                WHERE r.fk_tipo_recurso_id = NEW.fk_tipo_recurso_id
                  AND r.fk_estado_recurso_id = 1
                  AND NOT EXISTS (
                      SELECT 1 FROM ZonaRecurso zr2 
                      WHERE zr2.id_recurso = r.id_recurso AND zr2.id_zona = v_zona_recurso.id_zona
                  )
                ORDER BY nr.valor ASC, r.puntaje DESC
                LIMIT 1;

                -- Insertamos el permiso de zona y logueamos la decisión automática
                IF v_recurso_prestado IS NOT NULL THEN
                    INSERT INTO ZonaRecurso (id_zona, id_recurso)
                    VALUES (v_zona_recurso.id_zona, v_recurso_prestado);

                    INSERT INTO Log (tablaAfectada, idTablaAfectada, operacion, trigger_disparador, detalle)
                    VALUES (
                        'ZonaRecurso', 
                        v_recurso_prestado, 
                        'INSERT', 
                        TG_NAME, 
                        jsonb_build_object(
                            'motivo', 'R15: Rebalanceo automático por agotamiento de recursos tipo ' || NEW.fk_tipo_recurso_id,
                            'zona_desabastecida', v_zona_recurso.id_zona,
                            'recurso_prestado', v_recurso_prestado
                        )
                    );
                END IF;
                
            END IF;
        END LOOP;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_rebalanceo_recursos ON Recurso;
CREATE TRIGGER trg_rebalanceo_recursos
AFTER UPDATE OF fk_estado_recurso_id ON Recurso
FOR EACH ROW
EXECUTE FUNCTION fn_rebalanceo_recursos();