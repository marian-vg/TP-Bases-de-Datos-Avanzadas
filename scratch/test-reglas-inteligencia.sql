-- ============================================================================
-- SCRIPT DE PRUEBAS DE INTELIGENCIA — reglas-inteligencia.sql (R12, R13, R14, R15)
-- ============================================================================
--
-- Bloque "Reglas de Inteligencia" del TP: R12 (prioridad por gravedad),
-- R13 (prioridad por zona de riesgo), R14 (selección del mejor recurso) y
-- R15 (rebalanceo geográfico).
--
-- ESTADO DE IMPLEMENTACIÓN (a la fecha de este test):
--   R14  -> IMPLEMENTADA en database/triggers/reglas-inteligencia.sql.
--           Sus pruebas usan RAISE EXCEPTION: si fallan, el script ABORTA (gritan).
--   R12, R13, R15 -> PENDIENTES en los archivos modulares (database/triggers/).
--           Sus pruebas usan RAISE WARNING: dejan registrada la especificación
--           esperada SIN abortar la corrida. Cuando se implementen, basta cambiar
--           el WARNING por EXCEPTION para que pasen a ser aserciones duras.
--
-- Patrón de aserción: igual que scratch/test-reglas-activas.sql. Cada escenario
-- ejecuta la acción y comprueba el resultado.
--
-- Requiere haber cargado, EN ESTE ORDEN:
--   create-tables -> carga-dataset -> reglas-validadoras -> reglas-inteligencia
--   -> reglas-automatizacion
-- (reglas-inteligencia ANTES de reglas-automatizacion: el motor de asignación
--  ordena por Recurso.puntaje, que mantiene este archivo de inteligencia).
--
-- Es destructivo sobre las tablas operativas (Asignacion/Incidente/Evento/
-- Penalizacion/Log), que en el dataset base están vacías. Resetea puntaje y deja
-- los recursos en 'Disponible' al finalizar.
-- ============================================================================

\set ON_ERROR_STOP on

\echo '--------------------------------------------------'
\echo 'INICIANDO PRUEBAS DE INTELIGENCIA (R12, R13, R14, R15)'
\echo '--------------------------------------------------'

-- Reset idempotente de tablas operativas, puntaje y estado de los recursos.
DELETE FROM Asignacion;
DELETE FROM Penalizacion;
DELETE FROM Incidente;
DELETE FROM Evento;
DELETE FROM Log;
UPDATE Recurso SET fk_estado_recurso_id = 1 WHERE fk_estado_recurso_id <> 1;
UPDATE Recurso SET puntaje = 0 WHERE puntaje <> 0;

-- Sincronizar secuencias para evitar colisiones de PKs.
SELECT setval(pg_get_serial_sequence('recurso', 'id_recurso'),         COALESCE(MAX(id_recurso), 1))     FROM Recurso;
SELECT setval(pg_get_serial_sequence('incidente', 'id_incidente'),     COALESCE(MAX(id_incidente), 1))   FROM Incidente;
SELECT setval(pg_get_serial_sequence('asignacion', 'id_asignacion'),   COALESCE(MAX(id_asignacion), 1))  FROM Asignacion;
SELECT setval(pg_get_serial_sequence('penalizacion', 'id_penalizacion'), COALESCE(MAX(id_penalizacion), 1)) FROM Penalizacion;


-- ============================================================================
-- R14 — SELECCIÓN DEL MEJOR RECURSO (IMPLEMENTADA)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- PRUEBA 1: R14 — el motor elige el recurso de MAYOR puntaje
-- ----------------------------------------------------------------------------
\echo '>>> PRUEBA 1: R14 — el motor asigna el recurso de mayor puntaje'

DO $$
DECLARE
    v_pendiente   INT;
    v_incidente   INT;
    v_mejor       INT;
    v_asignado    INT;
BEGIN
    SELECT id_estado_incidente INTO v_pendiente FROM EstadoIncidente WHERE nombre = 'Pendiente';

    -- Todos los candidatos válidos para (tipo 1, zona 1) arrancan en 0; a UNO le damos +50.
    UPDATE Recurso r SET puntaje = 0
     WHERE r.fk_estado_recurso_id = 1
       AND EXISTS (SELECT 1 FROM TipoIncidenteTipoRecurso titr
                    WHERE titr.fk_tipo_recurso_id = r.fk_tipo_recurso_id AND titr.fk_tipo_incidente_id = 1)
       AND EXISTS (SELECT 1 FROM ZonaRecurso zr WHERE zr.id_recurso = r.id_recurso AND zr.id_zona = 1);

    SELECT r.id_recurso INTO v_mejor
      FROM Recurso r
      JOIN TipoIncidenteTipoRecurso titr ON titr.fk_tipo_recurso_id = r.fk_tipo_recurso_id AND titr.fk_tipo_incidente_id = 1
      JOIN ZonaRecurso zr ON zr.id_recurso = r.id_recurso AND zr.id_zona = 1
     WHERE r.fk_estado_recurso_id = 1
     ORDER BY r.id_recurso
     LIMIT 1;

    IF v_mejor IS NULL THEN
        RAISE EXCEPTION 'PRECONDICIÓN FALLIDA: no hay recurso compatible (tipo 1, zona 1) disponible.';
    END IF;

    UPDATE Recurso SET puntaje = 50 WHERE id_recurso = v_mejor;

    -- Incidente gravedad Baja (1) -> requiere 1 recurso. Debe tocarle el de mayor puntaje.
    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    VALUES (1, 1, v_pendiente, 1, 'P1 - R14 mejor recurso', 1)
    RETURNING id_incidente INTO v_incidente;

    SELECT fk_recurso_id INTO v_asignado FROM Asignacion WHERE fk_incidente_id = v_incidente;

    IF v_asignado IS DISTINCT FROM v_mejor THEN
        RAISE EXCEPTION 'FALLO R14: debía asignar el recurso de mayor puntaje (#%), asignó #%.', v_mejor, v_asignado;
    END IF;

    RAISE NOTICE 'ÉXITO P1: R14 asignó el recurso de mayor puntaje (#%).', v_mejor;

    DELETE FROM Asignacion WHERE fk_incidente_id = v_incidente;
    DELETE FROM Incidente WHERE id_incidente = v_incidente;
    UPDATE Recurso SET fk_estado_recurso_id = 1 WHERE fk_estado_recurso_id <> 1;
    UPDATE Recurso SET puntaje = 0 WHERE puntaje <> 0;
END;
$$;


-- Para las pruebas de FÓRMULA del puntaje apagamos la asignación automática:
-- así controlamos exactamente qué asignaciones recibe cada recurso.
ALTER TABLE Incidente DISABLE TRIGGER trg_asignacion_automatica;

ALTER TABLE Incidente DISABLE TRIGGER trg_valida_registro_incidente;
-- ----------------------------------------------------------------------------
-- PRUEBA 2: R14 — una asignación exitosa suma +1
-- ----------------------------------------------------------------------------
\echo '>>> PRUEBA 2: R14 — éxito suma +1 al puntaje'

DO $$
DECLARE
    v_pendiente INT;
    v_inc       INT;
    v_rec       INT;
    v_asig      INT;
    v_puntaje   INT;
BEGIN
    SELECT id_estado_incidente INTO v_pendiente FROM EstadoIncidente WHERE nombre = 'Pendiente';

    SELECT r.id_recurso INTO v_rec
      FROM Recurso r
      JOIN TipoIncidenteTipoRecurso titr ON titr.fk_tipo_recurso_id = r.fk_tipo_recurso_id AND titr.fk_tipo_incidente_id = 1
      JOIN ZonaRecurso zr ON zr.id_recurso = r.id_recurso AND zr.id_zona = 1
     WHERE r.fk_estado_recurso_id = 1
     ORDER BY r.id_recurso LIMIT 1;

    UPDATE Recurso SET puntaje = 0 WHERE id_recurso = v_rec;
    DELETE FROM Asignacion WHERE fk_recurso_id = v_rec;

    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    VALUES (1, 1, v_pendiente, 1, 'P2 - R14 +1 por exito', 1) RETURNING id_incidente INTO v_inc;

    INSERT INTO Asignacion (fk_recurso_id, fk_incidente_id) VALUES (v_rec, v_inc) RETURNING id_asignacion INTO v_asig;

    -- Éxito SIN registrar llegada -> +1 base, sin bonus de SLA, sin racha (es el 1.er éxito).
    UPDATE Asignacion SET estado_exito = TRUE, timestamp_finalizacion = CURRENT_TIMESTAMP WHERE id_asignacion = v_asig;

    SELECT puntaje INTO v_puntaje FROM Recurso WHERE id_recurso = v_rec;
    IF v_puntaje <> 1 THEN
        RAISE EXCEPTION 'FALLO R14(+1): tras 1 éxito el puntaje debía ser 1, es %.', v_puntaje;
    END IF;

    RAISE NOTICE 'ÉXITO P2: una asignación exitosa sumó +1 (puntaje = %).', v_puntaje;

    DELETE FROM Asignacion WHERE fk_recurso_id = v_rec;
    DELETE FROM Incidente WHERE id_incidente = v_inc;
    UPDATE Recurso SET fk_estado_recurso_id = 1, puntaje = 0 WHERE id_recurso = v_rec;
END;
$$;


-- ----------------------------------------------------------------------------
-- PRUEBA 3: R14 — 3 éxitos consecutivos suman +1 extra (3.er éxito vale +2)
-- ----------------------------------------------------------------------------
\echo '>>> PRUEBA 3: R14 — racha de 3 éxitos consecutivos da +1 extra (puntaje final 4)'

DO $$
DECLARE
    v_pendiente INT;
    v_rec       INT;
    v_inc       INT;
    v_asig      INT;
    v_puntaje   INT;
    i           INT;
BEGIN
    SELECT id_estado_incidente INTO v_pendiente FROM EstadoIncidente WHERE nombre = 'Pendiente';

    SELECT r.id_recurso INTO v_rec
      FROM Recurso r
      JOIN TipoIncidenteTipoRecurso titr ON titr.fk_tipo_recurso_id = r.fk_tipo_recurso_id AND titr.fk_tipo_incidente_id = 1
      JOIN ZonaRecurso zr ON zr.id_recurso = r.id_recurso AND zr.id_zona = 1
     WHERE r.fk_estado_recurso_id = 1
     ORDER BY r.id_recurso LIMIT 1;

    UPDATE Recurso SET puntaje = 0 WHERE id_recurso = v_rec;
    DELETE FROM Asignacion WHERE fk_recurso_id = v_rec;

    -- 3 ciclos: asignar -> cerrar con éxito (sin llegada, para aislar el bonus de SLA).
    FOR i IN 1..3 LOOP
        INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
        VALUES (1, 1, v_pendiente, 1, 'P3 - racha #' || i, 1) RETURNING id_incidente INTO v_inc;

        INSERT INTO Asignacion (fk_recurso_id, fk_incidente_id) VALUES (v_rec, v_inc) RETURNING id_asignacion INTO v_asig;
        UPDATE Asignacion SET estado_exito = TRUE, timestamp_finalizacion = CURRENT_TIMESTAMP WHERE id_asignacion = v_asig;
    END LOOP;

    -- 3 éxitos: +1 +1 +(1+1 de racha) = 4.
    SELECT puntaje INTO v_puntaje FROM Recurso WHERE id_recurso = v_rec;
    IF v_puntaje <> 4 THEN
        RAISE EXCEPTION 'FALLO R14(racha): tras 3 éxitos consecutivos el puntaje debía ser 4 (3 base + 1 racha), es %.', v_puntaje;
    END IF;

    RAISE NOTICE 'ÉXITO P3: racha de 3 éxitos dio el +1 extra (puntaje = %).', v_puntaje;

    DELETE FROM Asignacion WHERE fk_recurso_id = v_rec;
    DELETE FROM Incidente WHERE descripcion LIKE 'P3 - racha%';
    UPDATE Recurso SET fk_estado_recurso_id = 1, puntaje = 0 WHERE id_recurso = v_rec;
END;
$$;


-- ----------------------------------------------------------------------------
-- PRUEBA 4: R14 — cumplir el SLA suma + id_gravedad; incumplirlo no da bonus
-- ----------------------------------------------------------------------------
\echo '>>> PRUEBA 4: R14 — bonus de SLA = nivel de gravedad (y sin bonus si llega tarde)'

DO $$
DECLARE
    v_pendiente INT;
    v_rec       INT;
    v_inc       INT;
    v_asig      INT;
    v_sla       INT;
    v_puntaje   INT;
BEGIN
    SELECT id_estado_incidente INTO v_pendiente FROM EstadoIncidente WHERE nombre = 'Pendiente';
    SELECT tiempo_respuesta_minutos INTO v_sla FROM SLA WHERE fk_gravedad_id = 3;  -- gravedad Alta

    SELECT r.id_recurso INTO v_rec
      FROM Recurso r
      JOIN TipoIncidenteTipoRecurso titr ON titr.fk_tipo_recurso_id = r.fk_tipo_recurso_id AND titr.fk_tipo_incidente_id = 1
      JOIN ZonaRecurso zr ON zr.id_recurso = r.id_recurso AND zr.id_zona = 1
     WHERE r.fk_estado_recurso_id = 1
     ORDER BY r.id_recurso LIMIT 1;

    -- ---- 4a) DENTRO del SLA: llegada 1 min después de la asignación -> +1 base + 3 (gravedad) = 4
    UPDATE Recurso SET puntaje = 0 WHERE id_recurso = v_rec;
    DELETE FROM Asignacion WHERE fk_recurso_id = v_rec;

    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    VALUES (1, 3, v_pendiente, 1, 'P4a - SLA cumplido', 3) RETURNING id_incidente INTO v_inc;
    INSERT INTO Asignacion (fk_recurso_id, fk_incidente_id) VALUES (v_rec, v_inc) RETURNING id_asignacion INTO v_asig;

    UPDATE Asignacion
       SET timestamp_llegada = timestamp_asignacion + INTERVAL '1 minute',
           estado_exito = TRUE,
           timestamp_finalizacion = CURRENT_TIMESTAMP
     WHERE id_asignacion = v_asig;

    SELECT puntaje INTO v_puntaje FROM Recurso WHERE id_recurso = v_rec;
    IF v_puntaje <> 4 THEN
        RAISE EXCEPTION 'FALLO R14(SLA cumplido): esperado 1 base + 3 gravedad = 4, obtenido %.', v_puntaje;
    END IF;
    RAISE NOTICE 'ÉXITO P4a: SLA cumplido sumó +1 base + 3 de gravedad (puntaje = %).', v_puntaje;

    -- ---- 4b) FUERA del SLA: llegada muy tardía -> solo +1 base, sin bonus
    UPDATE Recurso SET puntaje = 0 WHERE id_recurso = v_rec;
    DELETE FROM Asignacion WHERE fk_recurso_id = v_rec;
    UPDATE Recurso SET fk_estado_recurso_id = 1 WHERE id_recurso = v_rec;

    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    VALUES (1, 3, v_pendiente, 1, 'P4b - SLA incumplido', 3) RETURNING id_incidente INTO v_inc;
    INSERT INTO Asignacion (fk_recurso_id, fk_incidente_id) VALUES (v_rec, v_inc) RETURNING id_asignacion INTO v_asig;

    UPDATE Asignacion
       SET timestamp_llegada = timestamp_asignacion + ((v_sla + 30) || ' minutes')::INTERVAL,
           estado_exito = TRUE,
           timestamp_finalizacion = CURRENT_TIMESTAMP
     WHERE id_asignacion = v_asig;

    SELECT puntaje INTO v_puntaje FROM Recurso WHERE id_recurso = v_rec;
    IF v_puntaje <> 1 THEN
        RAISE EXCEPTION 'FALLO R14(SLA incumplido): llegando tarde solo correspondía +1 base, obtenido %.', v_puntaje;
    END IF;
    RAISE NOTICE 'ÉXITO P4b: llegar fuera del SLA no dio bonus (puntaje = %).', v_puntaje;

    DELETE FROM Asignacion WHERE fk_recurso_id = v_rec;
    DELETE FROM Incidente WHERE descripcion LIKE 'P4%';
    UPDATE Recurso SET fk_estado_recurso_id = 1, puntaje = 0 WHERE id_recurso = v_rec;
END;
$$;


-- ----------------------------------------------------------------------------
-- PRUEBA 5: R14 — una penalización resta COALESCE(Penalizacion.puntaje, TipoPenalizacion.puntaje)
-- ----------------------------------------------------------------------------
\echo '>>> PRUEBA 5: R14 — la penalización descuenta puntaje por COALESCE explícito/default'

DO $$
DECLARE
    v_rec       INT;
    v_tipo      INT;
    v_resta     INT;
    v_puntaje   INT;
    v_resta_variable INT := 7;
BEGIN
    SELECT id_recurso INTO v_rec FROM Recurso WHERE fk_estado_recurso_id = 1 ORDER BY id_recurso LIMIT 1;

    -- Partimos de 10 para evidenciar el descuento sobre un valor positivo.
    UPDATE Recurso SET puntaje = 10 WHERE id_recurso = v_rec;
    DELETE FROM Penalizacion WHERE fk_recurso_id = v_rec;

    SELECT id_tipo_penalizacion, puntaje INTO v_tipo, v_resta
    FROM TipoPenalizacion WHERE nombre LIKE 'Falla en intervenci%n';

    -- Caso default: Penalizacion.puntaje NULL -> usa TipoPenalizacion.puntaje.
    INSERT INTO Penalizacion (fk_recurso_id, fk_tipo_penalizacion_id, motivo)
    VALUES (v_rec, v_tipo, 'P5 - prueba de descuento de puntaje');

    SELECT puntaje INTO v_puntaje FROM Recurso WHERE id_recurso = v_rec;
    IF v_puntaje <> 10 - v_resta THEN
        RAISE EXCEPTION 'FALLO R14(penalización): esperado % (10 - %), obtenido %.', 10 - v_resta, v_resta, v_puntaje;
    END IF;

    -- Caso variable: Penalizacion.puntaje explícito -> usa ese monto real.
    UPDATE Recurso SET puntaje = 10 WHERE id_recurso = v_rec;
    INSERT INTO Penalizacion (fk_recurso_id, fk_tipo_penalizacion_id, puntaje, motivo)
    VALUES (v_rec, v_tipo, v_resta_variable, 'P5 - prueba de descuento variable');

    SELECT puntaje INTO v_puntaje FROM Recurso WHERE id_recurso = v_rec;
    IF v_puntaje <> 10 - v_resta_variable THEN
        RAISE EXCEPTION 'FALLO R14(penalización variable): esperado % (10 - %), obtenido %.', 10 - v_resta_variable, v_resta_variable, v_puntaje;
    END IF;

    RAISE NOTICE 'ÉXITO P5: COALESCE restó default % y luego puntaje variable %.', v_resta, v_resta_variable;

    DELETE FROM Penalizacion WHERE fk_recurso_id = v_rec;
    UPDATE Recurso SET puntaje = 0 WHERE id_recurso = v_rec;
END;
$$;


-- ============================================================================
-- R12 — PRIORIZACIÓN AUTOMÁTICA POR GRAVEDAD (PENDIENTE en módulos)
-- ============================================================================
-- Especificación esperada: al insertar un incidente, su prioridad debe calcularse
-- automáticamente a partir de la gravedad (p. ej. prioridad = gravedad * 10),
-- ignorando el valor que provea el llamador.
\echo '>>> PRUEBA 6: R12 — prioridad automática por gravedad (PENDIENTE)'

DO $$
DECLARE
    v_pendiente INT;
    v_inc       INT;
    v_prioridad INT;
    v_esperado  INT;
BEGIN
    SELECT id_estado_incidente INTO v_pendiente FROM EstadoIncidente WHERE nombre = 'Pendiente';
    v_esperado := 3 * 10;  -- gravedad Alta (3) -> 30, según la especificación de R12

    ALTER TABLE Incidente DISABLE TRIGGER trg_asignacion_automatica;
    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    VALUES (1, 3, v_pendiente, 5, 'P6 - R12 prioridad por gravedad', 99) RETURNING id_incidente INTO v_inc;
    ALTER TABLE Incidente ENABLE TRIGGER trg_asignacion_automatica;

    SELECT prioridad INTO v_prioridad FROM Incidente WHERE id_incidente = v_inc;

    IF v_prioridad = v_esperado THEN
        RAISE NOTICE 'ÉXITO R12: prioridad calculada automáticamente (% para gravedad Alta).', v_prioridad;
    ELSE
        RAISE EXCEPTION 'FALLO R12: esperado prioridad %, se obtuvo %.', v_esperado, v_prioridad;
    END IF;

    DELETE FROM Incidente WHERE id_incidente = v_inc;
END;
$$;


-- ============================================================================
-- R13 — PRIORIZACIÓN POR ZONA DE RIESGO (PENDIENTE en módulos)
-- ============================================================================
-- Especificación esperada: si el incidente ocurre en una zona de alto riesgo
-- (NivelRiesgo.valor alto), su prioridad debe incrementarse por encima de la que
-- tendría el mismo incidente en una zona de bajo riesgo.
\echo '>>> PRUEBA 7: R13 — bonus de prioridad por zona de riesgo (PENDIENTE)'

DO $$
DECLARE
    v_pendiente   INT;
    v_zona_alta   INT;
    v_zona_baja   INT;
    v_inc_alta    INT;
    v_inc_baja    INT;
    v_prio_alta   INT;
    v_prio_baja   INT;
BEGIN
    SELECT id_estado_incidente INTO v_pendiente FROM EstadoIncidente WHERE nombre = 'Pendiente';

    SELECT z.id_zona INTO v_zona_alta
      FROM Zona z JOIN NivelRiesgo nr ON z.fk_nivel_riesgo_id = nr.id_nivel_riesgo
     ORDER BY nr.id_nivel_riesgo DESC LIMIT 1;
    SELECT z.id_zona INTO v_zona_baja
      FROM Zona z JOIN NivelRiesgo nr ON z.fk_nivel_riesgo_id = nr.id_nivel_riesgo
     ORDER BY nr.id_nivel_riesgo ASC LIMIT 1;

    ALTER TABLE Incidente DISABLE TRIGGER trg_asignacion_automatica;
    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    VALUES (1, 3, v_pendiente, v_zona_alta, 'P7 - R13 zona alto riesgo', 0) RETURNING id_incidente INTO v_inc_alta;
    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    VALUES (1, 3, v_pendiente, v_zona_baja, 'P7 - R13 zona bajo riesgo', 0) RETURNING id_incidente INTO v_inc_baja;
    ALTER TABLE Incidente ENABLE TRIGGER trg_asignacion_automatica;

    SELECT prioridad INTO v_prio_alta FROM Incidente WHERE id_incidente = v_inc_alta;
    SELECT prioridad INTO v_prio_baja FROM Incidente WHERE id_incidente = v_inc_baja;

    IF v_prio_alta > v_prio_baja THEN
        RAISE NOTICE 'ÉXITO R13: zona de alto riesgo tiene mayor prioridad (% vs %).', v_prio_alta, v_prio_baja;
    ELSE
        RAISE EXCEPTION 'FALLO R13: zona de alto riesgo (%) no superó a la de bajo riesgo (%).', v_prio_alta, v_prio_baja;
    END IF;

    DELETE FROM Incidente WHERE id_incidente IN (v_inc_alta, v_inc_baja);
END;
$$;


-- ============================================================================
-- R15 — REBALANCEO GEOGRÁFICO DE RECURSOS (PENDIENTE en módulos)
-- ============================================================================
-- Especificación esperada: si en la zona del incidente NO quedan recursos
-- compatibles disponibles, el sistema debe traer (rebalancear) un recurso
-- compatible de otra zona, en lugar de dejar el incidente sin atender.
\echo '>>> PRUEBA 8: R15 — rebalanceo desde otra zona cuando la local se agota (PENDIENTE)'

DO $$
DECLARE
    v_pendiente INT;
    v_inc       INT;
    v_n_asig    INT;
BEGIN
    SELECT id_estado_incidente INTO v_pendiente FROM EstadoIncidente WHERE nombre = 'Pendiente';

    -- Dejamos sin recursos disponibles a la zona 1 para el tipo 1 (los ponemos Fuera de servicio).
    UPDATE Recurso r SET fk_estado_recurso_id = 3
     WHERE EXISTS (SELECT 1 FROM ZonaRecurso zr WHERE zr.id_recurso = r.id_recurso AND zr.id_zona = 1)
       AND EXISTS (SELECT 1 FROM TipoIncidenteTipoRecurso titr
                    WHERE titr.fk_tipo_recurso_id = r.fk_tipo_recurso_id AND titr.fk_tipo_incidente_id = 1);

    INSERT INTO Incidente (fk_tipo_incidente_id, fk_gravedad_id, fk_estado_incidente_id, fk_zona_id, descripcion, prioridad)
    VALUES (1, 1, v_pendiente, 1, 'P8 - R15 rebalanceo', 1) RETURNING id_incidente INTO v_inc;

    SELECT count(*) INTO v_n_asig FROM Asignacion WHERE fk_incidente_id = v_inc;

    IF v_n_asig >= 1 THEN
        RAISE NOTICE 'ÉXITO R15: se rebalanceó un recurso de otra zona (% asignación/es).', v_n_asig;
    ELSE
        RAISE EXCEPTION 'FALLO R15: sin recursos locales el incidente quedó sin asignar (no hubo rebalanceo).';
    END IF;

    DELETE FROM Asignacion WHERE fk_incidente_id = v_inc;
    DELETE FROM Incidente WHERE id_incidente = v_inc;
    UPDATE Recurso SET fk_estado_recurso_id = 1 WHERE fk_estado_recurso_id <> 1;
END;
$$;


-- Reset final: dejar el entorno limpio.
DELETE FROM Asignacion;
DELETE FROM Penalizacion;
DELETE FROM Incidente;
DELETE FROM Evento;
DELETE FROM Log;
UPDATE Recurso SET fk_estado_recurso_id = 1 WHERE fk_estado_recurso_id <> 1;
UPDATE Recurso SET puntaje = 0 WHERE puntaje <> 0;

-- Rehabilitar los triggers apagados
ALTER TABLE Incidente ENABLE TRIGGER trg_asignacion_automatica;
ALTER TABLE Incidente ENABLE TRIGGER trg_valida_registro_incidente;

\echo '--------------------------------------------------'
\echo '>>> PRUEBAS DE INTELIGENCIA FINALIZADAS'
\echo '    R14: aserciones duras (deben pasar). R12/R13/R15: spec pendiente (WARNING).'
\echo '--------------------------------------------------'
