-- ============================================================================
-- SMART CITY - SCRIPT DE MIGRACIÓN NATIVO EN CASCADA
-- ============================================================================
-- Este script orquesta la creación completa de la base de datos, la estructura
-- de tablas (DDL) y la carga del dataset inicial (DML) en un solo flujo.
--
-- Para ejecutar este script desde la raíz del proyecto usando PSQL:
--
-- == POWERSHELL COMMAND ==
-- $env:PGPASSWORD="password"; psql -h localhost -U postgres -f migrate.sql
--
-- == CMD COMMAND ==
-- set PGPASSWORD=password && psql -h localhost -U postgres -f migrate.sql
-- ============================================================================

-- 1. Crear/recrear la base de datos objetivo.
\ir database/create-database.sql

-- 2. Conexión a la nueva base de datos 'smart_city' ya creada.
\c smart_city

-- 3. Ejecución secuencial de la estructura de tablas (DDL).
\ir database/create-tables.sql

-- 4. Carga de datos inicial (DML) de catálogos y registros operativos.
\ir database/carga-dataset.sql

-- 5. Vistas de monitoreo.
\ir database/create-views.sql

-- 6. Reglas activas cargadas desde el master script.
\ir database/create-triggers.sql

-- 7. Procedimientos almacenados adicionales.
\ir database/store-procedures/asignar-recurso.sql
\ir database/store-procedures/cerrar-incidente.sql
\ir database/store-procedures/simular-eventos.sql
