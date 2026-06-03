-- =============================================================================
-- SIMULACION 06 - CASO AVANZADO (penalizaciones por demora en el traslado)
-- =============================================================================
-- Que demuestra:
--   Si el recurso llega tarde respecto del SLA, se inserta una penalizacion.
--
-- Gravedad Baja -> SLA 30 minutos. Simulamos llegada a los 90 minutos.
-- =============================================================================

DELETE FROM Asignacion;
DELETE FROM Penalizacion;
DELETE FROM Incidente;
DELETE FROM Evento;
DELETE FROM Log;

UPDATE Recurso SET fk_estado_recurso_id = 1 WHERE fk_estado_recurso_id <> 1;


INSERT INTO Incidente (
    fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id,
    fk_zona_id, descripcion, prioridad
)
VALUES (4, 1, 1, 1, 'SIM-06 penalizacion traslado', 1);


-- Registrar llegada muy demorada (dispara penalizacion en el UPDATE de Asignacion)

UPDATE Asignacion
SET timestamp_llegada = timestamp_asignacion + INTERVAL '90 minutes'
WHERE fk_incidente_id = (
    SELECT id_incidente FROM Incidente WHERE descripcion = 'SIM-06 penalizacion traslado'
);


-- Penalizaciones generadas para el recurso asignado

SELECT
    p.id_penalizacion,
    p.fk_recurso_id,
    tp.nombre AS tipo_penalizacion,
    tp.puntaje,
    p.motivo
FROM Penalizacion p
JOIN TipoPenalizacion tp ON p.fk_tipo_penalizacion_id = tp.id_tipo_penalizacion
WHERE p.fk_recurso_id IN (
    SELECT a.fk_recurso_id
    FROM Asignacion a
    JOIN Incidente i ON a.fk_incidente_id = i.id_incidente
    WHERE i.descripcion = 'SIM-06 penalizacion traslado'
);


-- Vista de recursos penalizados

SELECT *
FROM vRecursosPenalizados
WHERE id_recurso IN (
    SELECT a.fk_recurso_id
    FROM Asignacion a
    JOIN Incidente i ON a.fk_incidente_id = i.id_incidente
    WHERE i.descripcion = 'SIM-06 penalizacion traslado'
);
