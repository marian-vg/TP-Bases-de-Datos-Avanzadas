-- ============================================================================
-- TRIGGERS - SMART CITY
-- ============================================================================

-- Este archivo sera para ir agregando los triggers a la base de datos.
-- Pongan sus triggers aca sin temor, luego el encargado de resolver los merge en caso de que haya conflictos 
-- (poco probable) se las arreglara. (osea Mariano, yo)
--
-- TODO ESTO FUE HECHO POR UNA IA NO TOMAR COMO ULTIMA VERSION (USARLO DE GUIA)
-- EN LA PARTE DE ABAJO DE LOS 7 TRIGGERS HAY UNA DOCUMENTACION DE CADA PUNTO
--
-- ============================================================================
-- 1. AUDITORÍA CENTRALIZADA UNIFICADA (DD-03 & R3 & R18 & R19)
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_auditoria_centralizada()
RETURNS TRIGGER AS $$
DECLARE
    v_trigger_disparador VARCHAR(100);
    v_detalle JSONB;
    v_id_afectado BIGINT;
BEGIN
    -- Obtener el nombre del trigger disparador desde la variable local de transacción
    v_trigger_disparador := NULLIF(current_setting('my.trigger_disparador', true), '');

    -- Construir el detalle del payload según la operación DML
    IF (TG_OP = 'INSERT') THEN
        v_detalle := jsonb_build_object('new', to_jsonb(NEW));
        
        CASE LOWER(TG_TABLE_NAME)
            WHEN 'incidente' THEN v_id_afectado := NEW.id_incidente;
            WHEN 'asignacion' THEN v_id_afectado := NEW.id_asignacion;
            WHEN 'recurso' THEN v_id_afectado := NEW.id_recurso;
            WHEN 'penalizacion' THEN v_id_afectado := NEW.id_penalizacion;
            WHEN 'sensor' THEN v_id_afectado := NEW.id_sensor;
            WHEN 'evento' THEN v_id_afectado := NEW.id_evento;
            ELSE v_id_afectado := 0;
        END CASE;
        
    ELSIF (TG_OP = 'UPDATE') THEN
        v_detalle := jsonb_build_object('old', to_jsonb(OLD), 'new', to_jsonb(NEW));
        
        CASE LOWER(TG_TABLE_NAME)
            WHEN 'incidente' THEN v_id_afectado := NEW.id_incidente;
            WHEN 'asignacion' THEN v_id_afectado := NEW.id_asignacion;
            WHEN 'recurso' THEN v_id_afectado := NEW.id_recurso;
            WHEN 'penalizacion' THEN v_id_afectado := NEW.id_penalizacion;
            WHEN 'sensor' THEN v_id_afectado := NEW.id_sensor;
            WHEN 'evento' THEN v_id_afectado := NEW.id_evento;
            ELSE v_id_afectado := 0;
        END CASE;
        
    ELSIF (TG_OP = 'DELETE') THEN
        v_detalle := jsonb_build_object('old', to_jsonb(OLD));
        
        CASE LOWER(TG_TABLE_NAME)
            WHEN 'incidente' THEN v_id_afectado := OLD.id_incidente;
            WHEN 'asignacion' THEN v_id_afectado := OLD.id_asignacion;
            WHEN 'recurso' THEN v_id_afectado := OLD.id_recurso;
            WHEN 'penalizacion' THEN v_id_afectado := OLD.id_penalizacion;
            WHEN 'sensor' THEN v_id_afectado := OLD.id_sensor;
            WHEN 'evento' THEN v_id_afectado := OLD.id_evento;
            ELSE v_id_afectado := 0;
        END CASE;
    END IF;

    -- Insertar en la tabla única de logs/auditoría
    INSERT INTO Log (tablaAfectada, idTablaAfectada, operacion, trigger_disparador, detalle)
    VALUES (TG_TABLE_NAME, v_id_afectado, TG_OP, v_trigger_disparador, v_detalle);

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Asignación de triggers de auditoría
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
-- 2. REGLAS DE VALIDACIÓN E INTEGRIDAD (R8_Val & R9_Val & R10_Val & R11_Val)
-- ============================================================================

-- Validaciones de recursos y zonas en Asignacion
CREATE OR REPLACE FUNCTION fn_validaciones_asignacion()
RETURNS TRIGGER AS $$
DECLARE
    v_zona_incidente INT;
    v_nombre_estado_recurso VARCHAR(50);
BEGIN
    -- R8_Val: No se puede asignar un recurso que ya esté ocupado/inactivo
    IF (TG_OP = 'INSERT') THEN
        SELECT er.nombre INTO v_nombre_estado_recurso
        FROM Recurso r
        JOIN EstadoRecurso er ON r.fk_estado_recurso_id = er.id_estado_recurso
        WHERE r.id_recurso = NEW.fk_recurso_id;

        IF (v_nombre_estado_recurso <> 'Disponible') THEN
            RAISE EXCEPTION 'R8_Val Error: El recurso % se encuentra en estado "%" y no puede asignarse.', 
                NEW.fk_recurso_id, v_nombre_estado_recurso;
        END IF;
    END IF;

    -- R10_Val: El recurso debe estar habilitado en la zona del incidente
    SELECT fk_zona_id INTO v_zona_incidente
    FROM Incidente
    WHERE id_incidente = NEW.fk_incidente_id;

    IF NOT EXISTS (
        SELECT 1 FROM ZonaRecurso 
        WHERE id_recurso = NEW.fk_recurso_id AND id_zona = v_zona_incidente
    ) THEN
        RAISE EXCEPTION 'R10_Val Error: El recurso % no está habilitado para operar en la zona %.', 
            NEW.fk_recurso_id, v_zona_incidente;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tg_val_asignacion BEFORE INSERT OR UPDATE ON Asignacion
FOR EACH ROW EXECUTE FUNCTION fn_validaciones_asignacion();


-- Validaciones de transiciones de estados e incidentes duplicados
CREATE OR REPLACE FUNCTION fn_validaciones_incidente()
RETURNS TRIGGER AS $$
DECLARE
    v_minutos_duplicado NUMERIC;
    v_estado_old VARCHAR(50);
    v_estado_new VARCHAR(50);
BEGIN
    -- R11_Val: Evitar incidentes duplicados temporales (misma zona y tipo en corto período)
    IF (TG_OP = 'INSERT') THEN
        SELECT numero INTO v_minutos_duplicado 
        FROM ParametrosSistema 
        WHERE nombre_parametro = 'MINUTOS_DUPLICADO_INCIDENTE';
        
        v_minutos_duplicado := COALESCE(v_minutos_duplicado, 10);

        IF EXISTS (
            SELECT 1 FROM Incidente
            WHERE fk_zona_id = NEW.fk_zona_id
              AND fk_tipo_incidente_id = NEW.fk_tipo_incidente_id
              AND fecha_hora_registro >= CURRENT_TIMESTAMP - (v_minutos_duplicado || ' minutes')::INTERVAL
              AND fk_estado_incidente_id <> 6 -- Omitir cancelados
        ) THEN
            RAISE EXCEPTION 'R11_Val Error: Ya se encuentra registrado un incidente similar activo en la zona en los últimos % minutos.', 
                v_minutos_duplicado;
        END IF;
    END IF;

    -- R9_Val: Coherencia en la transición de estados de incidentes
    IF (TG_OP = 'UPDATE' AND OLD.fk_estado_incidente_id <> NEW.fk_estado_incidente_id) THEN
        SELECT nombre INTO v_estado_old FROM EstadoIncidente WHERE id_estado_incidente = OLD.fk_estado_incidente_id;
        SELECT nombre INTO v_estado_new FROM EstadoIncidente WHERE id_estado_incidente = NEW.fk_estado_incidente_id;

        -- Estados terminales inmutables
        IF (v_estado_old IN ('Resuelto', 'Cancelado')) THEN
            RAISE EXCEPTION 'R9_Val Error: El incidente ya está en estado terminal (%) y no admite cambios.', v_estado_old;
        END IF;

        -- Transiciones de inicio incorrectas
        IF (v_estado_old = 'Pendiente' AND v_estado_new IN ('Resuelto', 'Escalado')) THEN
            RAISE EXCEPTION 'R9_Val Error: Transición inválida. No se puede pasar de % directamente a %.', v_estado_old, v_estado_new;
        END IF;

        IF (v_estado_old = 'En espera' AND v_estado_new IN ('Resuelto', 'Escalado')) THEN
            RAISE EXCEPTION 'R9_Val Error: Transición inválida. No se puede pasar de % directamente a %.', v_estado_old, v_estado_new;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tg_val_incidente BEFORE INSERT OR UPDATE ON Incidente
FOR EACH ROW EXECUTE FUNCTION fn_validaciones_incidente();


-- ============================================================================
-- 3. REGLAS TEMPORALES Y DE AUTO-DEPURACIÓN (R16 & R17)
-- ============================================================================

-- R17: Reactivación automática de recursos fuera de servicio pasados los minutos configurados
CREATE OR REPLACE FUNCTION fn_reactivar_recursos()
RETURNS VOID AS $$
DECLARE
    v_minutos_reactivacion INT;
    v_recurso RECORD;
BEGIN
    SELECT numero INTO v_minutos_reactivacion 
    FROM ParametrosSistema 
    WHERE nombre_parametro = 'MINUTOS_REACTIVACION_RECURSO';
    
    v_minutos_reactivacion := COALESCE(v_minutos_reactivacion, 60);

    FOR v_recurso IN 
        SELECT r.id_recurso 
        FROM Recurso r
        WHERE r.fk_estado_recurso_id = 3 -- Fuera de servicio
          AND NOT EXISTS (
              SELECT 1 FROM Penalizacion p
              WHERE p.fk_recurso_id = r.id_recurso
                AND (p.fecha + p.hora) >= CURRENT_TIMESTAMP - (v_minutos_reactivacion || ' minutes')::INTERVAL
          )
    LOOP
        UPDATE Recurso
        SET fk_estado_recurso_id = 1 -- Disponible
        WHERE id_recurso = v_recurso.id_recurso;

        INSERT INTO Log (tablaAfectada, idTablaAfectada, operacion, trigger_disparador, detalle)
        VALUES (
            'Recurso', 
            v_recurso.id_recurso, 
            'UPDATE', 
            'fn_reactivar_recursos', 
            jsonb_build_object('accion', 'Reactivación automática tras cumplir periodo de suspensión')
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql;


-- R16: Control y escalamiento automático de incidentes que superen el SLA
CREATE OR REPLACE FUNCTION fn_controlar_sla_incidentes()
RETURNS VOID AS $$
DECLARE
    v_incidente RECORD;
    v_minutos_transcurridos NUMERIC;
    v_factor_gravedad INT;
BEGIN
    SELECT numero INTO v_factor_gravedad 
    FROM ParametrosSistema 
    WHERE nombre_parametro = 'ESCALAR_FACTOR_GRAVEDAD';
    
    v_factor_gravedad := COALESCE(v_factor_gravedad, 1);

    FOR v_incidente IN
        SELECT i.id_incidente, i.prioridad, i.fk_gravedad_id, sla.tiempo_respuesta_minutos
        FROM Incidente i
        JOIN SLA sla ON i.fk_gravedad_id = sla.fk_gravedad_id
        WHERE i.fk_estado_incidente_id NOT IN (3, 4, 6) -- No terminados ni ya escalados
    LOOP
        v_minutos_transcurridos := EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - v_incidente.fecha_hora_registro)) / 60;

        IF (v_minutos_transcurridos > v_incidente.tiempo_respuesta_minutos) THEN
            UPDATE Incidente
            SET fk_estado_incidente_id = 4, -- Escalado
                fk_gravedad_id = LEAST(5, fk_gravedad_id + v_factor_gravedad), -- Incrementa gravedad
                prioridad = v_incidente.prioridad + 15 -- Aumenta urgencia
            WHERE id_incidente = v_incidente.id_incidente;

            INSERT INTO Log (tablaAfectada, idTablaAfectada, operacion, trigger_disparador, detalle)
            VALUES (
                'Incidente', 
                v_incidente.id_incidente, 
                'UPDATE', 
                'fn_controlar_sla_incidentes', 
                jsonb_build_object(
                    'accion', 'Escalamiento automático por SLA vencido',
                    'minutos_demora', ROUND(v_minutos_transcurridos - v_incidente.tiempo_respuesta_minutos, 1)
                )
            );
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;


-- ============================================================================
-- 4. CONTROL SANCIONATORIO (PUNTAJE_BLOQUEO_RECURSO & SUSPENSIÓN)
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_gestion_penalizaciones()
RETURNS TRIGGER AS $$
DECLARE
    v_total_puntos INT;
    v_umbral_bloqueo INT;
BEGIN
    PERFORM set_config('my.trigger_disparador', 'tg_gestion_penalizaciones', true);

    SELECT numero INTO v_umbral_bloqueo 
    FROM ParametrosSistema 
    WHERE nombre_parametro = 'PUNTAJE_BLOQUEO_RECURSO';
    
    v_umbral_bloqueo := COALESCE(v_umbral_bloqueo, 75);

    -- Sumar puntos acumulados de penalizaciones activas
    SELECT COALESCE(SUM(tp.puntaje), 0) INTO v_total_puntos
    FROM Penalizacion p
    JOIN TipoPenalizacion tp ON p.fk_tipo_penalizacion_id = tp.id_tipo_penalizacion
    WHERE p.fk_recurso_id = NEW.fk_recurso_id;

    -- Si supera el umbral se le inactiva físicamente
    IF (v_total_puntos >= v_umbral_bloqueo) THEN
        UPDATE Recurso
        SET fk_estado_recurso_id = 3 -- Fuera de servicio
        WHERE id_recurso = NEW.fk_recurso_id;

        INSERT INTO Log (tablaAfectada, idTablaAfectada, operacion, trigger_disparador, detalle)
        VALUES (
            'Recurso', 
            NEW.fk_recurso_id, 
            'UPDATE', 
            'tg_gestion_penalizaciones', 
            jsonb_build_object(
                'accion', 'Bloqueo automático de recurso por penalizaciones',
                'puntos_totales', v_total_puntos,
                'motivo', 'Superó el límite permitido de ' || v_umbral_bloqueo || ' puntos.'
            )
        );
    END IF;

    PERFORM set_config('my.trigger_disparador', '', true);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tg_penalizacion_bloqueo AFTER INSERT ON Penalizacion
FOR EACH ROW EXECUTE FUNCTION fn_gestion_penalizaciones();


-- ============================================================================
-- 5. GESTIÓN OPERATIVA DE ASIGNACIONES (DD-01 & R2 & R7 & R8 & R9 & R4)
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_gestion_asignacion_operativa()
RETURNS TRIGGER AS $$
DECLARE
    v_zona_incidente INT;
    v_gravedad_incidente INT;
    v_minutos_sla INT;
    v_minutos_traslado NUMERIC;
    v_demora NUMERIC;
    v_tipo_penalizacion_id INT;
    v_motivo TEXT;
BEGIN
    PERFORM set_config('my.trigger_disparador', 'tg_gestion_asignacion_operativa', true);

    SELECT fk_zona_id, fk_gravedad_id INTO v_zona_incidente, v_gravedad_incidente
    FROM Incidente
    WHERE id_incidente = NEW.fk_incidente_id;

    -- 1. AL CREAR UNA ASIGNACIÓN (INSERT)
    IF (TG_OP = 'INSERT') THEN
        -- R8 & DD-01: Recurso pasa a "En tránsito" (5)
        UPDATE Recurso 
        SET fk_estado_recurso_id = 5 
        WHERE id_recurso = NEW.fk_recurso_id;

        -- R2: Incidente pasa a "En proceso" (2)
        UPDATE Incidente 
        SET fk_estado_incidente_id = 2 
        WHERE id_incidente = NEW.fk_incidente_id 
          AND fk_estado_incidente_id IN (1, 5);
    END IF;

    -- 2. AL MODIFICAR UNA ASIGNACIÓN (UPDATE)
    IF (TG_OP = 'UPDATE') THEN
        
        -- CASO A: Arribo al incidente (timestamp_llegada registrado)
        IF (OLD.timestamp_llegada IS NULL AND NEW.timestamp_llegada IS NOT NULL) THEN
            -- R8: Recurso pasa a "Ocupado" (2) en el lugar
            UPDATE Recurso 
            SET fk_estado_recurso_id = 2 
            WHERE id_recurso = NEW.fk_recurso_id;

            -- DD-01 & R9: Medición de SLA de traslado
            v_minutos_traslado := EXTRACT(EPOCH FROM (NEW.timestamp_llegada - NEW.timestamp_asignacion)) / 60;
            
            SELECT tiempo_respuesta_minutos INTO v_minutos_sla
            FROM SLA
            WHERE fk_gravedad_id = v_gravedad_incidente;

            IF (v_minutos_sla IS NOT NULL AND v_minutos_traslado > v_minutos_sla) THEN
                v_demora := v_minutos_traslado - v_minutos_sla;
                
                -- Escalonamiento de penalizaciones por traslado tardío
                IF (v_demora <= 10) THEN
                    v_tipo_penalizacion_id := 1; -- Demora leve (5 pts)
                    v_motivo := 'Exceso de tiempo de traslado: Demora leve de ' || ROUND(v_demora, 1) || ' minutos sobre SLA de ' || v_minutos_sla || ' min.';
                ELSIF (v_demora <= 30) THEN
                    v_tipo_penalizacion_id := 2; -- Demora moderada (15 pts)
                    v_motivo := 'Exceso de tiempo de traslado: Demora moderada de ' || ROUND(v_demora, 1) || ' minutos sobre SLA de ' || v_minutos_sla || ' min.';
                ELSE
                    v_tipo_penalizacion_id := 3; -- Demora grave (25 pts)
                    v_motivo := 'Exceso de tiempo de traslado: Demora crítica de ' || ROUND(v_demora, 1) || ' minutos sobre SLA de ' || v_minutos_sla || ' min.';
                END IF;

                INSERT INTO Penalizacion (fk_recurso_id, fk_tipo_penalizacion_id, motivo)
                VALUES (NEW.fk_recurso_id, v_tipo_penalizacion_id, v_motivo);
            END IF;
        END IF;

        -- CASO B: Finalización y liberación (timestamp_finalizacion registrado)
        IF (OLD.timestamp_finalizacion IS NULL AND NEW.timestamp_finalizacion IS NOT NULL) THEN
            -- R8: Recurso vuelve a estar "Disponible" (1) si no fue suspendido
            UPDATE Recurso 
            SET fk_estado_recurso_id = 1 
            WHERE id_recurso = NEW.fk_recurso_id 
              AND fk_estado_recurso_id = 2;

            -- R7: Cierre automático del incidente si terminaron todos los recursos
            IF NOT EXISTS (
                SELECT 1 FROM Asignacion
                WHERE fk_incidente_id = NEW.fk_incidente_id 
                  AND timestamp_finalizacion IS NULL
            ) THEN
                UPDATE Incidente
                SET fk_estado_incidente_id = 3 -- Resuelto
                WHERE id_incidente = NEW.fk_incidente_id 
                  AND fk_estado_incidente_id NOT IN (3, 6);
            END IF;
        END IF;

        -- CASO C: Asignación declarada fallida (estado_exito = FALSE)
        -- R4: Reasignación y penalización por no-respuesta/abandono
        IF (COALESCE(OLD.estado_exito, TRUE) <> FALSE AND NEW.estado_exito = FALSE) THEN
            IF (NEW.timestamp_finalizacion IS NULL) THEN
                NEW.timestamp_finalizacion := CURRENT_TIMESTAMP;
            END IF;

            UPDATE Recurso 
            SET fk_estado_recurso_id = 1 
            WHERE id_recurso = NEW.fk_recurso_id;

            IF (NEW.timestamp_llegada IS NULL) THEN
                v_tipo_penalizacion_id := 6; -- No respuesta (50 pts)
                v_motivo := 'El recurso asignado no respondió al despacho de emergencia (Abandono en tránsito).';
            ELSE
                v_tipo_penalizacion_id := 4; -- Falla en intervención (30 pts)
                v_motivo := 'El recurso falló durante las tareas de mitigación en el lugar.';
            END IF;

            INSERT INTO Penalizacion (fk_recurso_id, fk_tipo_penalizacion_id, motivo)
            VALUES (NEW.fk_recurso_id, v_tipo_penalizacion_id, v_motivo);

            -- R4: Despachar otro recurso inmediatamente en su reemplazo
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
-- 6. AUTOMATIZACIÓN DE SENSORES IOT (DD-02 & PRIORIZACIÓN & CAPACIDAD)
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_gestion_evento_iot()
RETURNS TRIGGER AS $$
DECLARE
    v_sensor_rec RECORD;
    v_semanas_sin_mantenimiento INT;
    v_umbral NUMERIC;
    v_tipo_incidente_id INT;
    v_gravedad_id INT;
    v_estado_incidente_id INT;
    v_incidentes_activos INT;
    v_capacidad_maxima INT;
    v_prioridad INT;
    v_bonus INT;
    v_desc_incidente TEXT;
    v_incidente_id INT;
BEGIN
    PERFORM set_config('my.trigger_disparador', 'tg_gestion_evento_iot', true);

    -- 1. Cargar datos del dispositivo emisor y su zona
    SELECT s.*, z.fk_nivel_riesgo_id, nr.valor AS riesgo_valor, z.nombre AS nombre_zona
    INTO v_sensor_rec
    FROM Sensor s
    JOIN Zona z ON s.fk_zona_id = z.id_zona
    JOIN NivelRiesgo nr ON z.fk_nivel_riesgo_id = nr.id_nivel_riesgo
    WHERE s.id_sensor = NEW.fk_sensor_id;

    -- 2. DD-02: Calcular umbral de desgaste (semanas sin mantenimiento)
    v_semanas_sin_mantenimiento := FLOOR((NEW.fecha_evento - COALESCE(v_sensor_rec.fecha_mantenimiento, v_sensor_rec.fecha_instalado)) / 7);
    v_umbral := GREATEST(0, 100 - (5 * v_semanas_sin_mantenimiento));

    -- Filtrado y clasificación según desgaste del sensor
    IF (v_umbral < 20) THEN
        -- Umbral < 20%: Descartado (Falso Positivo)
        INSERT INTO Log (tablaAfectada, idTablaAfectada, operacion, trigger_disparador, detalle)
        VALUES (
            'Evento', 
            NEW.id_evento, 
            'INSERT', 
            'tg_gestion_evento_iot', 
            jsonb_build_object(
                'accion', 'Evento descartado',
                'motivo', 'Desgaste crítico del sensor. Se asume falso positivo.',
                'umbral_confianza', v_umbral
            )
        );
        PERFORM set_config('my.trigger_disparador', '', true);
        RETURN NEW;
        
    ELSIF (v_umbral < 50) THEN
        -- 20% <= Umbral < 50%: Guardar Log técnico, no genera incidente
        INSERT INTO Log (tablaAfectada, idTablaAfectada, operacion, trigger_disparador, detalle)
        VALUES (
            'Evento', 
            NEW.id_evento, 
            'INSERT', 
            'tg_gestion_evento_iot', 
            jsonb_build_object(
                'accion', 'Evento archivado en Log',
                'motivo', 'Baja confiabilidad del sensor. No califica para creación de incidente.',
                'umbral_confianza', v_umbral
            )
        );
        PERFORM set_config('my.trigger_disparador', '', true);
        RETURN NEW;
    END IF;

    -- Umbral >= 50%: Creación del incidente en base a sensor de confianza
    CASE NEW.fk_tipo_evento_id
        WHEN 1 THEN -- Humo
            v_tipo_incidente_id := 2; -- Incendio estructural
            v_gravedad_id := 4;       -- Crítica
        WHEN 2 THEN -- Gas
            v_tipo_incidente_id := 8; -- Fuga de gas
            v_gravedad_id := 3;       -- Alta
        WHEN 3 THEN -- Movimiento sospechoso
            v_tipo_incidente_id := 5; -- Robo / Asalto
            v_gravedad_id := 2;       -- Moderada
        WHEN 4 THEN -- Botón pánico
            v_tipo_incidente_id := 4; -- Emergencia médica
            v_gravedad_id := 3;       -- Alta
        WHEN 5 THEN -- Disparo acústico
            v_tipo_incidente_id := 7; -- Disturbios
            v_gravedad_id := 3;       -- Alta
        WHEN 6 THEN -- Temperatura crítica
            v_tipo_incidente_id := 2; -- Incendio estructural
            v_gravedad_id := 3;       -- Alta
        WHEN 7 THEN -- Inundación
            v_tipo_incidente_id := 10;-- Inundación urbana
            v_gravedad_id := 4;       -- Crítica
        WHEN 8 THEN -- Vibración sísmica
            v_tipo_incidente_id := 11;-- Derrumbe
            v_gravedad_id := 5;       -- Catastrófica
        WHEN 9 THEN -- Calidad de aire
            v_tipo_incidente_id := 13;-- Materiales peligrosos
            v_gravedad_id := 2;       -- Moderada
        WHEN 10 THEN -- Cámara caída
            v_tipo_incidente_id := 9; -- Corte de energía
            v_gravedad_id := 1;       -- Baja
        ELSE
            v_tipo_incidente_id := 4;
            v_gravedad_id := 2;
    END CASE;

    -- R12: Calcular prioridad base = gravedad_id * 10
    v_prioridad := v_gravedad_id * 10;

    -- R13: Bonus por zona de riesgo (Alto/Crítico >= 3)
    IF (v_sensor_rec.riesgo_valor >= 3) THEN
        SELECT numero INTO v_bonus FROM ParametrosSistema WHERE nombre_parametro = 'BONUS_PRIORIDAD_ZONA_RIESGO';
        v_prioridad := v_prioridad + COALESCE(v_bonus, 10);
    END IF;

    -- DD-02: Prioridad reducida a la mitad si el umbral está desgastado (50% <= umbral < 80%)
    IF (v_umbral < 80) THEN
        v_prioridad := FLOOR(v_prioridad / 2);
    END IF;

    -- R20: Capacidad máxima del sistema
    SELECT COUNT(*) INTO v_incidentes_activos FROM Incidente WHERE fk_estado_incidente_id NOT IN (3, 6);
    
    SELECT numero INTO v_capacidad_maxima 
    FROM ParametrosSistema 
    WHERE nombre_parametro = 'UMBRAL_INCIDENTES_ACTIVOS';
    
    v_capacidad_maxima := COALESCE(v_capacidad_maxima, 50);

    IF (v_incidentes_activos >= v_capacidad_maxima) THEN
        v_estado_incidente_id := 5; -- En espera
        v_desc_incidente := '[SISTEMA SATURADO - EN ESPERA] Incidente IoT generado automáticamente por sensor ' || v_sensor_rec.nombre || ' (Confianza: ' || v_umbral || '%).';
    ELSE
        v_estado_incidente_id := 1; -- Pendiente
        v_desc_incidente := '[AUTOMÁTICO - PENDIENTE] Incidente IoT generado automáticamente por sensor ' || v_sensor_rec.nombre || ' (Confianza: ' || v_umbral || '%).';
    END IF;

    -- Crear incidente
    INSERT INTO Incidente (
        fk_evento_id, 
        fk_tipo_incidente_id, 
        fk_gravedad_id, 
        fk_estado_incidente_id, 
        fk_zona_id, 
        descripcion, 
        prioridad
    ) VALUES (
        NEW.id_evento,
        v_tipo_incidente_id,
        v_gravedad_id,
        v_estado_incidente_id,
        v_sensor_rec.fk_zona_id,
        v_desc_incidente,
        v_prioridad
    ) RETURNING id_incidente INTO v_incidente_id;

    -- Auditoría
    INSERT INTO Log (tablaAfectada, idTablaAfectada, operacion, trigger_disparador, detalle)
    VALUES (
        'Incidente',
        v_incidente_id,
        'INSERT',
        'tg_gestion_evento_iot',
        jsonb_build_object(
            'accion', 'Generación automática por IoT',
            'umbral_confianza', v_umbral,
            'prioridad_final', v_prioridad
        )
    );

    PERFORM set_config('my.trigger_disparador', '', true);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tg_evento_iot AFTER INSERT ON Evento
FOR EACH ROW EXECUTE FUNCTION fn_gestion_evento_iot();


-- ============================================================================
-- 7. MOTOR INTELIGENTE DE ASIGNACIÓN AUTOMÁTICA Y REBALANCEO (R1 & R5 & R14 & R15)
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_asignar_recursos_incidente(p_incidente_id INT)
RETURNS INT AS $$
DECLARE
    v_incidente RECORD;
    v_recursos_requeridos INT;
    v_recursos_asignados INT := 0;
    v_recurso_id INT;
BEGIN
    -- Ejecutar auto-depuraciones del sistema previas a la búsqueda de flota
    PERFORM fn_reactivar_recursos();
    PERFORM fn_controlar_sla_incidentes();

    SELECT id_incidente, fk_zona_id, fk_gravedad_id 
    INTO v_incidente 
    FROM Incidente 
    WHERE id_incidente = p_incidente_id;

    -- Validar que siga activo
    IF NOT EXISTS (
        SELECT 1 FROM Incidente 
        WHERE id_incidente = p_incidente_id AND fk_estado_incidente_id NOT IN (3, 6)
    ) THEN
        RETURN 0;
    END IF;

    -- R5: Incidentes críticos requieren múltiples recursos (MIN_RECURSOS_INCIDENTE_CRITICO = 2)
    IF (v_incidente.fk_gravedad_id >= 3) THEN
        SELECT numero INTO v_recursos_requeridos 
        FROM ParametrosSistema 
        WHERE nombre_parametro = 'MIN_RECURSOS_INCIDENTE_CRITICO';
        
        v_recursos_requeridos := COALESCE(v_recursos_requeridos, 2);
    ELSE
        v_recursos_requeridos := 1;
    END IF;

    -- Asignaciones activas actuales
    SELECT COUNT(*) INTO v_recursos_asignados
    FROM Asignacion
    WHERE fk_incidente_id = p_incidente_id AND timestamp_finalizacion IS NULL;

    -- Asignación iterativa considerando historial y penalizaciones (vRecursosCandidatos)
    WHILE (v_recursos_asignados < v_recursos_requeridos) LOOP
        v_recurso_id := NULL;

        -- R14: Seleccionar el mejor recurso candidato disponible autorizado localmente
        SELECT rc.id_recurso INTO v_recurso_id
        FROM vRecursosCandidatos rc
        JOIN ZonaRecurso zr ON rc.id_recurso = zr.id_recurso
        WHERE zr.id_zona = v_incidente.fk_zona_id
          AND rc.id_recurso NOT IN (
              SELECT fk_recurso_id FROM Asignacion 
              WHERE fk_incidente_id = p_incidente_id
          )
        LIMIT 1;

        -- R15: REBALANCEO GEOGRÁFICO
        -- Si no hay flota disponible localmente, buscar el mejor disponible a nivel municipal global
        IF (v_recurso_id IS NULL) THEN
            SELECT rc.id_recurso INTO v_recurso_id
            FROM vRecursosCandidatos rc
            WHERE rc.id_recurso NOT IN (
                  SELECT fk_recurso_id FROM Asignacion 
                  WHERE fk_incidente_id = p_incidente_id
              )
            LIMIT 1;

            -- DD-01 & R10 & R15: Habilitación interbarrial dinámica
            IF (v_recurso_id IS NOT NULL) THEN
                INSERT INTO ZonaRecurso (id_zona, id_recurso)
                VALUES (v_incidente.fk_zona_id, v_recurso_id)
                ON CONFLICT DO NOTHING;
                
                INSERT INTO Log (tablaAfectada, idTablaAfectada, operacion, trigger_disparador, detalle)
                VALUES (
                    'ZonaRecurso', 
                    v_recurso_id, 
                    'INSERT', 
                    'fn_asignar_recursos_incidente', 
                    jsonb_build_object(
                        'accion', 'Rebalanceo geográfico por escasez',
                        'zona_habilitada', v_incidente.fk_zona_id,
                        'motivo', 'Habilitación dinâmica interbarrial de emergencia para cubrir incidente'
                    )
                );
            END IF;
        END IF;

        -- Municipio sin recursos disponibles, detener flujo
        IF (v_recurso_id IS NULL) THEN
            EXIT;
        END IF;

        -- R1: Despacho
        INSERT INTO Asignacion (fk_recurso_id, fk_incidente_id)
        VALUES (v_recurso_id, p_incidente_id);

        v_recursos_asignados := v_recursos_asignados + 1;
    END LOOP;

    RETURN v_recursos_asignados;
END;
$$ LANGUAGE plpgsql;


-- Trigger operacional sobre la tabla Incidente (AFTER INSERT)
CREATE OR REPLACE FUNCTION fn_gestion_incidente_automatizacion()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM set_config('my.trigger_disparador', 'tg_incidente_automatizacion', true);

    -- R1: Si inicia como Pendiente despachar recursos de inmediato
    IF (NEW.fk_estado_incidente_id = 1) THEN
        PERFORM fn_asignar_recursos_incidente(NEW.id_incidente);
    END IF;

    PERFORM set_config('my.trigger_disparador', '', true);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tg_incidente_auto_asignacion AFTER INSERT ON Incidente
FOR EACH ROW EXECUTE FUNCTION fn_gestion_incidente_automatizacion();


-- ============================================================================
-- DOCUMENTACIÓN Y EXPLICACIÓN DE FUNCIONAMIENTO (PUNTOS 1 AL 7)
-- ============================================================================
--
-- 1. AUDITORÍA CENTRALIZADA UNIFICADA (DD-03 & R3 & R18 & R19)
-- ----------------------------------------------------------------------------
-- * Objetivo: Crear una sola fuente de verdad inmutable (tabla "Log") que registre
--   tanto los cambios operacionales de negocio como la ejecución técnica de las
--   reglas activas, distinguiendo la operatividad del sistema de la manual.
-- * ¿Cómo funciona?:
--   - Es un trigger de tipo 'AFTER' que se dispara en operaciones INSERT, UPDATE 
--     y DELETE de todas las tablas operativas de Smart City.
--   - Utiliza variables de sesión transaccionales de PostgreSQL ('current_setting').
--     Si una mutación proviene de otro trigger operativo, dicho trigger establece 
--     la variable 'my.trigger_disparador' con su propio nombre. El trigger de 
--     auditoría lee esta variable; si está vacía (o lanza excepción silenciosa), 
--     entiende que la mutación fue manual (ej. un UPDATE directo de un operador 
--     en pgAdmin) y guarda NULL.
--   - Convierte el registro físico modificado completo a formato JSON estructurado
--     ('to_jsonb(NEW)') guardando las variables 'old' y/o 'new' para auditorías
--     de cambios históricos sin violar la normalización de la base de datos.
--
-- 2. REGLAS DE VALIDACIÓN E INTEGRIDAD (R8_Val & R9_Val & R10_Val & R11_Val)
-- ----------------------------------------------------------------------------
-- * Objetivo: Interceptar y detener cualquier mutación que atente contra la 
--   consistencia física y operativa de la base de datos municipal.
-- * ¿Cómo funciona?:
--   - Son triggers de tipo 'BEFORE'. Se ejecutan *antes* de que la base de datos 
--     escriba en el disco. Si el trigger lanza un 'RAISE EXCEPTION', la transacción
--     se cancela automáticamente mediante un rollback atómico a nivel de motor.
--   - R8_Val: Valida que el recurso a asignar se encuentre en estado físico 
--     'Disponible' en la tabla 'Recurso'. Si está Ocupado o Fuera de servicio, 
--     rebota la asignación con un mensaje descriptivo.
--   - R10_Val: Valida geográficamente que la zona del incidente se encuentre 
--     autorizada para el recurso asignado dentro de la tabla intermedia 'ZonaRecurso'.
--   - R11_Val: Deduplica incidentes del mismo tipo en el mismo barrio en un 
--     tiempo de 10 minutos (dinámico según ParametrosSistema), evitando registros 
--     duplicados en simultáneo.
--   - R9_Val: Protege la máquina de estados de incidentes, prohibiendo cambios 
--     en incidentes ya terminados (Resuelto/Cancelado) o saltos imposibles 
--     (ej. pasar directo de 'Pendiente' a 'Resuelto' sin tránsito intermedio).
--
-- 3. REGLAS TEMPORALES Y DE AUTO-DEPURACIÓN (R16 & R17)
-- ----------------------------------------------------------------------------
-- * Objetivo: Mantener la base de datos depurada y el control de tiempos del SLA
--   en tiempo real de manera reactiva, superando las limitaciones de no contar 
--   con un programador de tareas asíncrono nativo en el motor relacional estándar.
-- * ¿Cómo funciona?:
--   - fn_reactivar_recursos(): Evalúa a aquellos recursos que fueron suspendidos
--     al estado 'Fuera de servicio'. Si la fecha de su última penalización acumulada
--     supera los 'MINUTOS_REACTIVACION_RECURSO' (60 minutos), los devuelve de 
--     manera proactiva al estado 'Disponible'.
--   - fn_controlar_sla_incidentes(): Recorre en tiempo real los incidentes activos. 
--     Calcula el tiempo de demora real y, si supera el SLA permitido según la 
--     gravedad del caso, cambia automáticamente el estado del incidente a 
--     'Escalado' (4), aumenta su gravedad (+1 en gravedad, máx 5) e incrementa 
--     su prioridad en 15 puntos para captar prioridad en la flota de emergencias.
--   - Ambas rutinas se inyectan dinámicamente al inicio del motor de asignación, 
--     haciendo que el sistema se auto-depure de manera proactiva con el propio uso.
--
-- 4. CONTROL SANCIONATORIO (PUNTAJE_BLOQUEO_RECURSO & SUSPENSIÓN)
-- ----------------------------------------------------------------------------
-- * Objetivo: Sancionar y excluir de los despachos a las flotas municipales con
--   bajo desempeño acumulado.
-- * ¿Cómo funciona?:
--   - Es un trigger AFTER INSERT en la tabla 'Penalizacion'.
--   - Al registrarse una infracción, realiza una sumatoria de los puntos 
--     acumulados históricos del recurso (enlazando con 'TipoPenalizacion').
--   - Si el acumulado es igual o mayor a 'PUNTAJE_BLOQUEO_RECURSO' (75 puntos), 
--     actualiza automáticamente el estado del recurso a 'Fuera de servicio' (3).
--   - Escribe una bitácora justificada en el Log detallando que el bloqueo fue 
--     ejecutado de forma automática por bajo desempeño.
--
-- 5. GESTIÓN OPERATIVA DE ASIGNACIONES (DD-01 & R2 & R7 & R8 & R9 & R4)
-- ----------------------------------------------------------------------------
-- * Objetivo: Orquestar todo el ciclo de vida del despacho, traslado, mitigación 
--   y liberación de flotas y cierre de incidentes.
-- * ¿Cómo funciona?:
--   - R8 & DD-01 (Transiciones del Recurso): 
--     * Al crearse la asignación (INSERT): el recurso pasa a 'En tránsito' (5).
--     * Al registrar el arribo ('timestamp_llegada' UPDATE): pasa a 'Ocupado' (2).
--     * Al finalizar la intervención ('timestamp_finalizacion' UPDATE): vuelve a 'Disponible' (1).
--   - R2 (Cambio Automático de Incidente): Al insertarse la primera asignación,
--     el incidente cambia dinámicamente de 'Pendiente'/'En espera' a 'En proceso'.
--   - R7 (Cierre Automático): Al finalizar un recurso, el trigger verifica si 
--     quedan asignaciones activas sin terminar. Si es el último recurso asignado, 
--     cambia el incidente de forma automática a 'Resuelto' (3).
--   - DD-01 & R9 (Demoras SLA): Al llegar el recurso al lugar, calcula el tiempo 
--     de traslado. Si es mayor al SLA permitido por gravedad, le inserta una 
--     penalización clasificada dinámicamente por severidad de retraso.
--   - R4 (Reasignación Automática): Si la asignación se marca como fallida 
--     (estado_exito = FALSE), el recurso es liberado y penalizado críticamente 
--     (No respuesta si abandonó en tránsito con 50 pts o Falla de intervención 
--     en el lugar con 30 pts). Luego, el trigger gatilla el motor de asignación
--     para re-evaluar y despachar otro recurso de reemplazo disponible inmediatamente.
--
-- 6. AUTOMATIZACIÓN DE SENSORES IOT (DD-02 & PRIORIZACIÓN & CAPACIDAD)
-- ----------------------------------------------------------------------------
-- * Objetivo: Recibir lecturas de dispositivos inteligentes IoT y decidir de
--   forma inteligente e interactiva si califica para emergencias de la ciudad.
-- * ¿Cómo funciona?:
--   - Es un trigger AFTER INSERT en la tabla 'Evento'.
--   - DD-02 (Cálculo de Desgaste): Obtiene los días transcurridos desde el último
--     mantenimiento del sensor. Por cada semana sin revisión, el umbral de 
--     confianza decrece un 5% partiendo de 100%.
--   - Si el umbral calculado es menor a 20%, se descarta el evento por alta
--     probabilidad de ser un falso positivo (mantenimiento abandonado).
--   - Si está entre 20% y 50%, se archiva preventivamente en el Log técnico de 
--     auditoría pero no se genera incidente.
--   - Si está entre 50% y 80%, se crea el incidente pero con prioridad reducida 
--     a la mitad (reflejando sospecha operativa).
--   - Si supera el 80%, genera el incidente con prioridad plena.
--   - R12 & R13: Calcula prioridad como 'gravedad_id * 10'. Si el sensor reside 
--     en un barrio clasificado de alto riesgo (NivelRiesgo >= 3), le suma un 
--     'BONUS_PRIORIDAD_ZONA_RIESGO' (+10 puntos).
--   - R20 (Control de Capacidad): Si el sistema excede los 50 incidentes activos 
--     en la ciudad, marca el nuevo incidente como 'En espera' (5); de lo contrario, 
--     lo crea como 'Pendiente' (1), gatillando el despacho automático.
--
-- 7. MOTOR INTELIGENTE DE ASIGNACIÓN AUTOMÁTICA Y REBALANCEO (R1 & R5 & R14 & R15)
-- ----------------------------------------------------------------------------
-- * Objetivo: Analizar el incidente y despachar a los mejores recursos disponibles
--   a nivel local o global en tiempo real.
-- * ¿Cómo funciona?:
--   - R5 (Flotas Múltiples): Si la gravedad de la emergencia es alta, crítica o
--     catastrófica (gravedad >= 3), el motor exige y despacha 2 recursos (según 
--     MIN_RECURSOS_INCIDENTE_CRITICO) en lugar de uno ordinario.
--   - R14 (Mejor Candidato): Consume la vista de inteligencia del grupo 
--     'vRecursosCandidatos' para seleccionar al recurso disponible que tenga 
--     menor cantidad de penalizaciones y menor cantidad de despachos históricos,
--     promoviendo la equidad de carga laboral y excelente rendimiento.
--   - R15 (Rebalanceo Interbarrial): Si no hay ningún recurso disponible habilitado
--     para operar localmente en el barrio del incidente, la base de datos localiza
--     al mejor recurso disponible de forma global en todo el municipio y lo despacha.
--     Para no violar la validación física de zona (R10), el motor lo habilita 
--     de forma dinámica insertando el par en la tabla intermedia 'ZonaRecurso' 
--     antes de insertarlo en la tabla 'Asignacion', logrando una transición 
--     operativa sin fallas de integridad relacional.
--
