-- =============================================================================
-- SIMULACION 08 - OBLIGATORIA: 20 INCIDENTES SIMULTANEOS
-- =============================================================================
-- Demuestra la carga de 20 incidentes simultáneos y el control de capacidad.
--
-- El modelo actual no tiene estado "En espera"; la regla R20 se representa como
-- incidente "Pendiente" sin asignación. Para forzar ese caso sin cargar cientos
-- de filas, dentro de la transacción se baja temporalmente el umbral de cada zona
-- a 1 incidente activo.
-- =============================================================================

\set ON_ERROR_STOP on
BEGIN;

DELETE FROM Asignacion;
DELETE FROM Penalizacion;
DELETE FROM Incidente;
DELETE FROM Evento;
UPDATE Recurso
SET fk_estado_recurso_id = (SELECT id_estado_recurso FROM EstadoRecurso WHERE nombre = 'Disponible')
WHERE fk_estado_recurso_id <> (SELECT id_estado_recurso FROM EstadoRecurso WHERE nombre = 'Disponible');
DELETE FROM Log;

UPDATE Zona
SET umbral_incidentes_activos = 1;

DO $$
DECLARE
    v_total INT;
    v_en_proceso INT;
    v_pendientes_sin_asignacion INT;
BEGIN
    INSERT INTO Incidente (
        fk_tipo_incidente_id,
        fk_gravedad_id,
        fk_estado_incidente_id,
        fk_zona_id,
        descripcion,
        prioridad
    )
    SELECT ti.id_tipo_incidente,
           g.id_gravedad,
           ei.id_estado_incidente,
           z.id_zona,
           'SIM-08 incidente simultaneo #' || s.n,
           1
    FROM generate_series(1, 20) AS s(n)
    JOIN TipoIncidente ti ON ti.id_tipo_incidente = ((s.n - 1) % 10) + 1
    JOIN Gravedad g ON g.nombre = 'Baja'
    JOIN EstadoIncidente ei ON ei.nombre = 'Pendiente'
    JOIN Zona z ON z.id_zona = ((s.n - 1) % 12) + 1;

    SELECT COUNT(*) INTO v_total
    FROM Incidente
    WHERE descripcion LIKE 'SIM-08 incidente simultaneo #%';

    SELECT COUNT(*) INTO v_en_proceso
    FROM Incidente i
    JOIN EstadoIncidente ei ON ei.id_estado_incidente = i.fk_estado_incidente_id
    WHERE i.descripcion LIKE 'SIM-08 incidente simultaneo #%'
      AND ei.nombre = 'En proceso';

    SELECT COUNT(*) INTO v_pendientes_sin_asignacion
    FROM Incidente i
    JOIN EstadoIncidente ei ON ei.id_estado_incidente = i.fk_estado_incidente_id
    WHERE i.descripcion LIKE 'SIM-08 incidente simultaneo #%'
      AND ei.nombre = 'Pendiente'
      AND NOT EXISTS (SELECT 1 FROM Asignacion a WHERE a.fk_incidente_id = i.id_incidente);

    IF v_total <> 20 THEN
        RAISE EXCEPTION 'SIM-08 fallo carga: se esperaban 20 incidentes, se insertaron %.', v_total;
    END IF;

    IF v_en_proceso < 1 THEN
        RAISE EXCEPTION 'SIM-08 fallo asignación: ningún incidente quedó En proceso.';
    END IF;

    IF v_pendientes_sin_asignacion < 1 THEN
        RAISE EXCEPTION 'SIM-08 fallo R20: se esperaba al menos un Pendiente sin asignación por capacidad.';
    END IF;

    RAISE NOTICE 'SIM-08 OK: 20 incidentes cargados; % En proceso y % Pendiente sin asignación.', v_en_proceso, v_pendientes_sin_asignacion;
END;
$$;

\echo 'SIM-08: resumen por estado'
SELECT ei.nombre AS estado_incidente, COUNT(*) AS cantidad
FROM Incidente i
JOIN EstadoIncidente ei ON ei.id_estado_incidente = i.fk_estado_incidente_id
WHERE i.descripcion LIKE 'SIM-08 incidente simultaneo #%'
GROUP BY ei.nombre
ORDER BY ei.nombre;

\echo 'SIM-08: incidentes pendientes sin asignación por control de capacidad'
SELECT i.id_incidente, i.descripcion, z.nombre AS zona, ei.nombre AS estado
FROM Incidente i
JOIN Zona z ON z.id_zona = i.fk_zona_id
JOIN EstadoIncidente ei ON ei.id_estado_incidente = i.fk_estado_incidente_id
WHERE i.descripcion LIKE 'SIM-08 incidente simultaneo #%'
  AND ei.nombre = 'Pendiente'
  AND NOT EXISTS (SELECT 1 FROM Asignacion a WHERE a.fk_incidente_id = i.id_incidente)
ORDER BY i.id_incidente;

\echo 'SIM-08: incidentes atendidos con asignación abierta'
SELECT i.id_incidente, i.descripcion, z.nombre AS zona, COUNT(a.id_asignacion) AS asignaciones_abiertas
FROM Incidente i
JOIN Zona z ON z.id_zona = i.fk_zona_id
JOIN Asignacion a ON a.fk_incidente_id = i.id_incidente AND a.timestamp_finalizacion IS NULL
WHERE i.descripcion LIKE 'SIM-08 incidente simultaneo #%'
GROUP BY i.id_incidente, i.descripcion, z.nombre
ORDER BY i.id_incidente;

ROLLBACK;
