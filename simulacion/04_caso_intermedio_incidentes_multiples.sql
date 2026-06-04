-- =============================================================================
-- SIMULACION 04 - CASO INTERMEDIO (incidentes multiples simultaneos)
-- =============================================================================
-- Que demuestra:
--   Varios incidentes activos al mismo tiempo en distintas zonas,
--   cada uno con asignacion automatica y estado "En proceso".
-- =============================================================================

DELETE FROM Asignacion;
DELETE FROM Penalizacion;
DELETE FROM Incidente;
DELETE FROM Evento;
DELETE FROM Log;

UPDATE Recurso SET fk_estado_recurso_id = 1 WHERE fk_estado_recurso_id <> 1;


-- Cinco incidentes distintos (tipo y zona diferentes entre si)

INSERT INTO Incidente (
    fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id,
    fk_zona_id, descripcion, prioridad
)
VALUES
    (1, 1, 1, 1,  'SIM-04 accidente zona 1',       1),
    (2, 2, 1, 2,  'SIM-04 incendio zona 2',        2),
    (4, 1, 1, 3,  'SIM-04 emergencia zona 3',      1),
    (5, 2, 1, 4,  'SIM-04 robo zona 4',            2),
    (8, 3, 1, 5,  'SIM-04 fuga gas zona 5',        3);


-- Todos deberian estar En proceso con al menos una asignacion abierta

SELECT
    i.descripcion,
    z.nombre AS zona,
    ei.nombre AS estado_incidente,
    COUNT(a.id_asignacion) AS asignaciones_abiertas
FROM Incidente i
JOIN Zona z ON i.fk_zona_id = z.id_zona
JOIN EstadoIncidente ei ON i.fk_estado_incidente_id = ei.id_estado_incidente
LEFT JOIN Asignacion a
  ON a.fk_incidente_id = i.id_incidente AND a.timestamp_finalizacion IS NULL
WHERE i.descripcion LIKE 'SIM-04%'
GROUP BY i.id_incidente, i.descripcion, z.nombre, ei.nombre
ORDER BY i.id_incidente;


-- Vista resumen de incidentes activos del lote

SELECT id_incidente, tipo_incidente, gravedad, estado_actual, zona
FROM vIncidentesActivos
WHERE descripcion LIKE 'SIM-04%'
ORDER BY id_incidente;


-- Recursos en transito u ocupados por estos incidentes

SELECT id_recurso, tipo_recurso, zona_actual_asignada, id_incidente, descripcion_incidente
FROM vRecursosOcupados
WHERE descripcion_incidente LIKE 'SIM-04%'
ORDER BY id_incidente;

-- Nota: si el recurso aun no registro llegada, puede no aparecer en vRecursosOcupados
-- (solo lista estado Ocupado). Ver la consulta anterior con asignaciones_abiertas.
