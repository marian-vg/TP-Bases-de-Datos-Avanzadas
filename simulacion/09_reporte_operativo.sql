\if :{?sim_verbose}
\echo '>>> 09 - REPORTE OPERATIVO'
\endif

\pset border 2
\pset linestyle unicode

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

\echo ''
\echo '============================================================'
\echo ' VEREDICTO GENERAL'
\echo '============================================================'

SELECT CASE
    WHEN EXISTS (SELECT 1 FROM sim_resultado WHERE estado = 'FAIL')
        THEN 'FAIL - EXISTEN FALLOS INESPERADOS'
    WHEN EXISTS (SELECT 1 FROM sim_resultado WHERE estado = 'SKIP')
        THEN 'PASS CON PRUEBAS OMITIDAS'
    ELSE 'PASS'
END AS veredicto;

\echo ''
\echo '--- TABLERO EJECUTIVO ---'
SELECT
    (SELECT count(*) FROM sim_resultado) AS pruebas_registradas,
    (SELECT count(*) FROM sim_resultado WHERE estado = 'PASS') AS aprobadas,
    (SELECT count(*) FROM sim_resultado WHERE estado = 'FAIL') AS fallos,
    (SELECT count(*) FROM sim_resultado WHERE estado = 'SKIP') AS pruebas_omitidas,
    (SELECT count(*) FROM sim_cobertura WHERE estado = 'PASS') AS capacidades_validadas,
    (SELECT count(*) FROM Log WHERE operacion = 'DECISION') AS decisiones_automaticas,
    (SELECT count(*) FROM sim_lote_20) AS incidentes_en_rafaga;

\echo ''
\echo '--- RESUMEN DE ASERCIONES ---'
SELECT estado, count(*) AS cantidad
FROM sim_resultado
GROUP BY estado
ORDER BY CASE estado
    WHEN 'FAIL' THEN 1 WHEN 'SKIP' THEN 2
    WHEN 'PASS' THEN 3 ELSE 4 END;

\echo ''
\echo '--- MATRIZ DE COBERTURA R1-R21 / P1-P5 ---'
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

\echo ''
\echo '--- METRICAS RECOLECTADAS ---'
SELECT escenario, metrica, valor, COALESCE(detalle, '') AS detalle
FROM sim_metrica
ORDER BY orden;

\echo ''
\echo '--- ESTADO FINAL DEL LOTE DE 20 ---'
SELECT
    ei.nombre AS estado,
    count(*) AS incidentes
FROM sim_lote_20 l
JOIN Incidente i ON i.id_incidente = l.id_incidente
JOIN EstadoIncidente ei ON ei.id_estado_incidente = i.fk_estado_incidente_id
GROUP BY ei.nombre
ORDER BY incidentes DESC, ei.nombre;

\echo ''
\echo '--- DISTRIBUCION POR GRAVEDAD Y RIESGO ---'
SELECT
    g.nombre AS gravedad,
    nr.nombre AS riesgo_zona,
    count(*) AS incidentes
FROM sim_lote_20 l
JOIN Incidente i ON i.id_incidente = l.id_incidente
JOIN Gravedad g ON g.id_gravedad = i.fk_gravedad_id
JOIN Zona z ON z.id_zona = i.fk_zona_id
JOIN NivelRiesgo nr ON nr.id_nivel_riesgo = z.fk_nivel_riesgo_id
GROUP BY g.nombre, nr.nombre
ORDER BY min(g.id_gravedad), min(nr.valor);

\echo ''
\echo '--- RESPUESTA Y SLA DEL LOTE ---'
SELECT
    count(*) FILTER (WHERE a.timestamp_llegada IS NOT NULL) AS llegadas_registradas,
    count(*) FILTER (
        WHERE a.timestamp_llegada IS NOT NULL
          AND a.timestamp_llegada - a.timestamp_asignacion
              <= sla.tiempo_respuesta_minutos * INTERVAL '1 minute'
    ) AS dentro_sla,
    count(*) FILTER (
        WHERE a.timestamp_llegada IS NOT NULL
          AND a.timestamp_llegada - a.timestamp_asignacion
              > sla.tiempo_respuesta_minutos * INTERVAL '1 minute'
    ) AS fuera_sla
FROM sim_lote_20 l
JOIN Incidente i ON i.id_incidente = l.id_incidente
JOIN SLA sla ON sla.fk_gravedad_id = i.fk_gravedad_id
JOIN Asignacion a ON a.fk_incidente_id = i.id_incidente;

\echo ''
\echo '--- TOP 10 RECURSOS UTILIZADOS ---'
SELECT
    r.id_recurso,
    tr.nombre AS tipo_recurso,
    r.puntaje,
    count(a.id_asignacion) AS intervenciones,
    count(*) FILTER (WHERE a.estado_exito = TRUE) AS exitos,
    count(*) FILTER (WHERE a.estado_exito = FALSE) AS fallas
FROM Recurso r
JOIN TipoRecurso tr ON tr.id_tipo_recurso = r.fk_tipo_recurso_id
JOIN Asignacion a ON a.fk_recurso_id = r.id_recurso
JOIN sim_lote_20 l ON l.id_incidente = a.fk_incidente_id
GROUP BY r.id_recurso, tr.nombre, r.puntaje
ORDER BY intervenciones DESC, r.puntaje DESC, r.id_recurso
LIMIT 10;

\echo ''
\echo '--- PENALIZACIONES OBSERVADAS EN EL LOTE FINAL ---'
SELECT
    p.id_penalizacion,
    p.fk_recurso_id AS recurso,
    tp.nombre AS tipo,
    COALESCE(p.puntaje, tp.puntaje) AS puntos,
    p.motivo
FROM Penalizacion p
JOIN TipoPenalizacion tp ON tp.id_tipo_penalizacion = p.fk_tipo_penalizacion_id
ORDER BY p.id_penalizacion;

\echo ''
\echo '--- DECISIONES AUTOMATICAS OBSERVADAS EN EL LOTE FINAL ---'
SELECT
    trigger_disparador AS regla,
    tablaAfectada AS entidad,
    idTablaAfectada AS id_entidad,
    detalle->>'motivo' AS motivo
FROM Log
WHERE operacion = 'DECISION'
ORDER BY timestamp, id_log;

\echo ''
\echo '--- AUDITORIA DEL LOTE ---'
SELECT
    COALESCE(trigger_disparador, '(manual)') AS origen,
    operacion,
    count(*) AS ejecuciones
FROM Log
GROUP BY trigger_disparador, operacion
ORDER BY ejecuciones DESC, origen
LIMIT 15;

\echo ''
\echo '--- OBSERVACIONES Y PRUEBAS NO EXITOSAS ---'
SELECT escenario, prueba, estado, detalle
FROM sim_resultado
WHERE estado IN ('FAIL', 'SKIP')
ORDER BY CASE estado WHEN 'FAIL' THEN 1 WHEN 'SKIP' THEN 2 ELSE 3 END, orden;

\echo ''
\echo '--- DETALLE COMPLETO DE ASERCIONES ---'
SELECT escenario, prueba, estado, detalle
FROM sim_resultado
ORDER BY orden;

\echo ''
\echo '--- NOTA DE CONCURRENCIA ---'
SELECT
    'La suite prueba una rafaga de 20 filas en una sentencia. La validacion usa locks FOR UPDATE sobre recursos, pero no se ejecutan dos sesiones concurrentes.' AS diagnostico;
