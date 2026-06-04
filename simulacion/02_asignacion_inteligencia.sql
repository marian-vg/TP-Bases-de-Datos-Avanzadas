\echo '>>> 02 - ASIGNACION E INTELIGENCIA'

SELECT pg_temp.sim_reset_operativo();

DO $$
DECLARE
    v_pendiente INT := pg_temp.sim_id_catalogo('EstadoIncidente', 'id_estado_incidente', 'Pendiente');
    v_tipo INT := pg_temp.sim_id_catalogo('TipoIncidente', 'id_tipo_incidente', 'Accidente de tránsito');
    v_alta INT := pg_temp.sim_id_catalogo('Gravedad', 'id_gravedad', 'Alta');
    v_zona INT;
    v_incidente INT;
    v_asignaciones INT;
    v_estado TEXT;
    v_prioridad INT;
    v_bonus NUMERIC;
    v_mejor INT;
BEGIN
    SELECT z.id_zona INTO v_zona
    FROM Zona z
    JOIN NivelRiesgo nr ON nr.id_nivel_riesgo = z.fk_nivel_riesgo_id
    WHERE nr.valor >= 3
      AND EXISTS (
          SELECT 1
          FROM Recurso r
          JOIN EstadoRecurso er ON er.id_estado_recurso = r.fk_estado_recurso_id
          JOIN ZonaRecurso zr ON zr.id_recurso = r.id_recurso AND zr.id_zona = z.id_zona
          JOIN TipoIncidenteTipoRecurso titr
            ON titr.fk_tipo_recurso_id = r.fk_tipo_recurso_id
           AND titr.fk_tipo_incidente_id = v_tipo
          WHERE er.nombre = 'Disponible'
      )
    ORDER BY nr.valor DESC, z.id_zona
    LIMIT 1;

    SELECT r.id_recurso INTO v_mejor
    FROM Recurso r
    JOIN EstadoRecurso er ON er.id_estado_recurso = r.fk_estado_recurso_id
    JOIN ZonaRecurso zr ON zr.id_recurso = r.id_recurso AND zr.id_zona = v_zona
    JOIN TipoIncidenteTipoRecurso titr
      ON titr.fk_tipo_recurso_id = r.fk_tipo_recurso_id
     AND titr.fk_tipo_incidente_id = v_tipo
    WHERE er.nombre = 'Disponible'
    ORDER BY r.id_recurso
    LIMIT 1;

    UPDATE Recurso SET puntaje = 500 WHERE id_recurso = v_mejor;

    INSERT INTO Incidente (
        fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id,
        fk_zona_id, descripcion, prioridad
    ) VALUES (
        v_tipo, v_alta, v_pendiente, v_zona, 'SIM-PRO-02 asignacion e inteligencia', -1
    ) RETURNING id_incidente INTO v_incidente;

    SELECT count(*) INTO v_asignaciones FROM Asignacion WHERE fk_incidente_id = v_incidente;
    SELECT ei.nombre, i.prioridad INTO v_estado, v_prioridad
    FROM Incidente i JOIN EstadoIncidente ei ON ei.id_estado_incidente = i.fk_estado_incidente_id
    WHERE i.id_incidente = v_incidente;
    SELECT numero INTO v_bonus FROM ParametrosSistema WHERE nombre_parametro = 'BONUS_PRIORIDAD_ZONA_RIESGO';

    PERFORM pg_temp.sim_afirmar('02-ASIGNACION', 'R1/R5 cantidad por gravedad', v_asignaciones = 2,
        'Gravedad Alta genero dos asignaciones.', format('Se esperaban 2 asignaciones y se obtuvieron %s.', v_asignaciones));
    PERFORM pg_temp.sim_afirmar('02-ASIGNACION', 'R2 estado En proceso', v_estado = 'En proceso',
        'El incidente paso automaticamente a En proceso.', format('Estado obtenido: %s.', v_estado));
    PERFORM pg_temp.sim_afirmar('02-ASIGNACION', 'R8 recursos En transito',
        (SELECT count(*) = v_asignaciones FROM Asignacion a JOIN Recurso r ON r.id_recurso = a.fk_recurso_id
         JOIN EstadoRecurso er ON er.id_estado_recurso = r.fk_estado_recurso_id
         WHERE a.fk_incidente_id = v_incidente AND er.nombre = 'En tránsito'),
        'Todos los recursos asignados quedaron En transito antes del arribo.',
        'No todos los recursos asignados quedaron En transito.');
    PERFORM pg_temp.sim_afirmar('02-ASIGNACION', 'R12/R13 prioridad',
        v_prioridad = v_alta * 10 + COALESCE(v_bonus, 10),
        format('Prioridad calculada correctamente: %s.', v_prioridad),
        format('Prioridad inesperada: %s.', v_prioridad));
    PERFORM pg_temp.sim_afirmar('02-ASIGNACION', 'R14 mejor recurso',
        EXISTS (SELECT 1 FROM Asignacion WHERE fk_incidente_id = v_incidente AND fk_recurso_id = v_mejor),
        'El recurso con puntaje superior fue seleccionado.', 'El recurso con puntaje superior no fue seleccionado.');
    PERFORM pg_temp.sim_afirmar('02-ASIGNACION', 'Compatibilidad de tipos',
        NOT EXISTS (
            SELECT 1 FROM Asignacion a
            JOIN Recurso r ON r.id_recurso = a.fk_recurso_id
            WHERE a.fk_incidente_id = v_incidente
              AND NOT EXISTS (
                  SELECT 1 FROM TipoIncidenteTipoRecurso x
                  WHERE x.fk_tipo_incidente_id = v_tipo AND x.fk_tipo_recurso_id = r.fk_tipo_recurso_id
              )
        ), 'Todas las asignaciones son compatibles.', 'Existe una asignacion incompatible.');

    PERFORM pg_temp.sim_medir('02-ASIGNACION', 'asignaciones_generadas', v_asignaciones);
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.sim_capturar_error('02-ASIGNACION', 'Escenario completo', SQLERRM);
END;
$$;
