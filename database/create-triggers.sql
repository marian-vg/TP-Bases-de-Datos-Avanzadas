-- ============================================================================
-- TRIGGERS Y PROCEDIMIENTOS - SMART CITY
-- ============================================================================
--
-- Convención de estados usada en todo el archivo:
--   EstadoIncidente: 1 Pendiente | 2 En proceso | 3 Resuelto | 4 Escalado | 5 Cancelado
--                    (terminales: 3 y 5)
--   EstadoRecurso:   1 Disponible | 2 Ocupado | 3 Fuera de servicio | 4 En mantenimiento | 5 En tránsito
--
-- Variables de sesión transaccionales (set_config con is_local = true):
--   my.trigger_disparador -> nombre del trigger/proc que originó la mutación (NULL = acción manual)
--   my.bypass_zona        -> '1' habilita un rebalanceo de emergencia (R15) sin polucionar ZonaRecurso
--
-- La documentación de cada bloque está al pie del archivo.
-- ============================================================================


-- ============================================================================
-- 1. AUDITORÍA CENTRALIZADA UNIFICADA (R3 & R18 & R19)
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_auditoria_centralizada()
RETURNS TRIGGER AS $$
DECLARE
    v_trigger_disparador VARCHAR(100);
    v_detalle JSONB;
    v_id_afectado BIGINT;
BEGIN
    v_trigger_disparador := NULLIF(current_setting('my.trigger_disparador', true), '');

    IF (TG_OP = 'INSERT') THEN
        v_detalle := jsonb_build_object('new', to_jsonb(NEW));
    ELSIF (TG_OP = 'UPDATE') THEN
        v_detalle := jsonb_build_object('old', to_jsonb(OLD), 'new', to_jsonb(NEW));
    ELSE
        v_detalle := jsonb_build_object('old', to_jsonb(OLD));
    END IF;

    -- Resolver la PK del registro afectado según la tabla y la operación
    IF (TG_OP = 'DELETE') THEN
        CASE LOWER(TG_TABLE_NAME)
            WHEN 'incidente'    THEN v_id_afectado := OLD.id_incidente;
            WHEN 'asignacion'   THEN v_id_afectado := OLD.id_asignacion;
            WHEN 'recurso'      THEN v_id_afectado := OLD.id_recurso;
            WHEN 'penalizacion' THEN v_id_afectado := OLD.id_penalizacion;
            WHEN 'sensor'       THEN v_id_afectado := OLD.id_sensor;
            WHEN 'evento'       THEN v_id_afectado := OLD.id_evento;
            ELSE v_id_afectado := 0;
        END CASE;
    ELSE
        CASE LOWER(TG_TABLE_NAME)
            WHEN 'incidente'    THEN v_id_afectado := NEW.id_incidente;
            WHEN 'asignacion'   THEN v_id_afectado := NEW.id_asignacion;
            WHEN 'recurso'      THEN v_id_afectado := NEW.id_recurso;
            WHEN 'penalizacion' THEN v_id_afectado := NEW.id_penalizacion;
            WHEN 'sensor'       THEN v_id_afectado := NEW.id_sensor;
            WHEN 'evento'       THEN v_id_afectado := NEW.id_evento;
            ELSE v_id_afectado := 0;
        END CASE;
    END IF;

    INSERT INTO Log (tablaAfectada, idTablaAfectada, operacion, trigger_disparador, detalle)
    VALUES (TG_TABLE_NAME, v_id_afectado, TG_OP, v_trigger_disparador, v_detalle);

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tg_audit_incidente AFTER INSERT OR UPDATE OR DELETE ON Incidente
FOR EACH ROW EXECUTE FUNCTION fn_auditoria_centralizada();

CREATE TRIGGER tg_audit_asignacion AFTER INSERT OR UPDATE OR DELETE ON Asignacion
FOR EACH ROW EXECUTE FUNCTION fn_auditoria_centralizada();

CREATE TRIGGER tg_audit_recurso AFTER INSERT OR UPDATE OR DELETE ON Recurso
FOR EACH ROW EXECUTE FUNCTION fn_auditoria_centralizada();

CREATE TRIGGER tg_audit_penalizacion AFTER INSERT OR UPDATE OR DELETE ON Penalizacion
FOR EACH ROW EXECUTE FUNCTION fn_auditoria_centralizada();

CREATE TRIGGER tg_audit_sensor AFTER INSERT OR UPDATE OR DELETE ON Sensor
FOR EACH ROW EXECUTE FUNCTION fn_auditoria_centralizada();

CREATE TRIGGER tg_audit_evento AFTER INSERT OR UPDATE OR DELETE ON Evento
FOR EACH ROW EXECUTE FUNCTION fn_auditoria_centralizada();


-- ============================================================================
-- 2. CIERRE DE ASIGNACIONES FALLIDAS (soporte operativo para R7)
-- ============================================================================
-- Las validaciones R8/R9/R10/R11 + la validación de tipo aplicable viven ahora en
-- database/triggers/reglas-validadoras.sql (funciones fn_valida_registro_asignacion y
-- fn_valida_registro_incidente). Aquí solo queda la lógica OPERATIVA que NO es validación:
-- al marcar una asignación como fallida (estado_exito = FALSE) sin cierre, fijamos
-- timestamp_finalizacion en este BEFORE para que R7 (cierre automático, AFTER) no cuente
-- la asignación fallida como "todavía activa".

CREATE OR REPLACE FUNCTION fn_cerrar_asignacion_fallida()
RETURNS TRIGGER AS $$
BEGIN
    IF (NEW.estado_exito IS NOT DISTINCT FROM FALSE AND NEW.timestamp_finalizacion IS NULL) THEN
        NEW.timestamp_finalizacion := CURRENT_TIMESTAMP;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tg_cerrar_asignacion_fallida BEFORE UPDATE ON Asignacion
FOR EACH ROW EXECUTE FUNCTION fn_cerrar_asignacion_fallida();


-- ============================================================================
-- 3. PRIORIZACIÓN AUTOMÁTICA DEL INCIDENTE (R12 & R13)
-- ============================================================================
-- Se calcula a nivel incidente (BEFORE INSERT), válido para cualquier origen
-- (IoT o carga manual). La prioridad provista por el llamador se ignora.

CREATE OR REPLACE FUNCTION fn_calcular_prioridad_incidente()
RETURNS TRIGGER AS $$
DECLARE
    v_riesgo_valor INT;
    v_bonus NUMERIC;
    v_prioridad INT;
BEGIN
    -- R12: prioridad base según gravedad
    v_prioridad := NEW.fk_gravedad_id * 10;

    -- R13: bonus si la zona es de alto riesgo (NivelRiesgo.valor >= 3)
    SELECT nr.valor INTO v_riesgo_valor
      FROM Zona z
      JOIN NivelRiesgo nr ON z.fk_nivel_riesgo_id = nr.id_nivel_riesgo
     WHERE z.id_zona = NEW.fk_zona_id;

    IF (COALESCE(v_riesgo_valor, 0) >= 3) THEN
        SELECT numero INTO v_bonus
          FROM ParametrosSistema WHERE nombre_parametro = 'BONUS_PRIORIDAD_ZONA_RIESGO';
        v_prioridad := v_prioridad + COALESCE(v_bonus, 10)::INT;
    END IF;

    NEW.prioridad := v_prioridad;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tg_prioridad_incidente BEFORE INSERT ON Incidente
FOR EACH ROW EXECUTE FUNCTION fn_calcular_prioridad_incidente();


-- ============================================================================
-- 4. CONTROL SANCIONATORIO (bloqueo de recurso por penalizaciones)
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_gestion_penalizaciones()
RETURNS TRIGGER AS $$
DECLARE
    v_total_puntos INT;
    v_umbral_bloqueo INT;
BEGIN
    PERFORM set_config('my.trigger_disparador', 'tg_gestion_penalizaciones', true);

    SELECT numero INTO v_umbral_bloqueo
      FROM ParametrosSistema WHERE nombre_parametro = 'PUNTAJE_BLOQUEO_RECURSO';
    v_umbral_bloqueo := COALESCE(v_umbral_bloqueo, 75);

    SELECT COALESCE(SUM(tp.puntaje), 0) INTO v_total_puntos
      FROM Penalizacion p
      JOIN TipoPenalizacion tp ON p.fk_tipo_penalizacion_id = tp.id_tipo_penalizacion
     WHERE p.fk_recurso_id = NEW.fk_recurso_id;

    IF (v_total_puntos >= v_umbral_bloqueo) THEN
        UPDATE Recurso
           SET fk_estado_recurso_id = 3  -- Fuera de servicio
         WHERE id_recurso = NEW.fk_recurso_id;

        INSERT INTO Log (tablaAfectada, idTablaAfectada, operacion, trigger_disparador, detalle)
        VALUES ('Recurso', NEW.fk_recurso_id, 'UPDATE', 'tg_gestion_penalizaciones',
            jsonb_build_object(
                'accion', 'Bloqueo automático por penalizaciones',
                'puntos_totales', v_total_puntos,
                'umbral', v_umbral_bloqueo));
    END IF;

    PERFORM set_config('my.trigger_disparador', '', true);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tg_penalizacion_bloqueo AFTER INSERT ON Penalizacion
FOR EACH ROW EXECUTE FUNCTION fn_gestion_penalizaciones();


-- ============================================================================
-- 5. MOTOR DE ASIGNACIÓN AUTOMÁTICA Y REBALANCEO (R1 & R5 & R14 & R15)
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_asignar_recursos_incidente(p_incidente_id INT)
RETURNS INT AS $$
DECLARE
    v_zona INT;
    v_gravedad INT;
    v_tipo INT;
    v_estado INT;
    v_grav_min INT;
    v_requeridos INT;
    v_asignados INT := 0;
    v_recurso_id INT;
    v_rebalanceo BOOLEAN;
BEGIN
    SELECT fk_zona_id, fk_gravedad_id, fk_tipo_incidente_id, fk_estado_incidente_id
      INTO v_zona, v_gravedad, v_tipo, v_estado
      FROM Incidente WHERE id_incidente = p_incidente_id;

    -- El incidente debe seguir activo (no terminal)
    IF NOT FOUND OR v_estado IN (3, 5) THEN
        RETURN 0;
    END IF;

    -- R5: los incidentes de gravedad alta requieren más de un recurso
    SELECT numero INTO v_grav_min
      FROM ParametrosSistema WHERE nombre_parametro = 'GRAVEDAD_MINIMA_CRITICA';
    v_grav_min := COALESCE(v_grav_min, 4);

    IF (v_gravedad >= v_grav_min) THEN
        SELECT numero INTO v_requeridos
          FROM ParametrosSistema WHERE nombre_parametro = 'MIN_RECURSOS_INCIDENTE_CRITICO';
        v_requeridos := COALESCE(v_requeridos, 2);
    ELSE
        v_requeridos := 1;
    END IF;

    SELECT COUNT(*) INTO v_asignados
      FROM Asignacion
     WHERE fk_incidente_id = p_incidente_id AND timestamp_finalizacion IS NULL;

    WHILE (v_asignados < v_requeridos) LOOP
        v_recurso_id := NULL;
        v_rebalanceo := FALSE;

        -- R14: mejor candidato local (tipo aplicable + habilitado en la zona),
        -- ordenado por menor penalización y menor carga histórica.
        SELECT rc.id_recurso INTO v_recurso_id
          FROM vRecursosCandidatos rc
          JOIN ZonaRecurso zr ON rc.id_recurso = zr.id_recurso AND zr.id_zona = v_zona
          JOIN Recurso r ON r.id_recurso = rc.id_recurso
          JOIN TipoIncidenteTipoRecurso titr
            ON titr.fk_tipo_recurso_id = r.fk_tipo_recurso_id AND titr.fk_tipo_incidente_id = v_tipo
         WHERE rc.id_recurso NOT IN (
                  SELECT fk_recurso_id FROM Asignacion WHERE fk_incidente_id = p_incidente_id)
         ORDER BY rc.puntos_penalizacion ASC, rc.cantidad_asignaciones_historicas ASC
         LIMIT 1;

        -- R15: rebalanceo geográfico. Sin candidato local, buscar el mejor a nivel global
        -- (manteniendo el filtro de tipo). No se asigna policía a un incendio.
        IF (v_recurso_id IS NULL) THEN
            SELECT rc.id_recurso INTO v_recurso_id
              FROM vRecursosCandidatos rc
              JOIN Recurso r ON r.id_recurso = rc.id_recurso
              JOIN TipoIncidenteTipoRecurso titr
                ON titr.fk_tipo_recurso_id = r.fk_tipo_recurso_id AND titr.fk_tipo_incidente_id = v_tipo
             WHERE rc.id_recurso NOT IN (
                      SELECT fk_recurso_id FROM Asignacion WHERE fk_incidente_id = p_incidente_id)
             ORDER BY rc.puntos_penalizacion ASC, rc.cantidad_asignaciones_historicas ASC
             LIMIT 1;
            v_rebalanceo := (v_recurso_id IS NOT NULL);
        END IF;

        EXIT WHEN v_recurso_id IS NULL;

        -- El rebalanceo habilita el alta saltando la validación de zona (R10) solo para este INSERT,
        -- sin contaminar ZonaRecurso de forma permanente.
        IF (v_rebalanceo) THEN
            PERFORM set_config('my.bypass_zona', '1', true);
            INSERT INTO Log (tablaAfectada, idTablaAfectada, operacion, trigger_disparador, detalle)
            VALUES ('Asignacion', 0, 'INSERT', 'fn_asignar_recursos_incidente',
                jsonb_build_object('accion', 'Rebalanceo geográfico (R15)',
                                   'recurso', v_recurso_id, 'zona_incidente', v_zona));
        END IF;

        INSERT INTO Asignacion (fk_recurso_id, fk_incidente_id)
        VALUES (v_recurso_id, p_incidente_id);

        IF (v_rebalanceo) THEN
            PERFORM set_config('my.bypass_zona', '', true);
        END IF;

        v_asignados := v_asignados + 1;
    END LOOP;

    RETURN v_asignados;
END;
$$ LANGUAGE plpgsql;


-- Despacha un recurso recién liberado al incidente Pendiente de mayor prioridad
-- que ese recurso pueda atender (tipo aplicable + habilitado en la zona). Backlog por prioridad.
CREATE OR REPLACE FUNCTION fn_despachar_recurso_backlog(p_recurso_id INT)
RETURNS VOID AS $$
DECLARE
    v_tipo_recurso INT;
    v_incidente_id INT;
BEGIN
    SELECT fk_tipo_recurso_id INTO v_tipo_recurso FROM Recurso WHERE id_recurso = p_recurso_id;

    SELECT i.id_incidente INTO v_incidente_id
      FROM Incidente i
      JOIN ZonaRecurso zr ON zr.id_recurso = p_recurso_id AND zr.id_zona = i.fk_zona_id
      JOIN TipoIncidenteTipoRecurso titr
        ON titr.fk_tipo_incidente_id = i.fk_tipo_incidente_id AND titr.fk_tipo_recurso_id = v_tipo_recurso
     WHERE i.fk_estado_incidente_id = 1  -- Pendiente (a la espera de recurso)
     ORDER BY i.prioridad DESC, i.fecha_hora_registro ASC
     LIMIT 1;

    IF (v_incidente_id IS NOT NULL) THEN
        INSERT INTO Asignacion (fk_recurso_id, fk_incidente_id)
        VALUES (p_recurso_id, v_incidente_id);
    END IF;
END;
$$ LANGUAGE plpgsql;


-- ============================================================================
-- 6. GESTIÓN OPERATIVA DE ASIGNACIONES (R2 & R4 & R7 & R8 & R9-pen)
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_gestion_asignacion_operativa()
RETURNS TRIGGER AS $$
DECLARE
    v_gravedad INT;
    v_minutos_sla INT;
    v_minutos_traslado NUMERIC;
    v_demora NUMERIC;
    v_tipo_pen INT;
    v_motivo TEXT;
BEGIN
    PERFORM set_config('my.trigger_disparador', 'tg_gestion_asignacion_operativa', true);

    SELECT fk_gravedad_id INTO v_gravedad
      FROM Incidente WHERE id_incidente = NEW.fk_incidente_id;

    -- 1) ALTA DE ASIGNACIÓN
    IF (TG_OP = 'INSERT') THEN
        -- R8: el recurso pasa a "En tránsito"
        UPDATE Recurso SET fk_estado_recurso_id = 5 WHERE id_recurso = NEW.fk_recurso_id;

        -- R2: el incidente pasa a "En proceso" cuando recibe su primer recurso
        UPDATE Incidente SET fk_estado_incidente_id = 2
         WHERE id_incidente = NEW.fk_incidente_id AND fk_estado_incidente_id = 1;
    END IF;

    -- 2) MODIFICACIÓN DE ASIGNACIÓN
    IF (TG_OP = 'UPDATE') THEN

        -- CASO A: arribo al lugar (se registra timestamp_llegada)
        IF (OLD.timestamp_llegada IS NULL AND NEW.timestamp_llegada IS NOT NULL) THEN
            -- R8: el recurso pasa a "Ocupado"
            UPDATE Recurso SET fk_estado_recurso_id = 2 WHERE id_recurso = NEW.fk_recurso_id;

            -- R9: penalización por exceso de tiempo de traslado respecto del SLA
            v_minutos_traslado := EXTRACT(EPOCH FROM (NEW.timestamp_llegada - NEW.timestamp_asignacion)) / 60;
            SELECT tiempo_respuesta_minutos INTO v_minutos_sla FROM SLA WHERE fk_gravedad_id = v_gravedad;

            IF (v_minutos_sla IS NOT NULL AND v_minutos_traslado > v_minutos_sla) THEN
                v_demora := v_minutos_traslado - v_minutos_sla;
                IF (v_demora <= 10) THEN
                    v_tipo_pen := 1;  -- Demora leve
                ELSIF (v_demora <= 30) THEN
                    v_tipo_pen := 2;  -- Demora moderada
                ELSE
                    v_tipo_pen := 3;  -- Demora grave
                END IF;
                v_motivo := 'Exceso de traslado: ' || ROUND(v_demora, 1) || ' min sobre un SLA de ' || v_minutos_sla || ' min.';
                INSERT INTO Penalizacion (fk_recurso_id, fk_tipo_penalizacion_id, motivo)
                VALUES (NEW.fk_recurso_id, v_tipo_pen, v_motivo);
            END IF;
        END IF;

        -- CASO B: finalización exitosa (se registra timestamp_finalizacion sin marcar fallo)
        IF (OLD.timestamp_finalizacion IS NULL AND NEW.timestamp_finalizacion IS NOT NULL
            AND NEW.estado_exito IS DISTINCT FROM FALSE) THEN
            -- R8: el recurso vuelve a "Disponible" si estaba Ocupado
            UPDATE Recurso SET fk_estado_recurso_id = 1
             WHERE id_recurso = NEW.fk_recurso_id AND fk_estado_recurso_id = 2;

            -- R7: si ya no quedan recursos activos, el incidente se Resuelve
            IF NOT EXISTS (
                SELECT 1 FROM Asignacion
                 WHERE fk_incidente_id = NEW.fk_incidente_id AND timestamp_finalizacion IS NULL
            ) THEN
                UPDATE Incidente SET fk_estado_incidente_id = 3  -- Resuelto
                 WHERE id_incidente = NEW.fk_incidente_id AND fk_estado_incidente_id NOT IN (3, 5);
            END IF;

            -- Backlog: el recurso liberado atiende al Pendiente de mayor prioridad que pueda
            IF EXISTS (SELECT 1 FROM Recurso WHERE id_recurso = NEW.fk_recurso_id AND fk_estado_recurso_id = 1) THEN
                PERFORM fn_despachar_recurso_backlog(NEW.fk_recurso_id);
            END IF;
        END IF;

        -- CASO C: asignación fallida (estado_exito = FALSE)  -> R4
        IF (COALESCE(OLD.estado_exito, TRUE) <> FALSE AND NEW.estado_exito = FALSE) THEN
            -- El recurso se libera (el cierre de la asignación lo fijó el trigger BEFORE)
            UPDATE Recurso SET fk_estado_recurso_id = 1 WHERE id_recurso = NEW.fk_recurso_id;

            IF (NEW.timestamp_llegada IS NULL) THEN
                v_tipo_pen := 6;  -- No respuesta
                v_motivo := 'El recurso no respondió al despacho (abandono en tránsito).';
            ELSE
                v_tipo_pen := 4;  -- Falla en intervención
                v_motivo := 'El recurso falló durante la intervención en el lugar.';
            END IF;
            INSERT INTO Penalizacion (fk_recurso_id, fk_tipo_penalizacion_id, motivo)
            VALUES (NEW.fk_recurso_id, v_tipo_pen, v_motivo);

            -- R4: despachar un reemplazo para el incidente
            PERFORM fn_asignar_recursos_incidente(NEW.fk_incidente_id);
        END IF;

    END IF;

    PERFORM set_config('my.trigger_disparador', '', true);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tg_gestion_asignacion AFTER INSERT OR UPDATE ON Asignacion
FOR EACH ROW EXECUTE FUNCTION fn_gestion_asignacion_operativa();


-- ============================================================================
-- 7. AUTOMATIZACIÓN DE INCIDENTES (R1 despacho + R20 control de capacidad)
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_gestion_incidente_automatizacion()
RETURNS TRIGGER AS $$
DECLARE
    v_activos INT;
    v_umbral INT;
BEGIN
    PERFORM set_config('my.trigger_disparador', 'tg_incidente_automatizacion', true);

    -- R20: control de capacidad. Si la cantidad de incidentes activos supera el umbral,
    -- el incidente queda Pendiente sin despacharse; lo levantará el backlog al liberarse capacidad.
    SELECT numero INTO v_umbral
      FROM ParametrosSistema WHERE nombre_parametro = 'UMBRAL_INCIDENTES_ACTIVOS';
    v_umbral := COALESCE(v_umbral, 50);

    SELECT COUNT(*) INTO v_activos FROM Incidente WHERE fk_estado_incidente_id NOT IN (3, 5);

    -- R1: si nace Pendiente y hay capacidad, se despachan recursos de inmediato
    IF (NEW.fk_estado_incidente_id = 1 AND v_activos <= v_umbral) THEN
        PERFORM fn_asignar_recursos_incidente(NEW.id_incidente);
    END IF;

    PERFORM set_config('my.trigger_disparador', '', true);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tg_incidente_auto_asignacion AFTER INSERT ON Incidente
FOR EACH ROW EXECUTE FUNCTION fn_gestion_incidente_automatizacion();


-- ============================================================================
-- 8. AUTOMATIZACIÓN DE SENSORES IoT (R21 confianza por mantenimiento)
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_gestion_evento_iot()
RETURNS TRIGGER AS $$
DECLARE
    v_zona INT;
    v_ultima_revision DATE;
    v_fecha_instalado DATE;
    v_decaimiento NUMERIC;
    v_umbral_min NUMERIC;
    v_semanas INT;
    v_confianza NUMERIC;
    v_tipo_incidente INT;
    v_gravedad INT;
    v_incidente_id INT;
BEGIN
    PERFORM set_config('my.trigger_disparador', 'tg_gestion_evento_iot', true);

    SELECT s.fk_zona_id, s.fecha_instalado INTO v_zona, v_fecha_instalado
      FROM Sensor s WHERE s.id_sensor = NEW.fk_sensor_id;

    -- Última revisión = MAX(fecha) del historial o, si nunca se mantuvo, la fecha de instalación
    SELECT MAX(fecha) INTO v_ultima_revision FROM MantenimientoSensor WHERE fk_sensor_id = NEW.fk_sensor_id;
    v_ultima_revision := COALESCE(v_ultima_revision, v_fecha_instalado);

    SELECT numero INTO v_decaimiento FROM ParametrosSistema WHERE nombre_parametro = 'SENSOR_DECAIMIENTO_CONFIANZA_SEMANAL';
    v_decaimiento := COALESCE(v_decaimiento, 5);
    SELECT numero INTO v_umbral_min FROM ParametrosSistema WHERE nombre_parametro = 'SENSOR_UMBRAL_CONFIANZA_MINIMO';
    v_umbral_min := COALESCE(v_umbral_min, 80);

    -- R21: confianza = 100 - decaimiento * semanas sin mantenimiento (piso 0)
    v_semanas := FLOOR((NEW.fecha_evento - v_ultima_revision) / 7);
    v_confianza := GREATEST(0, 100 - v_decaimiento * v_semanas);

    -- Solo se genera incidente si la confianza supera el umbral mínimo
    IF (v_confianza <= v_umbral_min) THEN
        INSERT INTO Log (tablaAfectada, idTablaAfectada, operacion, trigger_disparador, detalle)
        VALUES ('Evento', NEW.id_evento, 'INSERT', 'tg_gestion_evento_iot',
            jsonb_build_object('accion', 'Evento descartado por baja confianza del sensor',
                               'confianza', v_confianza, 'umbral_minimo', v_umbral_min));
        PERFORM set_config('my.trigger_disparador', '', true);
        RETURN NEW;
    END IF;

    -- Mapeo tipo de evento -> tipo de incidente + gravedad
    CASE NEW.fk_tipo_evento_id
        WHEN 1  THEN v_tipo_incidente := 2;  v_gravedad := 4;  -- Humo -> Incendio estructural
        WHEN 2  THEN v_tipo_incidente := 8;  v_gravedad := 3;  -- Gas -> Fuga de gas
        WHEN 3  THEN v_tipo_incidente := 5;  v_gravedad := 2;  -- Movimiento -> Robo / Asalto
        WHEN 4  THEN v_tipo_incidente := 4;  v_gravedad := 3;  -- Botón pánico -> Emergencia médica
        WHEN 5  THEN v_tipo_incidente := 7;  v_gravedad := 3;  -- Disparo -> Disturbios
        WHEN 6  THEN v_tipo_incidente := 2;  v_gravedad := 3;  -- Temperatura -> Incendio estructural
        WHEN 7  THEN v_tipo_incidente := 10; v_gravedad := 4;  -- Inundación -> Inundación urbana
        WHEN 8  THEN v_tipo_incidente := 11; v_gravedad := 5;  -- Vibración -> Derrumbe
        WHEN 9  THEN v_tipo_incidente := 13; v_gravedad := 2;  -- Calidad de aire -> Materiales peligrosos
        WHEN 10 THEN v_tipo_incidente := 9;  v_gravedad := 1;  -- Cámara caída -> Corte de energía
        ELSE         v_tipo_incidente := 4;  v_gravedad := 2;
    END CASE;

    -- Alta del incidente. La prioridad (R12/R13), el despacho (R1) y la capacidad (R20)
    -- los resuelven los triggers de la tabla Incidente. La prioridad provista es un placeholder.
    INSERT INTO Incidente (fk_evento_id, fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id,
                           fk_zona_id, descripcion, prioridad)
    VALUES (NEW.id_evento, v_tipo_incidente, v_gravedad, 1, v_zona,
            'Incidente generado automáticamente por sensor IoT (confianza ' || v_confianza || '%).', 0)
    RETURNING id_incidente INTO v_incidente_id;

    INSERT INTO Log (tablaAfectada, idTablaAfectada, operacion, trigger_disparador, detalle)
    VALUES ('Incidente', v_incidente_id, 'INSERT', 'tg_gestion_evento_iot',
        jsonb_build_object('accion', 'Incidente generado por IoT', 'confianza', v_confianza));

    PERFORM set_config('my.trigger_disparador', '', true);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tg_evento_iot AFTER INSERT ON Evento
FOR EACH ROW EXECUTE FUNCTION fn_gestion_evento_iot();


-- ============================================================================
-- 9. PROCEDIMIENTOS TEMPORALES (R16 & R17) - se invocan manualmente con CALL
-- ============================================================================

-- R16 / P2: control de SLA. Los incidentes "En proceso" vencidos pasan a "Escalado";
-- los "Pendiente" vencidos solo incrementan su prioridad (no escalan: aún no se atendían).
CREATE OR REPLACE PROCEDURE sp_escalar_incidente()
LANGUAGE plpgsql AS $$
DECLARE
    v_inc RECORD;
    v_minutos NUMERIC;
BEGIN
    PERFORM set_config('my.trigger_disparador', 'sp_escalar_incidente', true);

    FOR v_inc IN
        SELECT i.id_incidente, i.fk_estado_incidente_id, i.fecha_hora_registro, sla.tiempo_respuesta_minutos
          FROM Incidente i
          JOIN SLA sla ON i.fk_gravedad_id = sla.fk_gravedad_id
         WHERE i.fk_estado_incidente_id IN (1, 2)  -- Pendiente o En proceso
    LOOP
        v_minutos := EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - v_inc.fecha_hora_registro)) / 60;

        IF (v_minutos > v_inc.tiempo_respuesta_minutos) THEN
            IF (v_inc.fk_estado_incidente_id = 2) THEN
                -- En proceso -> Escalado (y un punto más de prioridad)
                UPDATE Incidente
                   SET fk_estado_incidente_id = 4, prioridad = prioridad + 1
                 WHERE id_incidente = v_inc.id_incidente;
            ELSE
                -- Pendiente vencido -> solo sube prioridad
                UPDATE Incidente
                   SET prioridad = prioridad + 1
                 WHERE id_incidente = v_inc.id_incidente;
            END IF;
        END IF;
    END LOOP;

    PERFORM set_config('my.trigger_disparador', '', true);
END;
$$;


-- R17: reactivación de recursos. Devuelve a "Disponible" los recursos que fueron puestos
-- "Fuera de servicio" cuya última penalización ya superó el período de suspensión configurado.
CREATE OR REPLACE PROCEDURE sp_reactivar_recursos()
LANGUAGE plpgsql AS $$
DECLARE
    v_rec RECORD;
    v_minutos INT;
BEGIN
    PERFORM set_config('my.trigger_disparador', 'sp_reactivar_recursos', true);

    SELECT numero INTO v_minutos FROM ParametrosSistema WHERE nombre_parametro = 'MINUTOS_REACTIVACION_RECURSO';
    v_minutos := COALESCE(v_minutos, 60);

    FOR v_rec IN
        SELECT r.id_recurso
          FROM Recurso r
         WHERE r.fk_estado_recurso_id = 3  -- Fuera de servicio
           AND NOT EXISTS (
               SELECT 1 FROM Penalizacion p
                WHERE p.fk_recurso_id = r.id_recurso
                  AND (p.fecha + p.hora) >= CURRENT_TIMESTAMP - (v_minutos || ' minutes')::INTERVAL)
    LOOP
        UPDATE Recurso SET fk_estado_recurso_id = 1 WHERE id_recurso = v_rec.id_recurso;
    END LOOP;

    PERFORM set_config('my.trigger_disparador', '', true);
END;
$$;

-- ============================================================================
-- DOCUMENTACIÓN
-- ============================================================================
--
-- 1. AUDITORÍA (R3/R18/R19): trigger AFTER por fila sobre las tablas operativas. Registra cada
--    INSERT/UPDATE/DELETE en Log con el payload JSON (old/new), la operación y el trigger que la
--    originó (NULL = acción manual, leído desde la variable de sesión my.trigger_disparador).
--
-- 2. CIERRE DE ASIGNACIONES FALLIDAS (BEFORE UPDATE sobre Asignacion):
--    fn_cerrar_asignacion_fallida fija timestamp_finalizacion cuando estado_exito = FALSE sin cierre,
--    para que R7 (AFTER) no cuente la asignación fallida como activa.
--    Las VALIDACIONES R8/R9/R10/R11 + la validación de tipo aplicable se movieron a
--    database/triggers/reglas-validadoras.sql (se cargan después de este archivo en migrate.sql).
--
-- 3. PRIORIDAD (R12/R13): BEFORE INSERT sobre Incidente. prioridad = gravedad*10, +bonus si la zona
--    es de alto riesgo. Se aplica a TODO incidente (IoT o manual).
--
-- 4. SANCIONES: AFTER INSERT sobre Penalizacion. Si los puntos acumulados del recurso superan
--    PUNTAJE_BLOQUEO_RECURSO, el recurso pasa a "Fuera de servicio".
--
-- 5. MOTOR (R1/R5/R14/R15): fn_asignar_recursos_incidente despacha recursos a un incidente.
--    R5 exige 2 recursos si la gravedad alcanza GRAVEDAD_MINIMA_CRITICA. R14 elige el mejor
--    candidato (menor penalización y carga) filtrando por tipo aplicable y zona habilitada.
--    R15: si no hay candidato local, toma el mejor global del mismo tipo y lo asigna habilitando el
--    alta con my.bypass_zona (sin contaminar ZonaRecurso). fn_despachar_recurso_backlog reasigna un
--    recurso recién liberado al Pendiente de mayor prioridad que pueda atender.
--
-- 6. OPERATIVA (AFTER INSERT/UPDATE sobre Asignacion):
--    - INSERT: recurso -> En tránsito (R8); incidente Pendiente -> En proceso (R2).
--    - UPDATE caso A (llegada): recurso -> Ocupado; penalización por exceso de traslado vs SLA.
--    - UPDATE caso B (finalización ok): recurso -> Disponible; si no quedan recursos activos el
--      incidente -> Resuelto (R7); el recurso liberado atiende el backlog por prioridad.
--    - UPDATE caso C (estado_exito = FALSE): libera y penaliza el recurso y despacha un reemplazo (R4).
--
-- 7. AUTOMATIZACIÓN DE INCIDENTE (AFTER INSERT sobre Incidente): R20 controla la capacidad
--    (si los activos superan UMBRAL_INCIDENTES_ACTIVOS el incidente queda Pendiente sin despachar);
--    si hay capacidad y nace Pendiente, dispara el motor de asignación (R1).
--
-- 8. IoT (R21, AFTER INSERT sobre Evento): calcula la confianza del sensor (100 menos el decaimiento
--    semanal por semanas sin mantenimiento). Si supera SENSOR_UMBRAL_CONFIANZA_MINIMO genera el
--    incidente (mapeando tipo de evento a tipo/gravedad); si no, solo lo registra en el Log.
--
-- 9. PROCEDIMIENTOS TEMPORALES (se ejecutan con CALL, no hay scheduler):
--    - sp_escalar_incidente() (R16/P2): escala los "En proceso" vencidos de SLA y sube la prioridad
--      de los "Pendiente" vencidos.
--    - sp_reactivar_recursos() (R17): reactiva recursos suspendidos pasado el período configurado.
-- ============================================================================
