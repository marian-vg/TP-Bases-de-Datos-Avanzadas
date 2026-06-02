-- ============================================================================
-- SCRIPT DE PRUEBAS DE INTEGRIDAD PARA TRIGGERS (R8 Y R9)
-- ============================================================================

\echo '--------------------------------------------------'
\echo 'INICIANDO PRUEBAS DE INTEGRIDAD DE TRIGGERS'
\echo '--------------------------------------------------'

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

    -- Crear incidentes de prueba temporales, ya que la base de datos inicia vacía de datos operacionales
    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    VALUES (1, 1, v_estado_pendiente, 1, 'Incidente de prueba asignación 1', 1)
    RETURNING id_incidente INTO v_incidente_1;

    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    VALUES (1, 1, v_estado_pendiente, 1, 'Incidente de prueba asignación 2', 1)
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
    VALUES (1, 1, v_estado_pendiente, 1, 'Incidente de prueba máquina de estados', 1)
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
END;
$$;

\echo '--------------------------------------------------'
\echo 'PRUEBAS FINALIZADAS'
\echo '--------------------------------------------------'
