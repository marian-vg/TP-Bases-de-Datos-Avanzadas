-- =============================================================================
-- SIMULACION 04 - CASO INTERMEDIO: INCIDENTES MULTIPLES
-- =============================================================================
-- Demuestra que varios incidentes activos en distintas zonas reciben asignación
-- automática y quedan En proceso al mismo tiempo.
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

DO $$
DECLARE
    v_total INT;
    v_en_proceso INT;
    v_con_asignacion INT;
BEGIN
    INSERT INTO Incidente (
        fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id,
        fk_zona_id, descripcion, prioridad
    )
    SELECT ti.id_tipo_incidente, g.id_gravedad, ei.id_estado_incidente, z.id_zona, x.descripcion, 1
    FROM (VALUES
        ('Accidente de tránsito', 'Baja',     'Centro',        'SIM-04 accidente zona 1'),
        ('Incendio estructural',  'Moderada', 'Puerto Viejo',  'SIM-04 incendio zona 2'),
        ('Emergencia médica',     'Baja',     'Bajada Grande', 'SIM-04 emergencia zona 3'),
        ('Robo / Asalto',         'Moderada', 'Echeverría',    'SIM-04 robo zona 4'),
        ('Fuga de gas',           'Alta',     'Los Pinos',     'SIM-04 fuga gas zona 5')
    ) AS x(tipo_incidente, gravedad, zona, descripcion)
    JOIN TipoIncidente ti ON ti.nombre = x.tipo_incidente
    JOIN Gravedad g ON g.nombre = x.gravedad
    JOIN EstadoIncidente ei ON ei.nombre = 'Pendiente'
    JOIN Zona z ON z.nombre = x.zona;

    SELECT COUNT(*) INTO v_total FROM Incidente WHERE descripcion LIKE 'SIM-04%';

    SELECT COUNT(*) INTO v_en_proceso
    FROM Incidente i
    JOIN EstadoIncidente ei ON ei.id_estado_incidente = i.fk_estado_incidente_id
    WHERE i.descripcion LIKE 'SIM-04%'
      AND ei.nombre = 'En proceso';

    SELECT COUNT(*) INTO v_con_asignacion
    FROM Incidente i
    WHERE i.descripcion LIKE 'SIM-04%'
      AND EXISTS (
          SELECT 1
          FROM Asignacion a
          WHERE a.fk_incidente_id = i.id_incidente
            AND a.timestamp_finalizacion IS NULL
      );

    IF v_total <> 5 OR v_en_proceso <> 5 OR v_con_asignacion <> 5 THEN
        RAISE EXCEPTION 'SIM-04 fallo: total %, en proceso %, con asignación %.', v_total, v_en_proceso, v_con_asignacion;
    END IF;

    RAISE NOTICE 'SIM-04 OK: 5 incidentes simultáneos quedaron En proceso con asignación abierta.';
END;
$$;

\echo 'SIM-04: evidencia final'
SELECT i.id_incidente, i.descripcion, z.nombre AS zona, ei.nombre AS estado_incidente,
       COUNT(a.id_asignacion) AS asignaciones_abiertas
FROM Incidente i
JOIN Zona z ON z.id_zona = i.fk_zona_id
JOIN EstadoIncidente ei ON ei.id_estado_incidente = i.fk_estado_incidente_id
LEFT JOIN Asignacion a ON a.fk_incidente_id = i.id_incidente AND a.timestamp_finalizacion IS NULL
WHERE i.descripcion LIKE 'SIM-04%'
GROUP BY i.id_incidente, i.descripcion, z.nombre, ei.nombre
ORDER BY i.id_incidente;

ROLLBACK;
