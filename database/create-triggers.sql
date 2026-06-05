-- ============================================================================
-- SMART CITY - MASTER TRIGGER LOADER
-- ============================================================================
-- Este script orquesta la carga secuencial de todas las reglas activas (triggers)
-- y validaciones del sistema.
--
-- Para ser cargado desde migrate.sql o scripts de inicialización.
-- ============================================================================

-- 1. Reglas validadoras (BEFORE INSERT/UPDATE - validaciones)
\ir triggers/reglas-validadoras.sql

-- 2. Reglas de inteligencia (auditoría, cálculo de puntaje, rebalanceo, etc.)
\ir triggers/reglas-inteligencia.sql

-- 3. Reglas de automatización (motor de asignación y ciclo operativo)
\ir triggers/reglas-automatizacion.sql

-- 4. Reglas temporales (procedimientos para SLA y reactivación)
\ir triggers/reglas-temporales.sql

-- 5. Reglas de auditoría y control (monitoreo y capacidad global)
\ir triggers/reglas-auditoriaYcontrol.sql
