\set ON_ERROR_STOP on
\set QUIET on
\pset pager off
\pset border 2
\pset linestyle unicode
\pset null ''
\timing off

-- Runner resumido para informes/defensa.
-- Ejecuta los mismos escenarios que 00_run_all.sql, pero silencia la salida
-- intermedia y muestra solo un resumen compacto en consola. Si se pasa
-- -v sim_log=<archivo>, deja el detalle completo de aserciones en ese archivo.

\o /dev/null
BEGIN;
SET LOCAL client_min_messages TO warning;

\ir lib/harness.sql
\ir 01_preflight.sql
\ir 02_asignacion_inteligencia.sql
\ir 03_ciclo_vida.sql
\ir 04_validaciones.sql
\ir 05_sensores_iot.sql
\ir 06_saturacion_rebalanceo.sql
\ir 07_capacidades_avanzadas.sql
\ir 08_simulacion_20_incidentes.sql


CREATE TEMP TABLE sim_mapa_cobertura (
    codigo TEXT PRIMARY KEY,
    patron TEXT NOT NULL
) ON COMMIT DROP;

INSERT INTO sim_mapa_cobertura (codigo, patron)
VALUES
    ('R1',  'R1/R5 cantidad por gravedad'),
    ('R2',  'R2 estado En proceso'),
    ('R3',  'R3 auditoria de cierre'),
    ('R4',  'R4 reasignacion por falla'),
    ('R5',  'R1/R5 cantidad por gravedad'),
    ('R6',  'R6 incidente relacionado'),
    ('R7',  'R7 cierre automatico'),
    ('R8',  'R8 recursos En transito'),
    ('R9',  'R9 transicion invalida'),
    ('R10', 'R10 zona habilitada'),
    ('R11', 'R11 duplicados'),
    ('R12', 'R12/R13 prioridad'),
    ('R13', 'R12/R13 prioridad'),
    ('R14', 'R14 mejor recurso'),
    ('R15', 'R15 asignacion global'),
    ('R16', 'R16 escalamiento por SLA'),
    ('R17', 'R17 reactivacion temporal'),
    ('R18', 'R18 log de rebalanceo'),
    ('R19', 'R3 auditoria de cierre'),
    ('R20', 'R20 capacidad por zona'),
    ('R21', 'R21 promocion confiable');

UPDATE sim_cobertura c
SET estado = r.estado,
    detalle = r.detalle
FROM sim_mapa_cobertura m
CROSS JOIN LATERAL (
    SELECT sr.estado, sr.detalle
    FROM sim_resultado sr
    WHERE sr.prueba = m.patron
    ORDER BY CASE sr.estado WHEN 'FAIL' THEN 1 WHEN 'PASS' THEN 2 ELSE 3 END, sr.orden
    LIMIT 1
) r
WHERE c.codigo = m.codigo;

UPDATE sim_cobertura
SET estado = 'PASS',
    detalle = r.detalle
FROM sim_resultado r
WHERE codigo = 'P1'
  AND r.prueba = 'P1 asignacion diferida'
  AND r.estado = 'PASS';

UPDATE sim_cobertura c
SET estado = r.estado,
    detalle = r.detalle
FROM (VALUES
    ('P2', 'P2 incremento de gravedad'),
    ('P3', 'P3 cierre de incidente'),
    ('P4', 'P4 penalizacion proporcional'),
    ('P5', 'P5 simulacion de eventos')
) AS m(codigo, prueba)
CROSS JOIN LATERAL (
    SELECT sr.estado, sr.detalle
    FROM sim_resultado sr
    WHERE sr.prueba = m.prueba
    ORDER BY CASE sr.estado WHEN 'FAIL' THEN 1 WHEN 'PASS' THEN 2 ELSE 3 END, sr.orden
    LIMIT 1
) r
WHERE c.codigo = m.codigo;

\o

\echo '============================================================'
\echo ' SMART CITY - RESUMEN DE SIMULACION'
\echo '============================================================'
\echo ''

WITH segmentos(test_ejecutado, prueba, orden_segmento) AS (
    VALUES
        ('01-PREFLIGHT', 'Preflight de dataset, vistas y objetos instalados', 1),
        ('02-ASIGNACION', 'Asignacion automatica e inteligencia de seleccion', 2),
        ('03-CICLO', 'Ciclo de vida operativo y reasignacion por falla', 3),
        ('04-VALIDACIONES', 'Validaciones de integridad y reglas validadoras', 4),
        ('05-IOT', 'Sensores IoT y promocion de eventos', 5),
        ('06-SATURACION', 'Saturacion, rebalanceo y capacidad por zona', 6),
        ('07-AVANZADAS', 'SLA, temporales, arribo y penalizacion proporcional', 7),
        ('08-LOTE20', 'Rafaga deterministica de veinte incidentes', 8)
), resumen AS (
    SELECT
        r.escenario AS test_ejecutado,
        CASE
            WHEN count(*) FILTER (WHERE r.estado = 'FAIL') > 0 THEN 'FAIL'
            WHEN count(*) FILTER (WHERE r.estado = 'SKIP') > 0 THEN 'SKIP'
            ELSE 'PASS'
        END AS resultado,
        string_agg(
            CASE
                WHEN r.estado <> 'PASS' THEN r.prueba || ': ' || r.detalle
                ELSE NULL
            END,
            E'\n' ORDER BY r.orden
        ) AS observaciones
    FROM sim_resultado r
    GROUP BY r.escenario
)
SELECT
    s.test_ejecutado,
    s.prueba,
    COALESCE(r.resultado, 'SKIP') AS resultado,
    CASE
        WHEN length(COALESCE(r.observaciones, '')) > 180 THEN left(r.observaciones, 177) || '...'
        ELSE COALESCE(r.observaciones, '')
    END AS observaciones
FROM segmentos s
LEFT JOIN resumen r ON r.test_ejecutado = s.test_ejecutado
ORDER BY s.orden_segmento;

SELECT CASE
    WHEN EXISTS (SELECT 1 FROM sim_resultado WHERE estado = 'FAIL')
        THEN 'FAIL - EXISTEN FALLOS INESPERADOS'
    WHEN EXISTS (SELECT 1 FROM sim_resultado WHERE estado = 'SKIP')
        THEN 'PASS CON PRUEBAS OMITIDAS'
    ELSE 'PASS'
END AS sim_resultado_general
FROM sim_resultado
LIMIT 1
\gset

\echo ''
\echo 'Resultado general: ' :sim_resultado_general

\if :{?sim_log}
\o :sim_log
\qecho '============================================================'
\qecho ' SMART CITY - DETALLE DE SIMULACION'
\qecho '============================================================'
\qecho ''
\qecho '--- RESULTADO GENERAL ---'
SELECT CASE
    WHEN EXISTS (SELECT 1 FROM sim_resultado WHERE estado = 'FAIL')
        THEN 'FAIL - EXISTEN FALLOS INESPERADOS'
    WHEN EXISTS (SELECT 1 FROM sim_resultado WHERE estado = 'SKIP')
        THEN 'PASS CON PRUEBAS OMITIDAS'
    ELSE 'PASS'
END AS veredicto;

\qecho ''
\qecho '--- RESUMEN POR ESTADO ---'
SELECT estado, count(*) AS cantidad
FROM sim_resultado
GROUP BY estado
ORDER BY CASE estado
    WHEN 'FAIL' THEN 1 WHEN 'SKIP' THEN 2
    WHEN 'PASS' THEN 3 ELSE 4 END;

\qecho ''
\qecho '--- MATRIZ DE COBERTURA R1-R21 / P1-P5 ---'
SELECT
    codigo,
    nombre,
    COALESCE(objeto_instalado::text, 'n/a') AS instalado,
    estado,
    detalle
FROM sim_cobertura
ORDER BY
    CASE WHEN codigo LIKE 'R%' THEN 1 ELSE 2 END,
    substring(codigo FROM 2)::int;

\qecho ''
\qecho '--- METRICAS ---'
SELECT escenario, metrica, valor, COALESCE(detalle, '') AS detalle
FROM sim_metrica
ORDER BY orden;

\qecho ''
\qecho '--- DETALLE COMPLETO DE ASERCIONES ---'
SELECT escenario, prueba, estado, detalle
FROM sim_resultado
ORDER BY orden;
\o
\echo ''
\echo 'Detalle escrito en: ' :sim_log
\endif

\o /dev/null
SELECT pg_temp.sim_restaurar_secuencias();
SELECT (count(*) FILTER (WHERE estado = 'FAIL') > 0)::int AS sim_tiene_fallos
FROM sim_resultado
\gset
ROLLBACK;
\o

\if :sim_tiene_fallos
    \echo 'SIMULACION FINALIZADA CON FALLOS INESPERADOS'
\else
    \echo 'SIMULACION BASE INICIALIZADA Y REVERTIDA CORRECTAMENTE'
\endif
