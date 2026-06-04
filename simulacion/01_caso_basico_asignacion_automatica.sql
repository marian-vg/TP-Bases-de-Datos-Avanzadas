-- =============================================================================
-- SIMULACION 01 - CASO BASICO
-- =============================================================================
-- Que demuestra (casos basicos - asignacion):
--   Al insertar un incidente en "Pendiente", los triggers deben:
--     1) crear una asignacion automatica
--     2) cambiar el incidente a "En proceso"
--     3) cambiar el recurso a "En transito" (hasta registrar la llegada)
--   Ver tambien: 02_caso_basico_cambio_estados.sql
--
-- Como correrlo (desde la raiz del proyecto, con la base ya cargada):
--   psql -h localhost -p 5433 -U postgres -d smart_city
--   \i simulacion/01_caso_basico_asignacion_automatica.sql
--
-- O pegar este archivo en pgAdmin / DBeaver y ejecutarlo entero.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- PASO 0: dejar el entorno limpio para la prueba
-- -----------------------------------------------------------------------------
DELETE FROM Asignacion;
DELETE FROM Penalizacion;
DELETE FROM Incidente;
DELETE FROM Evento;
DELETE FROM Log;

UPDATE Recurso
SET fk_estado_recurso_id = 1
WHERE fk_estado_recurso_id <> 1;


-- -----------------------------------------------------------------------------
-- PASO 1: consultas ANTES de simular (solo lectura)
-- -----------------------------------------------------------------------------
-- Recursos disponibles en zona 1 que sirven para "Emergencia medica" (tipo 4):

SELECT
    r.id_recurso,
    tr.nombre AS tipo_recurso,
    er.nombre AS estado
FROM Recurso r
JOIN EstadoRecurso er ON r.fk_estado_recurso_id = er.id_estado_recurso
JOIN TipoRecurso tr ON r.fk_tipo_recurso_id = tr.id_tipo_recurso
JOIN ZonaRecurso zr ON zr.id_recurso = r.id_recurso AND zr.id_zona = 1
JOIN TipoIncidenteTipoRecurso titr
  ON titr.fk_tipo_recurso_id = r.fk_tipo_recurso_id
 AND titr.fk_tipo_incidente_id = 4
WHERE er.nombre = 'Disponible'
ORDER BY r.id_recurso;

-- Incidentes activos antes de la simulacion (deberia dar 0):

SELECT COUNT(*) AS incidentes_activos_antes
FROM vIncidentesActivos;


-- -----------------------------------------------------------------------------
-- PASO 2: simular el evento (INSERT del incidente)
-- -----------------------------------------------------------------------------
-- Valores del dataset:
--   tipo 4  = Emergencia medica
--   gravedad 1 = Baja (pide 1 solo recurso)
--   estado 1 = Pendiente
--   zona 1
-- La descripcion 'SIM-01' nos sirve despues para buscar este incidente.

INSERT INTO Incidente (
    fk_tipo_incidente_id,
    fk_gravedad_id,
    fk_estado_incidente_id,
    fk_zona_id,
    descripcion,
    prioridad
)
VALUES (
    4,
    1,
    1,
    1,
    'SIM-01 emergencia medica',
    1
);


-- -----------------------------------------------------------------------------
-- PASO 3: consultas DESPUES (verificar que los triggers actuaron)
-- -----------------------------------------------------------------------------

-- 3a) El incidente deberia estar "En proceso":

SELECT
    i.id_incidente,
    ti.nombre AS tipo_incidente,
    g.nombre AS gravedad,
    ei.nombre AS estado_incidente,
    z.nombre AS zona
FROM Incidente i
JOIN TipoIncidente ti ON i.fk_tipo_incidente_id = ti.id_tipo_incidente
JOIN Gravedad g ON i.fk_gravedad_id = g.id_gravedad
JOIN EstadoIncidente ei ON i.fk_estado_incidente_id = ei.id_estado_incidente
JOIN Zona z ON i.fk_zona_id = z.id_zona
WHERE i.descripcion = 'SIM-01 emergencia medica';


-- 3b) Deberia existir 1 asignacion y el recurso en "En transito":

SELECT
    a.id_asignacion,
    a.fk_recurso_id,
    tr.nombre AS tipo_recurso,
    er.nombre AS estado_recurso
FROM Asignacion a
JOIN Incidente i ON a.fk_incidente_id = i.id_incidente
JOIN Recurso r ON a.fk_recurso_id = r.id_recurso
JOIN TipoRecurso tr ON r.fk_tipo_recurso_id = tr.id_tipo_recurso
JOIN EstadoRecurso er ON r.fk_estado_recurso_id = er.id_estado_recurso
WHERE i.descripcion = 'SIM-01 emergencia medica';


-- 3c) Vista de incidentes activos del TP:

SELECT *
FROM vIncidentesActivos
WHERE descripcion = 'SIM-01 emergencia medica';
