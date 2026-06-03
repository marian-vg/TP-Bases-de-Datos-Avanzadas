-- =============================================================================
-- SIMULACION 02 - CASO BASICO (cambio de estados)
-- =============================================================================
-- Que demuestra:
--   Tras la asignacion automatica, al actualizar la asignacion:
--     1) timestamp_llegada  -> recurso pasa a "Ocupado"
--     2) cierre exitoso     -> recurso "Disponible" e incidente "Resuelto"
-- =============================================================================

DELETE FROM Asignacion;
DELETE FROM Penalizacion;
DELETE FROM Incidente;
DELETE FROM Evento;
DELETE FROM Log;

UPDATE Recurso SET fk_estado_recurso_id = 1 WHERE fk_estado_recurso_id <> 1;


-- Crear incidente (mismo criterio que SIM-01)

INSERT INTO Incidente (
    fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id,
    fk_zona_id, descripcion, prioridad
)
VALUES (4, 1, 1, 1, 'SIM-02 emergencia medica', 1);


-- Estado despues del INSERT (esperado: incidente En proceso, recurso En transito)

SELECT
    i.descripcion,
    ei.nombre AS estado_incidente,
    er.nombre AS estado_recurso
FROM Incidente i
JOIN EstadoIncidente ei ON i.fk_estado_incidente_id = ei.id_estado_incidente
JOIN Asignacion a ON a.fk_incidente_id = i.id_incidente AND a.timestamp_finalizacion IS NULL
JOIN Recurso r ON a.fk_recurso_id = r.id_recurso
JOIN EstadoRecurso er ON r.fk_estado_recurso_id = er.id_estado_recurso
WHERE i.descripcion = 'SIM-02 emergencia medica';


-- Simular llegada al lugar

UPDATE Asignacion
SET timestamp_llegada = CURRENT_TIMESTAMP
WHERE fk_incidente_id = (
    SELECT id_incidente FROM Incidente WHERE descripcion = 'SIM-02 emergencia medica'
)
AND timestamp_llegada IS NULL;


-- Estado tras la llegada (esperado: recurso Ocupado)

SELECT
    i.descripcion,
    ei.nombre AS estado_incidente,
    er.nombre AS estado_recurso
FROM Incidente i
JOIN EstadoIncidente ei ON i.fk_estado_incidente_id = ei.id_estado_incidente
JOIN Asignacion a ON a.fk_incidente_id = i.id_incidente
JOIN Recurso r ON a.fk_recurso_id = r.id_recurso
JOIN EstadoRecurso er ON r.fk_estado_recurso_id = er.id_estado_recurso
WHERE i.descripcion = 'SIM-02 emergencia medica';


-- Simular cierre exitoso de la intervencion

UPDATE Asignacion
SET estado_exito = TRUE,
    timestamp_finalizacion = CURRENT_TIMESTAMP
WHERE fk_incidente_id = (
    SELECT id_incidente FROM Incidente WHERE descripcion = 'SIM-02 emergencia medica'
);


-- Estado final (esperado: incidente Resuelto, recurso Disponible)

SELECT
    i.descripcion,
    ei.nombre AS estado_incidente,
    er.nombre AS estado_recurso
FROM Incidente i
JOIN EstadoIncidente ei ON i.fk_estado_incidente_id = ei.id_estado_incidente
LEFT JOIN Asignacion a ON a.fk_incidente_id = i.id_incidente
LEFT JOIN Recurso r ON a.fk_recurso_id = r.id_recurso
LEFT JOIN EstadoRecurso er ON r.fk_estado_recurso_id = er.id_estado_recurso
WHERE i.descripcion = 'SIM-02 emergencia medica';
