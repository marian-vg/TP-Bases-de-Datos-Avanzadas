\echo '>>> 08 - RAFAGA DETERMINISTICA DE 20 INCIDENTES'

SELECT pg_temp.sim_reset_operativo();

CREATE TEMP TABLE sim_lote_20 (
    numero INT PRIMARY KEY,
    id_incidente INT NOT NULL
) ON COMMIT DROP;

DO $$
DECLARE
    v_pendiente INT := pg_temp.sim_id_catalogo('EstadoIncidente', 'id_estado_incidente', 'Pendiente');
    v_creados INT;
    v_asignaciones_iniciales INT;
    v_fallas_inducidas INT;
    v_resueltos INT;
    v_pendientes INT;
    v_rebalanceos INT;
BEGIN
    WITH pares AS (
        SELECT
            row_number() OVER (ORDER BY ti.id_tipo_incidente, z.id_zona)::int AS numero,
            ti.id_tipo_incidente,
            z.id_zona
        FROM TipoIncidente ti
        CROSS JOIN Zona z
        ORDER BY ti.id_tipo_incidente, z.id_zona
        LIMIT 20
    ),
    combinaciones AS (
        SELECT p.numero, p.id_tipo_incidente, p.id_zona, g.id_gravedad
        FROM pares p
        JOIN LATERAL (
            SELECT id_gravedad
            FROM Gravedad
            ORDER BY id_gravedad
            OFFSET ((p.numero - 1) % (SELECT count(*) FROM Gravedad))::int
            LIMIT 1
        ) g ON TRUE
    ),
    insertados AS (
        INSERT INTO Incidente (
            fk_tipo_incidente_id,
            fk_gravedad_id,
            fk_estado_incidente_id,
            fk_zona_id,
            descripcion,
            prioridad
        )
        SELECT
            id_tipo_incidente,
            id_gravedad,
            v_pendiente,
            id_zona,
            'SIM-PRO-08 rafaga #' || lpad(numero::text, 2, '0'),
            0
        FROM combinaciones
        ORDER BY numero
        RETURNING id_incidente, descripcion
    )
    INSERT INTO sim_lote_20 (numero, id_incidente)
    SELECT substring(descripcion FROM '#([0-9]+)')::int, id_incidente
    FROM insertados;

    SELECT count(*) INTO v_creados FROM sim_lote_20;
    SELECT count(*) INTO v_asignaciones_iniciales
    FROM Asignacion a JOIN sim_lote_20 l ON l.id_incidente = a.fk_incidente_id;

    WITH candidatas AS (
        SELECT a.id_asignacion,
               row_number() OVER (PARTITION BY a.fk_incidente_id ORDER BY a.id_asignacion) AS posicion
        FROM Asignacion a
        JOIN sim_lote_20 l ON l.id_incidente = a.fk_incidente_id
        WHERE l.numero IN (7, 14)
          AND a.timestamp_finalizacion IS NULL
    )
    UPDATE Asignacion a
    SET estado_exito = FALSE
    FROM candidatas c
    WHERE a.id_asignacion = c.id_asignacion
      AND c.posicion = 1;
    GET DIAGNOSTICS v_fallas_inducidas = ROW_COUNT;

    UPDATE Asignacion a
    SET timestamp_llegada = a.timestamp_asignacion + ((l.numero % 8) + 1) * INTERVAL '1 minute',
        estado_exito = TRUE,
        timestamp_finalizacion = a.timestamp_asignacion + ((l.numero % 8) + 8) * INTERVAL '1 minute'
    FROM sim_lote_20 l
    WHERE l.id_incidente = a.fk_incidente_id
      AND a.timestamp_finalizacion IS NULL;

    SELECT count(*) FILTER (WHERE ei.nombre = 'Resuelto'),
           count(*) FILTER (WHERE ei.nombre = 'Pendiente')
    INTO v_resueltos, v_pendientes
    FROM sim_lote_20 l
    JOIN Incidente i ON i.id_incidente = l.id_incidente
    JOIN EstadoIncidente ei ON ei.id_estado_incidente = i.fk_estado_incidente_id;

    SELECT count(*) INTO v_rebalanceos
    FROM Log
    WHERE detalle::text ILIKE '%rebalanceo%';

    PERFORM pg_temp.sim_afirmar('08-LOTE20', 'Cantidad obligatoria', v_creados = 20,
        'Se insertaron exactamente veinte incidentes en una sentencia.',
        format('Se insertaron %s incidentes.', v_creados));
    PERFORM pg_temp.sim_afirmar('08-LOTE20', 'Combinaciones unicas',
        (SELECT count(*) = count(DISTINCT (i.fk_tipo_incidente_id, i.fk_zona_id))
         FROM sim_lote_20 l JOIN Incidente i ON i.id_incidente = l.id_incidente),
        'Los veinte pares tipo/zona son unicos.', 'El lote contiene pares tipo/zona repetidos.');
    PERFORM pg_temp.sim_afirmar('08-LOTE20', 'Compatibilidad de asignaciones',
        NOT EXISTS (
            SELECT 1
            FROM Asignacion a
            JOIN sim_lote_20 l ON l.id_incidente = a.fk_incidente_id
            JOIN Incidente i ON i.id_incidente = l.id_incidente
            JOIN Recurso r ON r.id_recurso = a.fk_recurso_id
            WHERE NOT EXISTS (
                SELECT 1 FROM TipoIncidenteTipoRecurso x
                WHERE x.fk_tipo_incidente_id = i.fk_tipo_incidente_id
                  AND x.fk_tipo_recurso_id = r.fk_tipo_recurso_id
            )
        ), 'Todas las asignaciones del lote son compatibles.', 'Se encontro una asignacion incompatible.');
    PERFORM pg_temp.sim_afirmar('08-LOTE20', 'Fallas deterministicas',
        v_fallas_inducidas > 0,
        format('Se indujeron %s fallas y el motor pudo reaccionar.', v_fallas_inducidas),
        'No fue posible inducir fallas en el lote.');

    PERFORM pg_temp.sim_medir('08-LOTE20', 'incidentes_creados', v_creados);
    PERFORM pg_temp.sim_medir('08-LOTE20', 'asignaciones_iniciales', v_asignaciones_iniciales);
    PERFORM pg_temp.sim_medir('08-LOTE20', 'fallas_inducidas', v_fallas_inducidas);
    PERFORM pg_temp.sim_medir('08-LOTE20', 'incidentes_resueltos', v_resueltos);
    PERFORM pg_temp.sim_medir('08-LOTE20', 'incidentes_pendientes', v_pendientes);
    PERFORM pg_temp.sim_medir('08-LOTE20', 'decisiones_rebalanceo', v_rebalanceos);

    PERFORM pg_temp.sim_registrar(
        '08-LOTE20', 'Alcance de simultaneidad', 'INFO',
        'La rafaga usa un unico INSERT de veinte filas. Prueba reaccion set-based y triggers fila a fila, no concurrencia multisesion.'
    );
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.sim_capturar_error('08-LOTE20', 'Escenario completo', SQLERRM);
END;
$$;
