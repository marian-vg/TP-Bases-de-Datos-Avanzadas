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

-- 6. Reglas activas, en módulos. ORDEN IMPORTANTE:
--    a) reglas-validadoras  -> validaciones BEFORE (R8/R9/R10/R11 + tipo aplicable).
--    b) reglas-inteligencia  -> mantiene Recurso.puntaje (R14). DEBE cargarse antes del motor.
--    c) reglas-automatizacion -> motor de asignación y ciclo operativo (R1/R2/R3/R5/R7/R8/R9/R14/R21);
--                                el motor ordena por el puntaje que mantiene (b).
--    d) reglas-temporales    -> reglas temporales R16/R17 (procedures para cron/manual).
--
--    NOTA: database/create-triggers.sql NO se carga a propósito. Es un script de REFERENCIA
--    generado con IA que no respeta las reglas del proyecto; se conserva solo a mano. Las reglas
--    que vivían ahí ya están en módulos (R12/R13/R15 en inteligencia, R20 en automatizacion).
\ir database/triggers/reglas-validadoras.sql
\ir database/triggers/reglas-inteligencia.sql
\ir database/triggers/reglas-automatizacion.sql
\ir database/triggers/reglas-temporales.sql

-- 7. Procedimientos almacenados adicionales.
\ir database/store-procedures/asignar-recurso.sql
