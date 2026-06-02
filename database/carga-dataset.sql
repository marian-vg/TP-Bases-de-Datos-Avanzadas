-- ============================================================================
-- SMART CITY - SCRIPT DE CARGA DE DATOS (DATASET)
-- ============================================================================
-- Este script realiza la limpieza previa de todas las tablas operativas y de
-- catálogos para evitar duplicados, y utiliza el comando client-side \copy
-- siguiendo la sintaxis estándar moderna de PostgreSQL y mapeo explícito de columnas.
--
-- Para ejecutar este script desde la raíz del proyecto:
-- == POWERSHELL COMMAND ==
-- $env:PGPASSWORD="password"; psql -h localhost -U postgres -d db_name -f
-- database/carga-dataset.sql
--
-- == CMD COMMAND ==
-- set PGPASSWORD=password && psql -h localhost -U postgres -d db_name -f
-- database/carga-dataset.sql
--
-- ============================================================================

-- 1. LIMPIEZA DE TABLAS EXISTENTES (Orden correcto respetando claves foráneas)
-- BEGIN;

-- TRUNCATE TABLE 
--     Asignacion, 
--     Penalizacion, 
--     Log, 
--     ZonaRecurso, 
--     Recurso, 
--     Sensor, 
--     Evento, 
--     Incidente, 
--     SLA, 
--     Zona, 
--     TipoIncidente, 
--     EstadoIncidente, 
--     Gravedad, 
--     NivelRiesgo, 
--     TipoSensor, 
--     TipoEvento, 
--     TipoRecurso, 
--     EstadoRecurso, 
--     TipoPenalizacion, 
--     ParametrosSistema 
-- RESTART IDENTITY CASCADE;

-- COMMIT;

-- 2. CARGA DE CATÁLOGOS E INFORMACIÓN OPERATIVA BASE
\encoding UTF8

-- 01. Tipo de Incidente
\copy TipoIncidente (id_tipo_incidente, nombre, descripcion) FROM 'data/01_tipo_incidente.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

-- 02. Estado de Incidente
\copy EstadoIncidente (id_estado_incidente, nombre) FROM 'data/02_estado_incidente.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

-- 03. Gravedad de Incidente
\copy Gravedad (id_gravedad, nombre) FROM 'data/03_gravedad.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

-- 04. SLA (Acuerdos de Nivel de Servicio)
\copy SLA (id_sla, fk_gravedad_id, tiempo_respuesta_minutos) FROM 'data/04_sla.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

-- 05. Nivel de Riesgo
\copy NivelRiesgo (id_nivel_riesgo, nombre, valor) FROM 'data/05_nivel_riesgo.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

-- 06. Zona Geográfica
\copy Zona (id_zona, nombre, fk_nivel_riesgo_id) FROM 'data/06_zona.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

-- 07. Tipo de Sensor
\copy TipoSensor (id_tipo_sensor, nombre) FROM 'data/07_tipo_sensor.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

-- 08. Tipo de Evento
\copy TipoEvento (id_tipo_evento, nombre, descripcion) FROM 'data/08_tipo_evento.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

-- 09. Tipo de Recurso (Equipos de emergencia)
\copy TipoRecurso (id_tipo_recurso, nombre, descripcion) FROM 'data/09_tipo_recurso.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

-- 10. Estado de Recurso
\copy EstadoRecurso (id_estado_recurso, nombre) FROM 'data/10_estado_recurso.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

-- 11. Tipo de Penalización
\copy TipoPenalizacion (id_tipo_penalizacion, nombre, puntaje) FROM 'data/11_tipo_penalizacion.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

-- 12. Sensor (Dispositivos IoT). Las fechas (instalación y mantenimiento) NO provienen del CSV:
--     se generan más abajo, relativas a CURRENT_DATE, para que el dataset no caduque con el tiempo.
\copy Sensor (id_sensor, fk_tipo_sensor_id, fk_zona_id, marca, modelo, nombre) FROM 'data/12_sensor.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',', NULL '');

-- 13. Recurso Operativo
\copy Recurso (id_recurso, fk_tipo_recurso_id, fk_zona_base_id, fk_estado_recurso_id) FROM 'data/13_recurso.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

-- 14. Zona Habilitada por Recurso (Relación M:N)
\copy ZonaRecurso (id_zona, id_recurso) FROM 'data/14_zona_recurso.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

-- 15. Parámetros Globales del Sistema
\copy ParametrosSistema (nombre_parametro, numero) FROM 'data/15_parametros_sistema.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

-- 16. Tipos de recurso aplicables por tipo de incidente (M:N para asignación correcta)
\copy TipoIncidenteTipoRecurso (fk_tipo_incidente_id, fk_tipo_recurso_id) FROM 'data/16_tipo_incidente_tipo_recurso.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

-- ============================================================================
-- 3. FECHAS DE SENSORES RELATIVAS A HOY (generadas, no provienen del CSV)
-- ============================================================================
-- Las fechas se generan relativas a CURRENT_DATE para que la confianza de los
-- sensores (R21) no caduque con el paso del tiempo. El setseed() fijo mantiene
-- el dataset reproducible para todo el equipo (misma base en cada carga).
SELECT setseed(0.42);

-- Instalación: en algún momento dentro de los últimos ~5 años.
UPDATE Sensor SET fecha_instalado = CURRENT_DATE - (random() * 1825)::int;

-- ~40% de los sensores tiene al menos un mantenimiento, dentro de las últimas ~12
-- semanas (GREATEST evita que sea anterior a la instalación). Así siempre hay
-- sensores de alta confianza capaces de generar incidentes.
INSERT INTO MantenimientoSensor (fk_sensor_id, fecha)
SELECT id_sensor, GREATEST(fecha_instalado, CURRENT_DATE - (random() * 84)::int)
FROM Sensor
WHERE random() < 0.4
ORDER BY id_sensor;