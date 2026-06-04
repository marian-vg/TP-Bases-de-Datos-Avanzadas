-- =============================================================================
-- SIMULACION 03 - CASO INTERMEDIO (falta de recursos en una zona)
-- =============================================================================
-- Que demuestra:
--   Al saturar la zona con muchos incidentes (tipos distintos para evitar R11),
--   los ultimos quedan en "Pendiente" sin asignacion porque no hay recursos libres.
-- =============================================================================

DELETE FROM Asignacion;
DELETE FROM Penalizacion;
DELETE FROM Incidente;
DELETE FROM Evento;
DELETE FROM Log;

UPDATE Recurso SET fk_estado_recurso_id = 1 WHERE fk_estado_recurso_id <> 1;


-- Recursos disponibles en zona 1 ANTES de saturar

SELECT COUNT(*) AS recursos_disponibles_zona_1
FROM Recurso r
JOIN EstadoRecurso er ON r.fk_estado_recurso_id = er.id_estado_recurso
JOIN ZonaRecurso zr ON zr.id_recurso = r.id_recurso AND zr.id_zona = 1
WHERE er.nombre = 'Disponible';


-- Insertar 30 incidentes en la misma zona (tipos 1 a 10 rotando = sin duplicado R11)

INSERT INTO Incidente (
    fk_tipo_incidente_id,
    fk_gravedad_id,
    fk_estado_incidente_id,
    fk_zona_id,
    descripcion,
    prioridad
)
SELECT
    ((s - 1) % 10) + 1,
    1,
    1,
    1,
    'SIM-03 saturacion zona 1 #' || s,
    1
FROM generate_series(1, 30) AS s;


-- Resumen: cuantos se atendieron y cuantos quedaron esperando recurso

SELECT
    ei.nombre AS estado_incidente,
    COUNT(*) AS cantidad
FROM Incidente i
JOIN EstadoIncidente ei ON i.fk_estado_incidente_id = ei.id_estado_incidente
WHERE i.descripcion LIKE 'SIM-03 saturacion zona 1 #%'
GROUP BY ei.nombre
ORDER BY ei.nombre;


-- Incidentes Pendiente sin ninguna asignacion (falta de recursos)

SELECT
    i.id_incidente,
    i.descripcion,
    ti.nombre AS tipo_incidente,
    ei.nombre AS estado
FROM Incidente i
JOIN TipoIncidente ti ON i.fk_tipo_incidente_id = ti.id_tipo_incidente
JOIN EstadoIncidente ei ON i.fk_estado_incidente_id = ei.id_estado_incidente
WHERE i.descripcion LIKE 'SIM-03 saturacion zona 1 #%'
  AND ei.nombre = 'Pendiente'
  AND NOT EXISTS (
      SELECT 1 FROM Asignacion a WHERE a.fk_incidente_id = i.id_incidente
  )
ORDER BY i.id_incidente
LIMIT 10;
