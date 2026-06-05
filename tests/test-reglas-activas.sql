-- ============================================================================
-- SCRIPT DE PRUEBAS DE AUTOMATIZACIÓN PARA reglas-activas.sql (R1,R2,R3,R4,R5,R7,R8,R9,R21)
-- ============================================================================
--
-- A diferencia de test-triggers.sql (que prueba las VALIDACIONES y APAGA la
-- automatización), este script ejercita las reglas de AUTOMATIZACIÓN con todos
-- los triggers PRENDIDOS, y verifica el ESTADO que producen.
--
-- Patrón de aserción: cada escenario ejecuta la acción y comprueba el resultado.
-- Si el resultado NO es el esperado -> RAISE EXCEPTION visible (el test GRITA en
-- vez de reportar un falso ÉXITO). Si todo sale bien, el script termina con
-- '>>> TODAS LAS PRUEBAS OK'.
--
-- Requiere haber cargado, en este orden: create-tables -> carga-dataset ->
-- reglas-validadoras -> reglas-activas. Es destructivo sobre las tablas
-- operativas (Asignacion/Incidente/Evento/Penalizacion/Log), que en el dataset
-- base están vacías; deja los recursos en 'Disponible' al finalizar.
-- ============================================================================

\set ON_ERROR_STOP on

\echo '--------------------------------------------------'
\echo 'INICIANDO PRUEBAS DE AUTOMATIZACIÓN (REGLAS ACTIVAS)'
\echo '--------------------------------------------------'

-- Reset idempotente de las tablas operativas y del estado de los recursos.
DELETE FROM Asignacion;
DELETE FROM Penalizacion;
DELETE FROM Incidente;
DELETE FROM Evento;
DELETE FROM Log;
UPDATE Recurso SET fk_estado_recurso_id = 1 WHERE fk_estado_recurso_id <> 1;

-- Sincronizar secuencias para evitar colisiones de PKs.
SELECT setval(pg_get_serial_sequence('recurso', 'id_recurso'),         COALESCE(MAX(id_recurso), 1))     FROM Recurso;
SELECT setval(pg_get_serial_sequence('incidente', 'id_incidente'),     COALESCE(MAX(id_incidente), 1))   FROM Incidente;
SELECT setval(pg_get_serial_sequence('asignacion', 'id_asignacion'),   COALESCE(MAX(id_asignacion), 1))  FROM Asignacion;
SELECT setval(pg_get_serial_sequence('evento', 'id_evento'),           COALESCE(MAX(id_evento), 1))      FROM Evento;
SELECT setval(pg_get_serial_sequence('penalizacion', 'id_penalizacion'), COALESCE(MAX(id_penalizacion), 1)) FROM Penalizacion;

-- ----------------------------------------------------------------------------
-- PRUEBA 1: R1 + R5 + R2 + R8 + R3 — Asignación automática al registrar incidente
-- ----------------------------------------------------------------------------
\echo '>>> PRUEBA 1: Asignación automática de incidente gravedad Alta (R1/R5/R2/R8/R3)'

DO $$
DECLARE
    v_pendiente   INT;
    v_incidente   INT;
    v_n_asig      INT;
    v_estado_inc  TEXT;
    v_n_ocupados  INT;
BEGIN
    SELECT id_estado_incidente INTO v_pendiente FROM EstadoIncidente WHERE nombre = 'Pendiente';

    -- Incidente tipo 1 / zona 1 / gravedad Alta (3). Zona 1 tiene recursos compatibles de sobra.
    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    VALUES (1, 3, v_pendiente, 1, 'P1 - asignación automática gravedad alta', 3)
    RETURNING id_incidente INTO v_incidente;

    -- R1 + R5: gravedad Alta -> 2 recursos asignados.
    SELECT count(*) INTO v_n_asig FROM Asignacion WHERE fk_incidente_id = v_incidente;
    IF v_n_asig <> 2 THEN
        RAISE EXCEPTION 'FALLO R1/R5: gravedad Alta debía asignar 2 recursos, asignó %.', v_n_asig;
    END IF;

    -- R2: el incidente debe haber pasado a 'En proceso'.
    SELECT ei.nombre INTO v_estado_inc
    FROM Incidente i JOIN EstadoIncidente ei ON i.fk_estado_incidente_id = ei.id_estado_incidente
    WHERE i.id_incidente = v_incidente;
    IF v_estado_inc <> 'En proceso' THEN
        RAISE EXCEPTION 'FALLO R2: el incidente debía quedar En proceso, quedó %.', v_estado_inc;
    END IF;

    -- R8: al asignarse, los recursos deben quedar 'En tránsito' hasta registrar el arribo.
    SELECT count(*) INTO v_n_ocupados
    FROM Asignacion a
    JOIN Recurso r ON a.fk_recurso_id = r.id_recurso
    JOIN EstadoRecurso er ON r.fk_estado_recurso_id = er.id_estado_recurso
    WHERE a.fk_incidente_id = v_incidente AND er.nombre = 'En tránsito';
    IF v_n_ocupados <> 2 THEN
        RAISE EXCEPTION 'FALLO R8: los 2 recursos debían quedar En tránsito, encontrados %.', v_n_ocupados;
    END IF;

    -- R3: el alta del incidente debe haberse auditado en Log.
    -- tablaAfectada guarda el nombre FÍSICO de la tabla (TG_TABLE_NAME), en minúscula.
    IF NOT EXISTS (SELECT 1 FROM Log WHERE tablaAfectada = 'incidente' AND idTablaAfectada = v_incidente) THEN
        RAISE EXCEPTION 'FALLO R3: no se registró en Log la auditoría del incidente %.', v_incidente;
    END IF;

    RAISE NOTICE 'ÉXITO P1: R1+R5 (2 asignaciones), R2 (En proceso), R8 (2 En tránsito), R3 (auditado).';

    -- Limpieza
    DELETE FROM Asignacion WHERE fk_incidente_id = v_incidente;
    DELETE FROM Incidente WHERE id_incidente = v_incidente;
    UPDATE Recurso SET fk_estado_recurso_id = 1 WHERE fk_estado_recurso_id <> 1;
END;
$$;

-- ----------------------------------------------------------------------------
-- PRUEBA 2: R21 — Evento de alta confianza con mapeo único promueve a incidente
-- ----------------------------------------------------------------------------
\echo '>>> PRUEBA 2: Promoción automática evento -> incidente (R21, mapeo único)'

DO $$
DECLARE
    v_umbral   NUMERIC;
    v_sensor   INT;
    v_evento   INT;
    v_tipo_inc INT;
BEGIN
    SELECT numero INTO v_umbral FROM ParametrosSistema WHERE nombre_parametro = 'SENSOR_UMBRAL_CONFIANZA_MINIMO';
    v_umbral := COALESCE(v_umbral, 80);

    -- Sensor de ALTA confianza (por encima del umbral).
    SELECT id_sensor INTO v_sensor
    FROM Sensor WHERE fn_confianza_sensor(id_sensor) > v_umbral
    ORDER BY id_sensor LIMIT 1;
    IF v_sensor IS NULL THEN
        RAISE EXCEPTION 'PRECONDICIÓN FALLIDA: no hay sensor de alta confianza para la prueba.';
    END IF;

    -- Tipo de evento 2 (Detección de gas) mapea a UN único tipo de incidente: 8 (Fuga de gas).
    INSERT INTO Evento (fk_sensor_id, fk_tipo_evento_id) VALUES (v_sensor, 2)
    RETURNING id_evento INTO v_evento;

    SELECT i.fk_tipo_incidente_id INTO v_tipo_inc FROM Incidente i WHERE i.fk_evento_id = v_evento;
    IF v_tipo_inc IS NULL THEN
        RAISE EXCEPTION 'FALLO R21: evento de alta confianza con mapeo único NO generó incidente.';
    END IF;
    IF v_tipo_inc <> 8 THEN
        RAISE EXCEPTION 'FALLO R21: incidente generado con tipo % (esperado 8 = Fuga de gas).', v_tipo_inc;
    END IF;

    RAISE NOTICE 'ÉXITO P2: R21 promovió el evento a un incidente Fuga de gas (tipo 8).';

    -- Limpieza (incluye la posible cascada de R1 sobre el incidente creado).
    DELETE FROM Asignacion WHERE fk_incidente_id IN (SELECT id_incidente FROM Incidente WHERE fk_evento_id = v_evento);
    DELETE FROM Incidente WHERE fk_evento_id = v_evento;
    DELETE FROM Evento WHERE id_evento = v_evento;
    UPDATE Recurso SET fk_estado_recurso_id = 1 WHERE fk_estado_recurso_id <> 1;
END;
$$;

-- ----------------------------------------------------------------------------
-- PRUEBA 3: R21 — Evento de baja confianza solo se registra en Log
-- ----------------------------------------------------------------------------
\echo '>>> PRUEBA 3: Evento de baja confianza no promueve (R21, solo Log)'

DO $$
DECLARE
    v_umbral NUMERIC;
    v_sensor INT;
    v_evento INT;
    v_n_inc  INT;
    v_motivo TEXT;
BEGIN
    SELECT numero INTO v_umbral FROM ParametrosSistema WHERE nombre_parametro = 'SENSOR_UMBRAL_CONFIANZA_MINIMO';
    v_umbral := COALESCE(v_umbral, 80);

    -- Sensor de BAJA confianza (umbral o menos).
    SELECT id_sensor INTO v_sensor
    FROM Sensor WHERE fn_confianza_sensor(id_sensor) <= v_umbral
    ORDER BY id_sensor LIMIT 1;
    IF v_sensor IS NULL THEN
        RAISE EXCEPTION 'PRECONDICIÓN FALLIDA: no hay sensor de baja confianza para la prueba.';
    END IF;

    INSERT INTO Evento (fk_sensor_id, fk_tipo_evento_id) VALUES (v_sensor, 2)
    RETURNING id_evento INTO v_evento;

    SELECT count(*) INTO v_n_inc FROM Incidente WHERE fk_evento_id = v_evento;
    IF v_n_inc <> 0 THEN
        RAISE EXCEPTION 'FALLO R21: un evento de baja confianza generó % incidente(s).', v_n_inc;
    END IF;

    SELECT detalle->>'motivo' INTO v_motivo
    FROM Log
    WHERE trigger_disparador = 'R21'
      AND operacion = 'DECISION'
      AND idTablaAfectada = v_evento
    ORDER BY id_log DESC LIMIT 1;
    IF v_motivo IS NULL OR v_motivo NOT LIKE '%baja fiabilidad%' THEN
        RAISE EXCEPTION 'FALLO R21: no se registró el Log de baja fiabilidad (motivo: %).', v_motivo;
    END IF;

    RAISE NOTICE 'ÉXITO P3: R21 registró el evento de baja fiabilidad en Log sin crear incidente.';

    DELETE FROM Evento WHERE id_evento = v_evento;
END;
$$;

-- ----------------------------------------------------------------------------
-- PRUEBA 4: R21 — Evento confiable con mapeo NO único no promueve (sin adivinar)
-- ----------------------------------------------------------------------------
\echo '>>> PRUEBA 4: Evento confiable con mapeo múltiple no promueve (R21, solo Log)'

DO $$
DECLARE
    v_umbral NUMERIC;
    v_sensor INT;
    v_evento INT;
    v_n_inc  INT;
    v_motivo TEXT;
BEGIN
    SELECT numero INTO v_umbral FROM ParametrosSistema WHERE nombre_parametro = 'SENSOR_UMBRAL_CONFIANZA_MINIMO';
    v_umbral := COALESCE(v_umbral, 80);

    SELECT id_sensor INTO v_sensor
    FROM Sensor WHERE fn_confianza_sensor(id_sensor) > v_umbral
    ORDER BY id_sensor LIMIT 1;
    IF v_sensor IS NULL THEN
        RAISE EXCEPTION 'PRECONDICIÓN FALLIDA: no hay sensor de alta confianza para la prueba.';
    END IF;

    -- Tipo de evento 1 (Detección de humo) mapea a 2 tipos (Incendio estructural/forestal): no único.
    INSERT INTO Evento (fk_sensor_id, fk_tipo_evento_id) VALUES (v_sensor, 1)
    RETURNING id_evento INTO v_evento;

    SELECT count(*) INTO v_n_inc FROM Incidente WHERE fk_evento_id = v_evento;
    IF v_n_inc <> 0 THEN
        RAISE EXCEPTION 'FALLO R21: un evento con mapeo no único generó % incidente(s) (debía no adivinar).', v_n_inc;
    END IF;

    SELECT detalle->>'motivo' INTO v_motivo
    FROM Log
    WHERE trigger_disparador = 'R21'
      AND operacion = 'DECISION'
      AND idTablaAfectada = v_evento
    ORDER BY id_log DESC LIMIT 1;
    IF v_motivo IS NULL OR v_motivo NOT LIKE '%no es único%' THEN
        RAISE EXCEPTION 'FALLO R21: no se registró el Log de mapeo no único (motivo: %).', v_motivo;
    END IF;

    RAISE NOTICE 'ÉXITO P4: R21 no promovió el evento de mapeo múltiple y lo registró en Log.';

    DELETE FROM Evento WHERE id_evento = v_evento;
END;
$$;

-- ----------------------------------------------------------------------------
-- PRUEBA 5: R4 / R9 — Asignación fallida penaliza, libera y reasigna
-- ----------------------------------------------------------------------------
\echo '>>> PRUEBA 5: Asignación fallida -> penalización + reasignación (R4/R9)'

DO $$
DECLARE
    v_pendiente   INT;
    v_incidente   INT;
    v_asig        INT;
    v_recurso     INT;
    v_n_pen       INT;
    v_cerrada     BOOLEAN;
    v_estado_rec  TEXT;
    v_total       INT;
    v_abiertas    INT;
BEGIN
    SELECT id_estado_incidente INTO v_pendiente FROM EstadoIncidente WHERE nombre = 'Pendiente';

    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    VALUES (1, 3, v_pendiente, 1, 'P5 - asignación fallida', 3)
    RETURNING id_incidente INTO v_incidente;

    -- Tomamos una de las asignaciones generadas por R1 y la marcamos como fallida.
    SELECT id_asignacion, fk_recurso_id INTO v_asig, v_recurso
    FROM Asignacion WHERE fk_incidente_id = v_incidente ORDER BY id_asignacion LIMIT 1;
    IF v_asig IS NULL THEN
        RAISE EXCEPTION 'PRECONDICIÓN FALLIDA: el incidente no recibió asignaciones para fallar.';
    END IF;

    UPDATE Asignacion SET estado_exito = FALSE WHERE id_asignacion = v_asig;

    -- R4/R9: se penaliza el recurso fallido.
    SELECT count(*) INTO v_n_pen FROM Penalizacion WHERE fk_recurso_id = v_recurso;
    IF v_n_pen < 1 THEN
        RAISE EXCEPTION 'FALLO R4/R9: no se penalizó el recurso fallido %.', v_recurso;
    END IF;

    -- La asignación fallida debe quedar cerrada (timestamp_finalizacion) para liberar al recurso.
    SELECT (timestamp_finalizacion IS NOT NULL) INTO v_cerrada FROM Asignacion WHERE id_asignacion = v_asig;
    IF NOT v_cerrada THEN
        RAISE EXCEPTION 'FALLO R4: la asignación fallida no se cerró (timestamp_finalizacion nulo).';
    END IF;

    -- R8: el recurso fallido vuelve a 'Disponible'.
    SELECT er.nombre INTO v_estado_rec
    FROM Recurso r JOIN EstadoRecurso er ON r.fk_estado_recurso_id = er.id_estado_recurso
    WHERE r.id_recurso = v_recurso;
    IF v_estado_rec <> 'Disponible' THEN
        RAISE EXCEPTION 'FALLO R8: el recurso fallido no volvió a Disponible (quedó %).', v_estado_rec;
    END IF;

    -- Reasignación: 2 originales + 1 reemplazo = 3 totales; la fallida cerrada => 2 abiertas.
    SELECT count(*) INTO v_total FROM Asignacion WHERE fk_incidente_id = v_incidente;
    SELECT count(*) INTO v_abiertas FROM Asignacion WHERE fk_incidente_id = v_incidente AND timestamp_finalizacion IS NULL;
    IF v_total <> 3 THEN
        RAISE EXCEPTION 'FALLO R4: tras reasignar esperaba 3 asignaciones totales, hay %.', v_total;
    END IF;
    IF v_abiertas <> 2 THEN
        RAISE EXCEPTION 'FALLO R4: esperaba 2 asignaciones abiertas, hay %.', v_abiertas;
    END IF;

    RAISE NOTICE 'ÉXITO P5: R4/R9 penalizó, cerró la fallida, liberó el recurso y reasignó (3 total / 2 abiertas).';

    -- Limpieza
    DELETE FROM Asignacion WHERE fk_incidente_id = v_incidente;
    DELETE FROM Penalizacion WHERE fk_recurso_id = v_recurso;
    DELETE FROM Incidente WHERE id_incidente = v_incidente;
    UPDATE Recurso SET fk_estado_recurso_id = 1 WHERE fk_estado_recurso_id <> 1;
END;
$$;

-- ----------------------------------------------------------------------------
-- PRUEBA 6: R7 — Cierre automático del incidente al finalizar sus asignaciones
-- ----------------------------------------------------------------------------
\echo '>>> PRUEBA 6: Cierre automático a Resuelto (R7)'

DO $$
DECLARE
    v_pendiente    INT;
    v_incidente    INT;
    v_estado_final TEXT;
BEGIN
    SELECT id_estado_incidente INTO v_pendiente FROM EstadoIncidente WHERE nombre = 'Pendiente';

    -- Gravedad Baja (1) -> 1 recurso, basta para probar el cierre.
    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    VALUES (1, 1, v_pendiente, 1, 'P6 - cierre automático', 1)
    RETURNING id_incidente INTO v_incidente;

    -- Finalizamos con éxito todas las asignaciones del incidente.
    UPDATE Asignacion
    SET estado_exito = TRUE, timestamp_finalizacion = CURRENT_TIMESTAMP
    WHERE fk_incidente_id = v_incidente;

    SELECT ei.nombre INTO v_estado_final
    FROM Incidente i JOIN EstadoIncidente ei ON i.fk_estado_incidente_id = ei.id_estado_incidente
    WHERE i.id_incidente = v_incidente;
    IF v_estado_final <> 'Resuelto' THEN
        RAISE EXCEPTION 'FALLO R7: el incidente no pasó a Resuelto (quedó %).', v_estado_final;
    END IF;

    RAISE NOTICE 'ÉXITO P6: R7 cerró el incidente como Resuelto al finalizar todas sus asignaciones.';

    DELETE FROM Asignacion WHERE fk_incidente_id = v_incidente;
    DELETE FROM Incidente WHERE id_incidente = v_incidente;
    UPDATE Recurso SET fk_estado_recurso_id = 1 WHERE fk_estado_recurso_id <> 1;
END;
$$;

-- ----------------------------------------------------------------------------
-- PRUEBA 7: R1 — Umbral de recursos activos superado deja el incidente Pendiente
-- ----------------------------------------------------------------------------
\echo '>>> PRUEBA 7: Umbral de recursos activos superado -> Pendiente (R1)'

DO $$
DECLARE
    v_pendiente   INT;
    v_incidente   INT;
    v_umbral_old  INT;
    v_n_asig      INT;
    v_estado_inc  TEXT;
BEGIN
    SELECT id_estado_incidente INTO v_pendiente FROM EstadoIncidente WHERE nombre = 'Pendiente';

    -- Forzamos el umbral de la zona a 0 para simular capacidad agotada.
    SELECT umbral_incidentes_activos INTO v_umbral_old FROM Zona WHERE id_zona = 1;
    UPDATE Zona SET umbral_incidentes_activos = 0 WHERE id_zona = 1;

    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    VALUES (1, 3, v_pendiente, 1, 'P7 - umbral superado', 3)
    RETURNING id_incidente INTO v_incidente;

    SELECT count(*) INTO v_n_asig FROM Asignacion WHERE fk_incidente_id = v_incidente;
    SELECT ei.nombre INTO v_estado_inc
    FROM Incidente i JOIN EstadoIncidente ei ON i.fk_estado_incidente_id = ei.id_estado_incidente
    WHERE i.id_incidente = v_incidente;

    -- Restauramos el umbral ANTES de asertar, para no dejar el parámetro alterado si la prueba falla.
    UPDATE Zona SET umbral_incidentes_activos = v_umbral_old WHERE id_zona = 1;

    IF v_n_asig <> 0 THEN
        RAISE EXCEPTION 'FALLO R1 (umbral): con umbral 0 se asignaron % recursos (debían ser 0).', v_n_asig;
    END IF;
    IF v_estado_inc <> 'Pendiente' THEN
        RAISE EXCEPTION 'FALLO R1 (umbral): el incidente no quedó Pendiente (quedó %).', v_estado_inc;
    END IF;

    RAISE NOTICE 'ÉXITO P7: R20 dejó el incidente en Pendiente al alcanzarse la capacidad de la zona.';

    DELETE FROM Incidente WHERE id_incidente = v_incidente;
END;
$$;

-- ----------------------------------------------------------------------------
-- PRUEBA 8: Penalización automática por demora vía trigger en Asignacion
-- ----------------------------------------------------------------------------
\echo '>>> PRUEBA 8: Penalización automática por demora vía trigger en Asignacion'

DO $$
DECLARE
    v_pendiente   INT;
    v_incidente   INT;
    v_asig        INT;
    v_recurso     INT;
    v_sla         INT;
    v_tramo       INT;
    v_puntos_esp  INT := 2;
    v_puntos_obt  INT;
    v_gravedad_baja INT;
BEGIN
    SELECT id_estado_incidente INTO v_pendiente FROM EstadoIncidente WHERE nombre = 'Pendiente';
    SELECT id_gravedad INTO v_gravedad_baja FROM Gravedad WHERE nombre = 'Baja';

    -- Insertar incidente para asegurar que se crea asignación
    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    VALUES (1, v_gravedad_baja, v_pendiente, 1, 'P8 - test trigger penalizacion automatica', 1)
    RETURNING id_incidente INTO v_incidente;

    -- Obtener la asignación y recurso creados automáticamente
    SELECT id_asignacion, fk_recurso_id INTO v_asig, v_recurso
    FROM Asignacion WHERE fk_incidente_id = v_incidente LIMIT 1;

    -- Obtener SLA y minutos por punto
    SELECT tiempo_respuesta_minutos, minutos_por_punto_demora
    INTO v_sla, v_tramo
    FROM SLA WHERE fk_gravedad_id = v_gravedad_baja;

    -- Actualizar timestamp_llegada directamente simulando demora de SLA + tramo * puntos + offset
    UPDATE Asignacion
    SET timestamp_llegada = timestamp_asignacion + (v_sla + v_tramo * v_puntos_esp + 0.5) * INTERVAL '1 minute'
    WHERE id_asignacion = v_asig;

    -- Verificar que el trigger insertó la penalización automáticamente (sin llamar a sp_CalcularPenalizacion)
    SELECT COALESCE(puntaje, 0) INTO v_puntos_obt
    FROM Penalizacion
    WHERE fk_recurso_id = v_recurso
      AND motivo LIKE '%asignación #' || v_asig || '%'
    ORDER BY id_penalizacion DESC LIMIT 1;

    IF v_puntos_obt <> v_puntos_esp THEN
        RAISE EXCEPTION 'FALLO trigger penalizacion: esperado % puntos de penalización, obtenido %.', v_puntos_esp, v_puntos_obt;
    END IF;

    RAISE NOTICE 'ÉXITO P8: El trigger en Asignacion penalizó automáticamente la demora con % puntos.', v_puntos_obt;

    -- Limpieza
    DELETE FROM Asignacion WHERE fk_incidente_id = v_incidente;
    DELETE FROM Penalizacion WHERE fk_recurso_id = v_recurso;
    DELETE FROM Incidente WHERE id_incidente = v_incidente;
    UPDATE Recurso SET fk_estado_recurso_id = 1 WHERE fk_estado_recurso_id <> 1;
END;
$$;

-- Limpieza final: dejar el entorno operativo vacío y los recursos disponibles.
DELETE FROM Asignacion;
DELETE FROM Penalizacion;
DELETE FROM Incidente;
DELETE FROM Evento;
DELETE FROM Log;
UPDATE Recurso SET fk_estado_recurso_id = 1 WHERE fk_estado_recurso_id <> 1;

\echo '--------------------------------------------------'
\echo '>>> TODAS LAS PRUEBAS OK'
\echo '--------------------------------------------------'
