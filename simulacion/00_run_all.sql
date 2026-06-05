\set ON_ERROR_STOP on
\set sim_verbose on
\pset pager off
\timing on

\echo '============================================================'
\echo ' SMART CITY - SIMULACION PROFESIONAL TRANSACCIONAL'
\echo '============================================================'

BEGIN;

\ir lib/harness.sql

\ir 01_preflight.sql
\ir 02_asignacion_inteligencia.sql
\ir 03_ciclo_vida.sql
\ir 04_validaciones.sql
\ir 05_sensores_iot.sql
\ir 06_saturacion_rebalanceo.sql
\ir 07_capacidades_avanzadas.sql
\ir 08_simulacion_20_incidentes.sql
\ir 09_reporte_operativo.sql

-- Las secuencias no son transaccionales en PostgreSQL: restaurarlas antes del rollback.
SELECT pg_temp.sim_restaurar_secuencias();

SELECT (count(*) FILTER (WHERE estado = 'FAIL') > 0)::int AS sim_tiene_fallos
FROM sim_resultado
\gset

ROLLBACK;

\if :sim_tiene_fallos
    \echo 'SIMULACION FINALIZADA CON FALLOS INESPERADOS'
\else
    \echo 'SIMULACION BASE INICIALIZADA Y REVERTIDA CORRECTAMENTE'
\endif
