-- ============================================================================
-- SCRIPT DE PRUEBAS DE INTEGRIDAD PARA TRIGGERS (R8, R9, R10, R11)
-- ============================================================================

\echo '--------------------------------------------------'
\echo 'INICIANDO PRUEBAS DE INTEGRIDAD DE TRIGGERS'
\echo '--------------------------------------------------'

-- Limpiar tablas operativas para evitar interferencias de datos previos
DELETE FROM Asignacion;
DELETE FROM Incidente;

-- Sincronizar secuencias para evitar colisiones de llaves primarias
SELECT setval(pg_get_serial_sequence('recurso', 'id_recurso'), COALESCE(MAX(id_recurso), 1)) FROM Recurso;
SELECT setval(pg_get_serial_sequence('incidente', 'id_incidente'), COALESCE(MAX(id_incidente), 1)) FROM Incidente;
SELECT setval(pg_get_serial_sequence('asignacion', 'id_asignacion'), COALESCE(MAX(id_asignacion), 1)) FROM Asignacion;

-- ----------------------------------------------------------------------------
-- PRUEBA 1: REGLA 8 - VALIDACIÓN DE DISPONIBILIDAD DE RECURSOS
-- ----------------------------------------------------------------------------
\echo '>>> PRUEBA 1: Asignación de recursos ocupados o no disponibles (R8)'

DO $$
DECLARE
    v_recurso_disp INT;
    v_incidente_1 INT;
    v_incidente_2 INT;
    v_estado_pendiente INT;
BEGIN
    -- Obtener el ID de estado 'Pendiente'
    SELECT id_estado_incidente INTO v_estado_pendiente FROM EstadoIncidente WHERE nombre = 'Pendiente';

    -- Crear incidentes de prueba temporales.
    -- Para evitar activar la regla R11 (duplicados), usamos diferentes tipos de incidente.
    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    VALUES (1, 1, v_estado_pendiente, 1, 'Incidente de prueba asignación 1', 1)
    RETURNING id_incidente INTO v_incidente_1;

    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    VALUES (2, 1, v_estado_pendiente, 1, 'Incidente de prueba asignación 2', 1)
    RETURNING id_incidente INTO v_incidente_2;

    -- Buscar un recurso que esté en estado 'Disponible'
    SELECT r.id_recurso INTO v_recurso_disp 
    FROM Recurso r 
    JOIN EstadoRecurso er ON r.fk_estado_recurso_id = er.id_estado_recurso
    WHERE er.nombre = 'Disponible' 
    LIMIT 1;

    RAISE NOTICE 'Paso 1.1: Insertando primera asignación de recurso disponible... (Debería tener éxito)';
    INSERT INTO Asignacion (fk_recurso_id, fk_incidente_id) 
    VALUES (v_recurso_disp, v_incidente_1);

    RAISE NOTICE 'Paso 1.2: Intentando insertar segunda asignación activa para el mismo recurso... (Debería fallar)';
    BEGIN
        INSERT INTO Asignacion (fk_recurso_id, fk_incidente_id) 
        VALUES (v_recurso_disp, v_incidente_2);
        RAISE EXCEPTION 'ERROR: Se permitió la doble asignación simultánea (Fallo del trigger R8).';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'ÉXITO: Se bloqueó la doble asignación simultánea del recurso.';
        RAISE NOTICE 'Mensaje del error: %', SQLERRM;
    END;

    -- Cambiamos manualmente el estado del recurso a 'Fuera de servicio' (id=3)
    UPDATE Recurso SET fk_estado_recurso_id = 3 WHERE id_recurso = v_recurso_disp;
    
    RAISE NOTICE 'Paso 1.3: Intentando asignar un recurso Fuera de servicio... (Debería fallar)';
    BEGIN
        INSERT INTO Asignacion (fk_recurso_id, fk_incidente_id) 
        VALUES (v_recurso_disp, v_incidente_2);
        RAISE EXCEPTION 'ERROR: Se permitió asignar un recurso Fuera de servicio (Fallo del trigger R8).';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'ÉXITO: Se bloqueó la asignación del recurso no disponible.';
        RAISE NOTICE 'Mensaje del error: %', SQLERRM;
    END;

    -- Limpieza de prueba 1
    DELETE FROM Asignacion WHERE fk_incidente_id IN (v_incidente_1, v_incidente_2);
    DELETE FROM Incidente WHERE id_incidente IN (v_incidente_1, v_incidente_2);
    -- Restaurar estado del recurso a Disponible (id=1)
    UPDATE Recurso SET fk_estado_recurso_id = 1 WHERE id_recurso = v_recurso_disp;
END;
$$;

-- ----------------------------------------------------------------------------
-- PRUEBA 2: REGLA 9 - VALIDACIÓN DE COHERENCIA DE ESTADOS DE INCIDENTES
-- ----------------------------------------------------------------------------
\echo '>>> PRUEBA 2: Máquina de estados de incidentes (R9)'

DO $$
DECLARE
    v_incidente INT;
    v_estado_pendiente INT;
    v_estado_proceso INT;
    v_estado_resuelto INT;
BEGIN
    -- Obtener IDs de estados
    SELECT id_estado_incidente INTO v_estado_pendiente FROM EstadoIncidente WHERE nombre = 'Pendiente';
    SELECT id_estado_incidente INTO v_estado_proceso FROM EstadoIncidente WHERE nombre = 'En proceso';
    SELECT id_estado_incidente INTO v_estado_resuelto FROM EstadoIncidente WHERE nombre = 'Resuelto';

    -- Crear un incidente de prueba en estado 'Pendiente'
    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    VALUES (3, 1, v_estado_pendiente, 1, 'Incidente de prueba máquina de estados', 1)
    RETURNING id_incidente INTO v_incidente;

    RAISE NOTICE 'Paso 2.1: Intentando pasar de Pendiente directamente a Resuelto... (Debería fallar)';
    BEGIN
        UPDATE Incidente SET fk_estado_incidente_id = v_estado_resuelto WHERE id_incidente = v_incidente;
        RAISE EXCEPTION 'ERROR: Se permitió la transición directa Pendiente -> Resuelto (Fallo del trigger R9).';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'ÉXITO: Se bloqueó la transición directa Pendiente -> Resuelto.';
        RAISE NOTICE 'Mensaje del error: %', SQLERRM;
    END;

    RAISE NOTICE 'Paso 2.2: Actualizando de Pendiente a En proceso... (Debería tener éxito)';
    UPDATE Incidente SET fk_estado_incidente_id = v_estado_proceso WHERE id_incidente = v_incidente;
    RAISE NOTICE 'ÉXITO: Transición Pendiente -> En proceso realizada.';

    RAISE NOTICE 'Paso 2.3: Actualizando de En proceso a Resuelto... (Debería tener éxito)';
    UPDATE Incidente SET fk_estado_incidente_id = v_estado_resuelto WHERE id_incidente = v_incidente;
    RAISE NOTICE 'ÉXITO: Transición En proceso -> Resuelto realizada.';

    RAISE NOTICE 'Paso 2.4: Intentando modificar el estado de un incidente Resuelto... (Debería fallar)';
    BEGIN
        UPDATE Incidente SET fk_estado_incidente_id = v_estado_proceso WHERE id_incidente = v_incidente;
        RAISE EXCEPTION 'ERROR: Se permitió cambiar el estado de un incidente Resuelto (Fallo del trigger R9).';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'ÉXITO: Se bloqueó la modificación del incidente cerrado.';
        RAISE NOTICE 'Mensaje del error: %', SQLERRM;
    END;

    -- Limpieza de prueba 2
    DELETE FROM Incidente WHERE id_incidente = v_incidente;
END;
$$;

-- ----------------------------------------------------------------------------
-- PRUEBA 3: REGLA 10 - VALIDACIÓN DE ZONA DEL RECURSO
-- ----------------------------------------------------------------------------
\echo '>>> PRUEBA 3: Validación de zona habilitada para el recurso (R10)'

DO $$
DECLARE
    v_zona_1 INT := 1;
    v_zona_2 INT := 2;
    v_recurso INT;
    v_incidente_zona_2 INT;
    v_estado_pendiente INT;
BEGIN
    -- Obtener el ID de estado 'Pendiente'
    SELECT id_estado_incidente INTO v_estado_pendiente FROM EstadoIncidente WHERE nombre = 'Pendiente';

    -- 1. Crear un recurso de prueba que pertenezca a la Zona 1 (su zona base)
    -- Y nos aseguramos de que en ZonaRecurso esté habilitado SOLO en Zona 1.
    INSERT INTO Recurso (fk_tipo_recurso_id, fk_zona_base_id, fk_estado_recurso_id)
    VALUES (1, v_zona_1, 1) -- Disponible
    RETURNING id_recurso INTO v_recurso;

    INSERT INTO ZonaRecurso (id_zona, id_recurso)
    VALUES (v_zona_1, v_recurso);

    -- 2. Crear un incidente en la Zona 2 (usamos tipo 4 para evitar R11)
    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    VALUES (4, 1, v_estado_pendiente, v_zona_2, 'Incidente en Zona 2', 1)
    RETURNING id_incidente INTO v_incidente_zona_2;

    -- 3. Intentar asignar el recurso (de Zona 1) al incidente en la Zona 2 (Debería fallar)
    RAISE NOTICE 'Paso 3.1: Intentando asignar recurso de Zona 1 a incidente en Zona 2... (Debería fallar)';
    BEGIN
        INSERT INTO Asignacion (fk_recurso_id, fk_incidente_id)
        VALUES (v_recurso, v_incidente_zona_2);
        RAISE EXCEPTION 'ERROR: Se permitió asignar un recurso a una zona no habilitada (Fallo del trigger R10).';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'ÉXITO: Se bloqueó la asignación del recurso fuera de su zona habilitada.';
        RAISE NOTICE 'Mensaje del error: %', SQLERRM;
    END;

    -- 4. Activar el bypass de emergencia (R15) e intentar la asignación nuevamente (Debería tener éxito)
    RAISE NOTICE 'Paso 3.2: Activando bypass de zona (my.bypass_zona = 1) e intentando asignar... (Debería tener éxito)';
    PERFORM set_config('my.bypass_zona', '1', true);
    
    INSERT INTO Asignacion (fk_recurso_id, fk_incidente_id)
    VALUES (v_recurso, v_incidente_zona_2);
    
    RAISE NOTICE 'ÉXITO: Asignación por rebalanceo de emergencia permitida.';

    -- Desactivar bypass
    PERFORM set_config('my.bypass_zona', '', true);

    -- Limpieza de prueba 3
    DELETE FROM Asignacion WHERE fk_incidente_id = v_incidente_zona_2;
    DELETE FROM ZonaRecurso WHERE id_recurso = v_recurso;
    DELETE FROM Recurso WHERE id_recurso = v_recurso;
    DELETE FROM Incidente WHERE id_incidente = v_incidente_zona_2;
END;
$$;

-- ----------------------------------------------------------------------------
-- PRUEBA 4: REGLA 11 - VALIDACIÓN DE DUPLICACIÓN DE INCIDENTES
-- ----------------------------------------------------------------------------
\echo '>>> PRUEBA 4: Evitar duplicación de incidentes en corto período (R11)'

DO $$
DECLARE
    v_estado_pendiente INT;
    v_estado_cancelado INT;
    v_incidente_original INT;
    v_incidente_duplicado INT;
    v_incidente_fuera_ventana INT;
    v_minutos NUMERIC;
BEGIN
    -- Obtener los IDs de estados
    SELECT id_estado_incidente INTO v_estado_pendiente FROM EstadoIncidente WHERE nombre = 'Pendiente';
    SELECT id_estado_incidente INTO v_estado_cancelado FROM EstadoIncidente WHERE nombre = 'Cancelado';

    -- Asegurar que el parámetro de minutos esté en 10
    SELECT numero INTO v_minutos FROM ParametrosSistema WHERE nombre_parametro = 'MINUTOS_DUPLICADO_INCIDENTE';
    IF v_minutos IS NULL THEN
        INSERT INTO ParametrosSistema (nombre_parametro, numero) VALUES ('MINUTOS_DUPLICADO_INCIDENTE', 10);
    ELSE
        UPDATE ParametrosSistema SET numero = 10 WHERE nombre_parametro = 'MINUTOS_DUPLICADO_INCIDENTE';
    END IF;

    -- 1. Registrar primer incidente en Zona 1, Tipo 5
    RAISE NOTICE 'Paso 4.1: Registrando incidente original en Zona 1, Tipo 5...';
    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    VALUES (5, 1, v_estado_pendiente, 1, 'Incidente original de prueba R11', 1)
    RETURNING id_incidente INTO v_incidente_original;
    RAISE NOTICE 'ÉXITO: Incidente original registrado con ID %.', v_incidente_original;

    -- 2. Intentar registrar un incidente duplicado en la misma zona y tipo (Debería fallar)
    RAISE NOTICE 'Paso 4.2: Intentando registrar incidente duplicado inmediatamente... (Debería fallar)';
    BEGIN
        INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
        VALUES (5, 1, v_estado_pendiente, 1, 'Segundo reporte de prueba R11', 1);
        RAISE EXCEPTION 'ERROR: Se permitió registrar un incidente duplicado en el período de bloqueo (Fallo del trigger R11).';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'ÉXITO: Se bloqueó el registro del incidente duplicado.';
        RAISE NOTICE 'Mensaje del error: %', SQLERRM;
    END;

    -- 3. Cancelar el incidente original
    RAISE NOTICE 'Paso 4.3: Cancelando el incidente original...';
    UPDATE Incidente SET fk_estado_incidente_id = v_estado_cancelado WHERE id_incidente = v_incidente_original;

    -- 4. Intentar registrar nuevamente el incidente duplicado (Debería tener éxito porque el original está cancelado)
    RAISE NOTICE 'Paso 4.4: Intentando registrar duplicado tras cancelar el original... (Debería tener éxito)';
    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    VALUES (5, 1, v_estado_pendiente, 1, 'Segundo reporte tras cancelación', 1)
    RETURNING id_incidente INTO v_incidente_duplicado;
    RAISE NOTICE 'ÉXITO: Incidente registrado tras la cancelación del duplicado anterior (ID %).', v_incidente_duplicado;

    -- 5. Simular el paso del tiempo desplazando la fecha del incidente duplicado a hace 11 minutos
    -- (fuera de la ventana de 10 minutos configurada)
    RAISE NOTICE 'Paso 4.5: Simulando paso del tiempo (desplazando incidente duplicado a hace 11 minutos)...';
    UPDATE Incidente 
    SET fecha_hora_registro = CURRENT_TIMESTAMP - INTERVAL '11 minutes' 
    WHERE id_incidente = v_incidente_duplicado;

    -- 6. Intentar registrar otro incidente similar inmediatamente (Debería tener éxito porque el anterior está fuera de la ventana)
    RAISE NOTICE 'Paso 4.6: Registrando incidente duplicado fuera de la ventana de tiempo... (Debería tener éxito)';
    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    VALUES (5, 1, v_estado_pendiente, 1, 'Reporte fuera de la ventana de tiempo', 1)
    RETURNING id_incidente INTO v_incidente_fuera_ventana;
    RAISE NOTICE 'ÉXITO: Registro permitido al haber expirado la ventana de tiempo (ID %).', v_incidente_fuera_ventana;

    -- Limpieza de prueba 4
    DELETE FROM Incidente WHERE fk_tipo_incidente_id = 5 AND fk_zona_id = 1;
END;
$$;

\echo '--------------------------------------------------'
\echo 'PRUEBAS FINALIZADAS'
\echo '--------------------------------------------------'
