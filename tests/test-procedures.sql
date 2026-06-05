-- ============================================================================
-- SCRIPT DE PRUEBAS DE INTEGRIDAD PARA PROCEDIMIENTOS ALMACENADOS (test-procedures.sql)
-- ============================================================================
--
-- Este script ejercita el procedimiento sp_AsignarRecurso (P1) y simula su
-- comportamiento bajo diversas condiciones operativas (casos de éxito, control
-- de errores y límites).
--
-- Patrón de aserción: Cada bloque de prueba verifica condiciones y lanza
-- RAISE EXCEPTION en caso de error. Si todo el script ejecuta sin problemas,
-- finalizará informando '>>> TODAS LAS PRUEBAS DE PROCEDIMIENTOS OK'.
-- ============================================================================

\set ON_ERROR_STOP on

\echo '--------------------------------------------------'
\echo 'INICIANDO PRUEBAS DE PROCEDIMIENTOS ALMACENADOS'
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

-- ----------------------------------------------------------------------------
-- PRUEBA 1: Validación de Incidente Inexistente
-- ----------------------------------------------------------------------------
\echo '>>> PRUEBA 1: sp_AsignarRecurso con incidente inexistente (Debería fallar)'

DO $$
DECLARE
    v_bloqueado BOOLEAN := FALSE;
BEGIN
    BEGIN
        CALL sp_AsignarRecurso(-9999);
    EXCEPTION WHEN OTHERS THEN
        v_bloqueado := TRUE;
        RAISE NOTICE '   (Bloqueo correcto: %)', SQLERRM;
    END;

    IF NOT v_bloqueado THEN
        RAISE EXCEPTION 'FALLO: sp_AsignarRecurso permitió la ejecución con un ID de incidente no existente.';
    ELSE
        RAISE NOTICE 'ÉXITO: Se bloqueó correctamente la ejecución para incidente inexistente.';
    END IF;
END;
$$;


-- ----------------------------------------------------------------------------
-- PRUEBA 2: Validación de Incidente en Estado Finalizado (Resuelto/Cerrado)
-- ----------------------------------------------------------------------------
\echo '>>> PRUEBA 2: sp_AsignarRecurso con incidente finalizado (Debería fallar)'

DO $$
DECLARE
    v_incidente INT;
    v_estado_resuelto INT;
    v_bloqueado BOOLEAN := FALSE;
BEGIN
    -- Obtener ID del estado Resuelto
    SELECT id_estado_incidente INTO v_estado_resuelto FROM EstadoIncidente WHERE nombre = 'Resuelto';

    -- Insertar incidente directamente en estado Resuelto
    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    VALUES (1, 1, v_estado_resuelto, 1, 'Incidente finalizado de prueba', 1)
    RETURNING id_incidente INTO v_incidente;

    BEGIN
        CALL sp_AsignarRecurso(v_incidente);
    EXCEPTION WHEN OTHERS THEN
        v_bloqueado := TRUE;
        RAISE NOTICE '   (Bloqueo correcto: %)', SQLERRM;
    END;

    IF NOT v_bloqueado THEN
        RAISE EXCEPTION 'FALLO: sp_AsignarRecurso permitió asignar recursos a un incidente en estado finalizado.';
    ELSE
        RAISE NOTICE 'ÉXITO: Se bloqueó correctamente la asignación a un incidente finalizado.';
    END IF;

    -- Limpieza local
    DELETE FROM Asignacion WHERE fk_incidente_id = v_incidente;
    DELETE FROM Incidente WHERE id_incidente = v_incidente;
END;
$$;


-- ----------------------------------------------------------------------------
-- PRUEBA 3: Asignación Normal / Recuperación de Flujo cuando hay recursos disponibles
-- ----------------------------------------------------------------------------
\echo '>>> PRUEBA 3: Simular recuperación de asignación cuando se habilitan recursos'

DO $$
DECLARE
    v_incidente INT;
    v_pendiente INT;
    v_tipo_rec_compatible INT;
    v_estado_disponible INT;
    v_estado_fueraservicio INT;
    v_n_asig INT;
    v_estado_inc TEXT;
    v_recurso_id INT;
BEGIN
    -- Obtener IDs de catálogos
    SELECT id_estado_incidente INTO v_pendiente FROM EstadoIncidente WHERE nombre = 'Pendiente';
    SELECT id_estado_recurso INTO v_estado_disponible FROM EstadoRecurso WHERE nombre = 'Disponible';
    SELECT id_estado_recurso INTO v_estado_fueraservicio FROM EstadoRecurso WHERE nombre = 'Fuera de servicio';

    -- Obtener tipo de recurso compatible para tipo de incidente 1
    SELECT fk_tipo_recurso_id INTO v_tipo_rec_compatible
    FROM TipoIncidenteTipoRecurso
    WHERE fk_tipo_incidente_id = 1
    LIMIT 1;

    -- 1. Poner temporalmente todos los recursos de la base de datos en 'Fuera de servicio'
    -- para simular que no hay stock disponible de ningún tipo compatible al momento de crear el incidente.
    UPDATE Recurso SET fk_estado_recurso_id = v_estado_fueraservicio;

    -- 2. Insertar un incidente de Gravedad Alta (3), que requiere 2 recursos (R5).
    -- Al no haber recursos compatibles disponibles, el trigger automático trg_asignacion_automatica
    -- no podrá asignar nada. El incidente quedará Pendiente con 0 asignaciones.
    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    VALUES (1, 3, v_pendiente, 1, 'Incidente en espera de recursos', 3)
    RETURNING id_incidente INTO v_incidente;

    -- Verificar que quedó con 0 asignaciones y estado Pendiente
    SELECT COUNT(*) INTO v_n_asig FROM Asignacion WHERE fk_incidente_id = v_incidente;
    SELECT nombre INTO v_estado_inc FROM Incidente i JOIN EstadoIncidente e ON i.fk_estado_incidente_id = e.id_estado_incidente WHERE i.id_incidente = v_incidente;

    IF v_n_asig <> 0 OR v_estado_inc <> 'Pendiente' THEN
        RAISE EXCEPTION 'PRECONDICIÓN FALLIDA: El incidente debió crearse con 0 asignaciones y en Pendiente. Asig: %, Estado: %', v_n_asig, v_estado_inc;
    END IF;

    -- 3. Habilitar 2 recursos compatibles poniéndolos de vuelta en 'Disponible' y habilitados en zona 1.
    -- (Nos aseguramos de que estén habilitados en la zona 1 para evitar rebalanceo local en esta etapa).
    FOR v_recurso_id IN
        SELECT id_recurso FROM Recurso WHERE fk_tipo_recurso_id = v_tipo_rec_compatible LIMIT 2
    LOOP
        UPDATE Recurso SET fk_estado_recurso_id = v_estado_disponible WHERE id_recurso = v_recurso_id;

        -- Garantizar zona habilitada para el test
        INSERT INTO ZonaRecurso (id_zona, id_recurso)
        VALUES (1, v_recurso_id)
        ON CONFLICT DO NOTHING;
    END LOOP;

    -- 4. Ejecutar el Stored Procedure para simular la asignación manual/diferida
    RAISE NOTICE '   Invocando sp_AsignarRecurso para el incidente %...', v_incidente;
    CALL sp_AsignarRecurso(v_incidente);

    -- 5. Aserción de resultados esperados:
    --   - Deben haberse asignado 2 recursos.
    --   - El incidente debe haber pasado a 'En proceso'.
    --   - Los recursos asignados deben estar ahora 'En tránsito' hasta registrar el arribo.
    SELECT COUNT(*) INTO v_n_asig FROM Asignacion WHERE fk_incidente_id = v_incidente AND timestamp_finalizacion IS NULL;
    IF v_n_asig <> 2 THEN
        RAISE EXCEPTION 'FALLO: sp_AsignarRecurso debía asignar 2 recursos, asignó %', v_n_asig;
    END IF;

    SELECT nombre INTO v_estado_inc FROM Incidente i JOIN EstadoIncidente e ON i.fk_estado_incidente_id = e.id_estado_incidente WHERE i.id_incidente = v_incidente;
    IF v_estado_inc <> 'En proceso' THEN
        RAISE EXCEPTION 'FALLO: El incidente debió pasar a "En proceso", quedó en "%"', v_estado_inc;
    END IF;

    SELECT COUNT(*) INTO v_n_asig
    FROM Asignacion a
    JOIN Recurso r ON a.fk_recurso_id = r.id_recurso
    JOIN EstadoRecurso er ON r.fk_estado_recurso_id = er.id_estado_recurso
    WHERE a.fk_incidente_id = v_incidente AND er.nombre = 'En tránsito';

    IF v_n_asig <> 2 THEN
        RAISE EXCEPTION 'FALLO: Los recursos asignados debían quedar "En tránsito", pero solo hay %', v_n_asig;
    END IF;

    RAISE NOTICE 'ÉXITO: Se asignaron los recursos en forma diferida y cambió correctamente el estado del incidente.';

    -- Limpieza local
    DELETE FROM Asignacion WHERE fk_incidente_id = v_incidente;
    DELETE FROM Incidente WHERE id_incidente = v_incidente;
    UPDATE Recurso SET fk_estado_recurso_id = v_estado_disponible;
END;
$$;


-- ----------------------------------------------------------------------------
-- PRUEBA 4: Control de Asignaciones Existentes / Idempotencia de Llamada
-- ----------------------------------------------------------------------------
\echo '>>> PRUEBA 4: Invocación redundante de sp_AsignarRecurso (No-Op)'

DO $$
DECLARE
    v_incidente INT;
    v_pendiente INT;
    v_tipo_rec_compatible INT;
    v_estado_disponible INT;
    v_estado_fueraservicio INT;
    v_n_asig_inicial INT;
    v_n_asig_final INT;
    v_recurso_id INT;
BEGIN
    SELECT id_estado_incidente INTO v_pendiente FROM EstadoIncidente WHERE nombre = 'Pendiente';
    SELECT id_estado_recurso INTO v_estado_disponible FROM EstadoRecurso WHERE nombre = 'Disponible';
    SELECT id_estado_recurso INTO v_estado_fueraservicio FROM EstadoRecurso WHERE nombre = 'Fuera de servicio';

    -- Obtener tipo compatible
    SELECT fk_tipo_recurso_id INTO v_tipo_rec_compatible
    FROM TipoIncidenteTipoRecurso
    WHERE fk_tipo_incidente_id = 1
    LIMIT 1;

    -- Poner temporalmente todos los recursos en 'Fuera de servicio'
    UPDATE Recurso SET fk_estado_recurso_id = v_estado_fueraservicio;

    -- Asegurar recursos disponibles (solo 2 compatibles)
    FOR v_recurso_id IN
        SELECT id_recurso FROM Recurso WHERE fk_tipo_recurso_id = v_tipo_rec_compatible LIMIT 2
    LOOP
        UPDATE Recurso SET fk_estado_recurso_id = v_estado_disponible WHERE id_recurso = v_recurso_id;
        INSERT INTO ZonaRecurso (id_zona, id_recurso) VALUES (1, v_recurso_id) ON CONFLICT DO NOTHING;
    END LOOP;

    -- Insertar incidente de Gravedad Moderada (2), requiere 1 recurso (R5).
    -- La inserción ejecutará la asignación automática (asigna 1 recurso).
    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    VALUES (1, 2, v_pendiente, 1, 'Incidente para prueba redundancia', 2)
    RETURNING id_incidente INTO v_incidente;

    SELECT COUNT(*) INTO v_n_asig_inicial FROM Asignacion WHERE fk_incidente_id = v_incidente AND timestamp_finalizacion IS NULL;

    IF v_n_asig_inicial <> 1 THEN
        RAISE EXCEPTION 'PRECONDICIÓN FALLIDA: Se esperaba 1 recurso asignado al insertar, se asignaron: %', v_n_asig_inicial;
    END IF;

    -- Volver a llamar sp_AsignarRecurso. Como ya tiene la cantidad requerida (1), no debe asignar más.
    RAISE NOTICE '   Llamando sp_AsignarRecurso redundante para incidente % con 1 asignación activa...', v_incidente;
    CALL sp_AsignarRecurso(v_incidente);

    SELECT COUNT(*) INTO v_n_asig_final FROM Asignacion WHERE fk_incidente_id = v_incidente AND timestamp_finalizacion IS NULL;
    IF v_n_asig_final <> v_n_asig_inicial THEN
        RAISE EXCEPTION 'FALLO: El SP agregó asignaciones redundantes (% -> %)', v_n_asig_inicial, v_n_asig_final;
    END IF;

    RAISE NOTICE 'ÉXITO: La ejecución fue idempotente y no agregó recursos redundantes.';

    -- Limpieza local
    DELETE FROM Asignacion WHERE fk_incidente_id = v_incidente;
    DELETE FROM Incidente WHERE id_incidente = v_incidente;
    UPDATE Recurso SET fk_estado_recurso_id = v_estado_disponible;
END;
$$;


-- ----------------------------------------------------------------------------
-- PRUEBA 5: sp_CerrarIncidente - Caso de Error (Incidente Inexistente)
-- ----------------------------------------------------------------------------
\echo '>>> PRUEBA 5: sp_CerrarIncidente con incidente inexistente (Debería fallar)'

DO $$
DECLARE
    v_bloqueado BOOLEAN := FALSE;
BEGIN
    BEGIN
        CALL sp_CerrarIncidente(-9999);
    EXCEPTION WHEN OTHERS THEN
        v_bloqueado := TRUE;
        RAISE NOTICE '   (Bloqueo correcto: %)', SQLERRM;
    END;

    IF NOT v_bloqueado THEN
        RAISE EXCEPTION 'FALLO: sp_CerrarIncidente permitió la ejecución con un ID de incidente no existente.';
    ELSE
        RAISE NOTICE 'ÉXITO: Se bloqueó correctamente la ejecución para incidente inexistente.';
    END IF;
END;
$$;


-- ----------------------------------------------------------------------------
-- PRUEBA 6: sp_CerrarIncidente - Caso de Error (Incidente ya Finalizado)
-- ----------------------------------------------------------------------------
\echo '>>> PRUEBA 6: sp_CerrarIncidente con incidente ya cerrado (Debería fallar)'

DO $$
DECLARE
    v_incidente INT;
    v_estado_resuelto INT;
    v_bloqueado BOOLEAN := FALSE;
BEGIN
    SELECT id_estado_incidente INTO v_estado_resuelto FROM EstadoIncidente WHERE nombre = 'Resuelto';

    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    VALUES (1, 1, v_estado_resuelto, 1, 'Incidente ya resuelto', 1)
    RETURNING id_incidente INTO v_incidente;

    BEGIN
        CALL sp_CerrarIncidente(v_incidente);
    EXCEPTION WHEN OTHERS THEN
        v_bloqueado := TRUE;
        RAISE NOTICE '   (Bloqueo correcto: %)', SQLERRM;
    END;

    IF NOT v_bloqueado THEN
        RAISE EXCEPTION 'FALLO: sp_CerrarIncidente permitió cerrar un incidente que ya estaba resuelto.';
    ELSE
        RAISE NOTICE 'ÉXITO: Se bloqueó correctamente el cierre de un incidente ya resuelto.';
    END IF;

    -- Limpieza local
    DELETE FROM Asignacion WHERE fk_incidente_id = v_incidente;
    DELETE FROM Incidente WHERE id_incidente = v_incidente;
END;
$$;


-- ----------------------------------------------------------------------------
-- PRUEBA 7: sp_CerrarIncidente - Caso Exitoso (Cierre Normal y Liberación)
-- ----------------------------------------------------------------------------
\echo '>>> PRUEBA 7: sp_CerrarIncidente cierre normal de incidente con recursos ocupados'

DO $$
DECLARE
    v_incidente INT;
    v_pendiente INT;
    v_estado_resuelto INT;
    v_estado_disponible INT;
    v_tipo_rec_compatible INT;
    v_recurso_id INT;
    v_n_asig INT;
    v_recurso_estado INT;
    v_estado_actual TEXT;
BEGIN
    SELECT id_estado_incidente INTO v_pendiente FROM EstadoIncidente WHERE nombre = 'Pendiente';
    SELECT id_estado_incidente INTO v_estado_resuelto FROM EstadoIncidente WHERE nombre = 'Resuelto';
    SELECT id_estado_recurso INTO v_estado_disponible FROM EstadoRecurso WHERE nombre = 'Disponible';

    -- Obtener tipo compatible
    SELECT fk_tipo_recurso_id INTO v_tipo_rec_compatible
    FROM TipoIncidenteTipoRecurso
    WHERE fk_tipo_incidente_id = 1
    LIMIT 1;

    -- Asegurar recursos disponibles
    FOR v_recurso_id IN
        SELECT id_recurso FROM Recurso WHERE fk_tipo_recurso_id = v_tipo_rec_compatible LIMIT 1
    LOOP
        UPDATE Recurso SET fk_estado_recurso_id = v_estado_disponible WHERE id_recurso = v_recurso_id;
        INSERT INTO ZonaRecurso (id_zona, id_recurso) VALUES (1, v_recurso_id) ON CONFLICT DO NOTHING;
    END LOOP;

    -- Insertar incidente de Gravedad Moderada (2), requiere 1 recurso (R5).
    -- La inserción ejecutará la asignación automática (asigna 1 recurso).
    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    VALUES (1, 2, v_pendiente, 1, 'Incidente para prueba de cierre normal', 2)
    RETURNING id_incidente INTO v_incidente;

    -- Verificar que tiene 1 asignación activa y el incidente está 'En proceso'
    SELECT COUNT(*) INTO v_n_asig FROM Asignacion WHERE fk_incidente_id = v_incidente AND timestamp_finalizacion IS NULL;
    IF v_n_asig <> 1 THEN
        RAISE EXCEPTION 'PRECONDICIÓN FALLIDA: Se esperaba 1 asignación activa, se encontraron %', v_n_asig;
    END IF;

    SELECT r.fk_estado_recurso_id INTO v_recurso_estado
    FROM Asignacion a
    JOIN Recurso r ON a.fk_recurso_id = r.id_recurso
    WHERE a.fk_incidente_id = v_incidente AND a.timestamp_finalizacion IS NULL;

    SELECT nombre INTO v_estado_actual FROM Incidente i JOIN EstadoIncidente e ON i.fk_estado_incidente_id = e.id_estado_incidente WHERE i.id_incidente = v_incidente;

    -- El recurso debe estar Ocupado (id 2) e incidente En proceso
    IF v_recurso_estado = v_estado_disponible OR v_estado_actual <> 'En proceso' THEN
        RAISE EXCEPTION 'PRECONDICIÓN FALLIDA: Estado del recurso o incidente incoherente. Recurso Estado: %, Incidente Estado: %', v_recurso_estado, v_estado_actual;
    END IF;

    -- Invocamos sp_CerrarIncidente
    RAISE NOTICE '   Invocando sp_CerrarIncidente para el incidente %...', v_incidente;
    CALL sp_CerrarIncidente(v_incidente);

    -- Verificar que:
    --   1. El incidente está ahora en estado 'Resuelto'.
    --   2. El recurso asociado ahora está 'Disponible'.
    --   3. La asignación se encuentra finalizada.
    SELECT nombre INTO v_estado_actual FROM Incidente i JOIN EstadoIncidente e ON i.fk_estado_incidente_id = e.id_estado_incidente WHERE i.id_incidente = v_incidente;
    IF v_estado_actual <> 'Resuelto' THEN
        RAISE EXCEPTION 'FALLO: El incidente debió quedar en "Resuelto", quedó en "%"', v_estado_actual;
    END IF;

    SELECT COUNT(*) INTO v_n_asig FROM Asignacion WHERE fk_incidente_id = v_incidente AND timestamp_finalizacion IS NULL;
    IF v_n_asig <> 0 THEN
        RAISE EXCEPTION 'FALLO: Quedaron asignaciones activas para el incidente.';
    END IF;

    SELECT r.fk_estado_recurso_id INTO v_recurso_estado
    FROM Asignacion a
    JOIN Recurso r ON a.fk_recurso_id = r.id_recurso
    WHERE a.fk_incidente_id = v_incidente;

    IF v_recurso_estado <> v_estado_disponible THEN
        RAISE EXCEPTION 'FALLO: El recurso no fue liberado a Disponible (Estado actual: %)', v_recurso_estado;
    END IF;

    RAISE NOTICE 'ÉXITO: El incidente se cerró, las asignaciones se finalizaron y los recursos fueron liberados.';

    -- Limpieza local
    DELETE FROM Asignacion WHERE fk_incidente_id = v_incidente;
    DELETE FROM Incidente WHERE id_incidente = v_incidente;
END;
$$;


-- ----------------------------------------------------------------------------
-- PRUEBA 8: sp_CerrarIncidente - Caso Incidente Pendiente (R9 Pendiente -> Cancelado)
-- ----------------------------------------------------------------------------
\echo '>>> PRUEBA 8: sp_CerrarIncidente cerrar incidente en estado Pendiente'

DO $$
DECLARE
    v_incidente INT;
    v_pendiente INT;
    v_estado_actual TEXT;
BEGIN
    SELECT id_estado_incidente INTO v_pendiente FROM EstadoIncidente WHERE nombre = 'Pendiente';

    -- Poner todos los recursos a Fuera de servicio para asegurar 0 asignaciones automáticas
    UPDATE Recurso SET fk_estado_recurso_id = 3;

    -- Insertar incidente
    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    VALUES (1, 1, v_pendiente, 1, 'Incidente pendiente sin recursos', 1)
    RETURNING id_incidente INTO v_incidente;

    -- Invocamos sp_CerrarIncidente
    RAISE NOTICE '   Invocando sp_CerrarIncidente para incidente Pendiente %...', v_incidente;
    CALL sp_CerrarIncidente(v_incidente);

    -- Verificar que transitó a Cancelado (R9)
    SELECT nombre INTO v_estado_actual
    FROM Incidente i
    JOIN EstadoIncidente e ON i.fk_estado_incidente_id = e.id_estado_incidente
    WHERE i.id_incidente = v_incidente;

    IF v_estado_actual <> 'Cancelado' THEN
        RAISE EXCEPTION 'FALLO: Un incidente sin asignaciones en estado Pendiente debió cerrarse como Cancelado. Estado actual: %', v_estado_actual;
    END IF;

    RAISE NOTICE 'ÉXITO: Incidente Pendiente cerrado correctamente transitando a Cancelado.';

    -- Limpieza local
    DELETE FROM Incidente WHERE id_incidente = v_incidente;
    UPDATE Recurso SET fk_estado_recurso_id = 1;
END;
$$;


-- ----------------------------------------------------------------------------
-- PRUEBA 9: sp_SimularEventoSensor - Casos de Error (Sensor/Evento inexistentes)
-- ----------------------------------------------------------------------------
\echo '>>> PRUEBA 9: sp_SimularEventoSensor validación de parámetros inválidos'

DO $$
DECLARE
    v_sensor INT;
    v_bloqueado BOOLEAN;
BEGIN
    -- 9.1 Sensor Inexistente
    v_bloqueado := FALSE;
    BEGIN
        CALL sp_SimularEventoSensor(-9999, 1);
    EXCEPTION WHEN OTHERS THEN
        v_bloqueado := TRUE;
        RAISE NOTICE '   (Bloqueo correcto sensor: %)', SQLERRM;
    END;
    IF NOT v_bloqueado THEN
        RAISE EXCEPTION 'FALLO: sp_SimularEventoSensor no falló ante un ID de sensor inválido.';
    END IF;

    -- Obtener un sensor existente
    SELECT id_sensor INTO v_sensor FROM Sensor LIMIT 1;

    -- 9.2 Tipo Evento Inexistente
    v_bloqueado := FALSE;
    BEGIN
        CALL sp_SimularEventoSensor(v_sensor, -9999);
    EXCEPTION WHEN OTHERS THEN
        v_bloqueado := TRUE;
        RAISE NOTICE '   (Bloqueo correcto tipo evento: %)', SQLERRM;
    END;
    IF NOT v_bloqueado THEN
        RAISE EXCEPTION 'FALLO: sp_SimularEventoSensor no falló ante un ID de tipo de evento inválido.';
    END IF;

    RAISE NOTICE 'ÉXITO: Se validaron correctamente los parámetros de sensor y tipo de evento.';
END;
$$;


-- ----------------------------------------------------------------------------
-- PRUEBA 10: sp_SimularEventoSensor - Caso Exitoso (Mapeo Único y Asignación)
-- ----------------------------------------------------------------------------
\echo '>>> PRUEBA 10: sp_SimularEventoSensor simulación de evento con promoción única'

DO $$
DECLARE
    v_sensor INT;
    v_tipo_evento INT := 2; -- Mapeo único: tipo_evento 2 -> tipo_incidente 8 (gravedad 3)
    v_incidente INT;
    v_evento INT;
BEGIN
    -- Asegurar recursos disponibles
    UPDATE Recurso SET fk_estado_recurso_id = 1;

    -- Buscar un sensor compatible habilitado en zona 1
    SELECT id_sensor INTO v_sensor FROM Sensor WHERE fk_zona_id = 1 LIMIT 1;

    IF v_sensor IS NULL THEN
        RAISE EXCEPTION 'PRECONDICIÓN FALLIDA: No hay sensores en la zona 1 para el test.';
    END IF;

    -- Limpieza de Log/Incidente previos para evitar interferencias
    DELETE FROM Asignacion;
    DELETE FROM Incidente;
    DELETE FROM Evento;

    -- Asegurar confianza del sensor al 100% insertando mantenimiento hoy (R21)
    INSERT INTO MantenimientoSensor (fk_sensor_id, fecha)
    VALUES (v_sensor, CURRENT_DATE);

    -- Ejecutamos la simulación
    RAISE NOTICE '   Invocando sp_SimularEventoSensor para sensor % y tipo evento %...', v_sensor, v_tipo_evento;
    CALL sp_SimularEventoSensor(v_sensor, v_tipo_evento);

    -- Comprobar que:
    --   1. Se insertó un Evento.
    --   2. Se insertó un Incidente asociado a ese evento de tipo compatible.
    SELECT MAX(id_evento) INTO v_evento FROM Evento WHERE fk_sensor_id = v_sensor AND fk_tipo_evento_id = v_tipo_evento;
    IF v_evento IS NULL THEN
        RAISE EXCEPTION 'FALLO: No se registró el evento del sensor.';
    END IF;

    SELECT id_incidente INTO v_incidente FROM Incidente WHERE fk_evento_id = v_evento;
    IF v_incidente IS NULL THEN
        RAISE EXCEPTION 'FALLO: El evento no se promovió a incidente automáticamente.';
    END IF;

    -- Limpieza local
    DELETE FROM Asignacion WHERE fk_incidente_id = v_incidente;
    DELETE FROM Incidente WHERE id_incidente = v_incidente;
    DELETE FROM Evento WHERE id_evento = v_evento;
    DELETE FROM MantenimientoSensor WHERE fk_sensor_id = v_sensor;
END;
$$;


-- ----------------------------------------------------------------------------
-- PRUEBA 11: sp_SimularEventoSensor - Caso Mapeo Múltiple (No Promoción)
-- ----------------------------------------------------------------------------
\echo '>>> PRUEBA 11: sp_SimularEventoSensor simulación de evento con mapeo no único (No-Op)'

DO $$
DECLARE
    v_sensor INT;
    v_tipo_evento INT := 1; -- Mapeo múltiple: tipo_evento 1 -> incidente 2 e incidente 3
    v_incidente INT;
    v_evento INT;
BEGIN
    SELECT id_sensor INTO v_sensor FROM Sensor WHERE fk_zona_id = 1 LIMIT 1;

    -- Limpieza previa
    DELETE FROM Asignacion;
    DELETE FROM Incidente;
    DELETE FROM Evento;

    -- Asegurar confianza del sensor al 100% insertando mantenimiento hoy (R21)
    INSERT INTO MantenimientoSensor (fk_sensor_id, fecha)
    VALUES (v_sensor, CURRENT_DATE);

    -- Ejecutamos la simulación
    RAISE NOTICE '   Invocando sp_SimularEventoSensor con mapeo múltiple (sensor %, tipo evento %)...', v_sensor, v_tipo_evento;
    CALL sp_SimularEventoSensor(v_sensor, v_tipo_evento);

    -- Comprobar que:
    --   1. Se registró el evento.
    --   2. NO se creó ningún incidente (mapeo no único).
    SELECT MAX(id_evento) INTO v_evento FROM Evento WHERE fk_sensor_id = v_sensor AND fk_tipo_evento_id = v_tipo_evento;
    IF v_evento IS NULL THEN
        RAISE EXCEPTION 'FALLO: Debería haberse insertado el evento del sensor.';
    END IF;

    SELECT id_incidente INTO v_incidente FROM Incidente WHERE fk_evento_id = v_evento;
    IF v_incidente IS NOT NULL THEN
        RAISE EXCEPTION 'FALLO: Se creó un incidente para un evento con mapeo de tipos no único.';
    END IF;

    -- Limpieza local
    DELETE FROM Evento WHERE id_evento = v_evento;
    DELETE FROM MantenimientoSensor WHERE fk_sensor_id = v_sensor;
END;
$$;


-- ----------------------------------------------------------------------------
-- Restaurar el estado de los recursos de la base de datos al finalizar
-- ----------------------------------------------------------------------------
UPDATE Recurso SET fk_estado_recurso_id = 1 WHERE fk_estado_recurso_id <> 1;

\echo '--------------------------------------------------'
\echo '>>> TODAS LAS PRUEBAS DE PROCEDIMIENTOS OK <<<'
\echo '--------------------------------------------------'
