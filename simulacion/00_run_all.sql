\set ON_ERROR_STOP on
\pset pager off
\timing on

\echo '============================================================'
\echo ' SMART CITY - SIMULACION PROFESIONAL TRANSACCIONAL'
\echo '============================================================'

BEGIN;

\ir lib/harness.sql

-- Los escenarios y el reporte se incorporan en los siguientes bloques.

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
