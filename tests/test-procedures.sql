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
-- Restaurar el estado de los recursos de la base de datos al finalizar
-- ----------------------------------------------------------------------------
UPDATE Recurso SET fk_estado_recurso_id = 1 WHERE fk_estado_recurso_id <> 1;

\echo '--------------------------------------------------'
\echo '>>> TODAS LAS PRUEBAS DE PROCEDIMIENTOS OK <<<'
\echo '--------------------------------------------------'
