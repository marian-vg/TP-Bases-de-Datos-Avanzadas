-- =============================================================================
-- SIMULACION 07 - CASO AVANZADO (bloqueo de recurso por penalizaciones)
-- =============================================================================
-- Que demuestra:
--   Si los puntos acumulados superan PUNTAJE_BLOQUEO_RECURSO (75),
--   el recurso pasa a "Fuera de servicio".
--
-- Usamos un recurso disponible y le cargamos penalizaciones manuales
-- (50 + 30 = 80 puntos >= 75).
-- =============================================================================

DELETE FROM Asignacion;
DELETE FROM Penalizacion;
DELETE FROM Incidente;
DELETE FROM Evento;
DELETE FROM Log;

UPDATE Recurso SET fk_estado_recurso_id = 1 WHERE fk_estado_recurso_id <> 1;


-- Elegir un recurso disponible (el primero del dataset)

SELECT
    r.id_recurso,
    tr.nombre AS tipo_recurso,
    er.nombre AS estado
FROM Recurso r
JOIN EstadoRecurso er ON r.fk_estado_recurso_id = er.id_estado_recurso
JOIN TipoRecurso tr ON r.fk_tipo_recurso_id = tr.id_tipo_recurso
WHERE er.nombre = 'Disponible'
ORDER BY r.id_recurso
LIMIT 1;


-- Penalizaciones que superan el umbral (tipo 6 = 50 pts, tipo 4 = 30 pts)

INSERT INTO Penalizacion (fk_recurso_id, fk_tipo_penalizacion_id, motivo)
SELECT
    r.id_recurso,
    6,
    'SIM-07 penalizacion acumulada 1'
FROM Recurso r
JOIN EstadoRecurso er ON r.fk_estado_recurso_id = er.id_estado_recurso
WHERE er.nombre = 'Disponible'
ORDER BY r.id_recurso
LIMIT 1;

INSERT INTO Penalizacion (fk_recurso_id, fk_tipo_penalizacion_id, motivo)
SELECT
    p.fk_recurso_id,
    4,
    'SIM-07 penalizacion acumulada 2'
FROM Penalizacion p
WHERE p.motivo = 'SIM-07 penalizacion acumulada 1';


-- Estado del recurso (esperado: Fuera de servicio)

SELECT
    r.id_recurso,
    tr.nombre AS tipo_recurso,
    er.nombre AS estado_recurso
FROM Recurso r
JOIN EstadoRecurso er ON r.fk_estado_recurso_id = er.id_estado_recurso
JOIN TipoRecurso tr ON r.fk_tipo_recurso_id = tr.id_tipo_recurso
WHERE r.id_recurso IN (
    SELECT fk_recurso_id FROM Penalizacion WHERE motivo LIKE 'SIM-07%'
);


-- Puntos acumulados segun la vista

SELECT *
FROM vRecursosPenalizados
WHERE id_recurso IN (
    SELECT fk_recurso_id FROM Penalizacion WHERE motivo LIKE 'SIM-07%'
);
