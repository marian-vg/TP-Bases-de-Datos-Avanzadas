\set ON_ERROR_STOP on
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
\ir 07_brechas_conocidas.sql
\ir 08_simulacion_20_incidentes.sql

SELECT (count(*) FILTER (WHERE estado = 'FAIL') > 0)::int AS sim_tiene_fallos
FROM sim_resultado
\gset

ROLLBACK;

\if :sim_tiene_fallos
    \echo 'SIMULACION FINALIZADA CON FALLOS INESPERADOS'
    \quit 1
\else
    \echo 'SIMULACION BASE INICIALIZADA Y REVERTIDA CORRECTAMENTE'
\endif
