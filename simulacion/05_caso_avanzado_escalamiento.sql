-- =============================================================================
-- SIMULACION 05 - CASO AVANZADO (escalamiento automatico por SLA)
-- =============================================================================
-- Que demuestra:
--   Un incidente "En proceso" cuyo tiempo supera el SLA pasa a "Escalado"
--   al ejecutar el procedimiento sp_escalar_incidente().
--
-- SLA gravedad Alta (id 3) = 10 minutos de respuesta.
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
VALUES (1, 3, 1, 1, 'SIM-05 escalamiento SLA', 3);


-- Estado tras la asignacion automatica

SELECT
    i.descripcion,
    g.nombre AS gravedad,
    ei.nombre AS estado_incidente,
    sla.tiempo_respuesta_minutos AS sla_minutos
FROM Incidente i
JOIN Gravedad g ON i.fk_gravedad_id = g.id_gravedad
JOIN EstadoIncidente ei ON i.fk_estado_incidente_id = ei.id_estado_incidente
JOIN SLA sla ON sla.fk_gravedad_id = g.id_gravedad
WHERE i.descripcion = 'SIM-05 escalamiento SLA';


-- Simular que el incidente lleva mas de 10 minutos abierto

UPDATE Incidente
SET fecha_hora_registro = CURRENT_TIMESTAMP - INTERVAL '20 minutes'
WHERE descripcion = 'SIM-05 escalamiento SLA';


-- Ejecutar control de SLA (procedimiento del motor activo)

CALL sp_escalar_incidente();


-- Resultado esperado: estado "Escalado" y prioridad incrementada

SELECT
    i.descripcion,
    ei.nombre AS estado_incidente,
    i.prioridad,
    ROUND(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - i.fecha_hora_registro)) / 60) AS minutos_transcurridos
FROM Incidente i
JOIN EstadoIncidente ei ON i.fk_estado_incidente_id = ei.id_estado_incidente
WHERE i.descripcion = 'SIM-05 escalamiento SLA';
