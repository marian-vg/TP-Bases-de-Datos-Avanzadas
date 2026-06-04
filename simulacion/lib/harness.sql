-- =============================================================================
-- SMART CITY - HARNESS TRANSACCIONAL DE SIMULACION
-- =============================================================================
-- Debe incluirse dentro de una transaccion abierta por 00_run_all.sql.

CREATE TEMP TABLE sim_resultado (
    orden       BIGSERIAL PRIMARY KEY,
    escenario   TEXT NOT NULL,
    prueba      TEXT NOT NULL,
    estado      TEXT NOT NULL CHECK (estado IN ('PASS', 'FAIL', 'XFAIL', 'XPASS', 'SKIP', 'INFO')),
    detalle     TEXT NOT NULL,
    creado_en   TIMESTAMP NOT NULL DEFAULT clock_timestamp()
) ON COMMIT DROP;

CREATE TEMP TABLE sim_metrica (
    orden       BIGSERIAL PRIMARY KEY,
    escenario   TEXT NOT NULL,
    metrica     TEXT NOT NULL,
    valor       NUMERIC NOT NULL,
    detalle     TEXT,
    creado_en   TIMESTAMP NOT NULL DEFAULT clock_timestamp()
) ON COMMIT DROP;

CREATE TEMP TABLE sim_cobertura (
    codigo          TEXT PRIMARY KEY,
    nombre          TEXT NOT NULL,
    objeto_esperado TEXT,
    objeto_instalado BOOLEAN,
    estado          TEXT NOT NULL DEFAULT 'INFO',
    detalle         TEXT NOT NULL DEFAULT 'Pendiente de evaluar'
) ON COMMIT DROP;

CREATE TEMP TABLE sim_parametros_base ON COMMIT DROP AS
SELECT nombre_parametro, numero
FROM ParametrosSistema;

CREATE TEMP TABLE sim_recursos_base ON COMMIT DROP AS
SELECT id_recurso, fk_estado_recurso_id, puntaje
FROM Recurso;

CREATE TEMP TABLE sim_zona_recurso_base ON COMMIT DROP AS
SELECT id_zona, id_recurso
FROM ZonaRecurso;

CREATE TEMP TABLE sim_conteos_base (
    tabla TEXT PRIMARY KEY,
    cantidad BIGINT NOT NULL
) ON COMMIT DROP;

INSERT INTO sim_conteos_base (tabla, cantidad)
VALUES
    ('Incidente',    (SELECT count(*) FROM Incidente)),
    ('Evento',       (SELECT count(*) FROM Evento)),
    ('Asignacion',   (SELECT count(*) FROM Asignacion)),
    ('Penalizacion', (SELECT count(*) FROM Penalizacion)),
    ('Log',          (SELECT count(*) FROM Log)),
    ('ZonaRecurso',  (SELECT count(*) FROM ZonaRecurso));

CREATE OR REPLACE FUNCTION pg_temp.sim_registrar(
    p_escenario TEXT,
    p_prueba TEXT,
    p_estado TEXT,
    p_detalle TEXT
) RETURNS VOID AS $$
BEGIN
    INSERT INTO sim_resultado (escenario, prueba, estado, detalle)
    VALUES (p_escenario, p_prueba, p_estado, COALESCE(p_detalle, ''));
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pg_temp.sim_afirmar(
    p_escenario TEXT,
    p_prueba TEXT,
    p_condicion BOOLEAN,
    p_detalle_ok TEXT,
    p_detalle_error TEXT
) RETURNS VOID AS $$
BEGIN
    PERFORM pg_temp.sim_registrar(
        p_escenario,
        p_prueba,
        CASE WHEN COALESCE(p_condicion, FALSE) THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN COALESCE(p_condicion, FALSE) THEN p_detalle_ok ELSE p_detalle_error END
    );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pg_temp.sim_brecha(
    p_escenario TEXT,
    p_prueba TEXT,
    p_brecha_presente BOOLEAN,
    p_detalle_brecha TEXT,
    p_detalle_resuelto TEXT
) RETURNS VOID AS $$
BEGIN
    PERFORM pg_temp.sim_registrar(
        p_escenario,
        p_prueba,
        CASE WHEN COALESCE(p_brecha_presente, FALSE) THEN 'XFAIL' ELSE 'XPASS' END,
        CASE WHEN COALESCE(p_brecha_presente, FALSE) THEN p_detalle_brecha ELSE p_detalle_resuelto END
    );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pg_temp.sim_medir(
    p_escenario TEXT,
    p_metrica TEXT,
    p_valor NUMERIC,
    p_detalle TEXT DEFAULT NULL
) RETURNS VOID AS $$
BEGIN
    INSERT INTO sim_metrica (escenario, metrica, valor, detalle)
    VALUES (p_escenario, p_metrica, p_valor, p_detalle);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pg_temp.sim_objeto_existe(
    p_tipo "char",
    p_nombre TEXT
) RETURNS BOOLEAN AS $$
    SELECT EXISTS (
        SELECT 1
        FROM pg_proc
        WHERE prokind = p_tipo
          AND lower(proname) = lower(p_nombre)
    );
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION pg_temp.sim_trigger_existe(
    p_tabla TEXT,
    p_trigger TEXT
) RETURNS BOOLEAN AS $$
    SELECT EXISTS (
        SELECT 1
        FROM pg_trigger t
        JOIN pg_class c ON c.oid = t.tgrelid
        WHERE NOT t.tgisinternal
          AND lower(c.relname) = lower(p_tabla)
          AND lower(t.tgname) = lower(p_trigger)
          AND t.tgenabled <> 'D'
    );
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION pg_temp.sim_relacion_existe(
    p_nombre TEXT
) RETURNS BOOLEAN AS $$
    SELECT to_regclass(p_nombre) IS NOT NULL;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION pg_temp.sim_id_catalogo(
    p_tabla TEXT,
    p_columna_id TEXT,
    p_nombre TEXT
) RETURNS INT AS $$
DECLARE
    v_id INT;
BEGIN
    EXECUTE format('SELECT %I FROM %I WHERE nombre = $1', p_columna_id, p_tabla)
    INTO v_id
    USING p_nombre;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION pg_temp.sim_reset_operativo()
RETURNS VOID AS $$
BEGIN
    DELETE FROM Asignacion;
    DELETE FROM Penalizacion;
    DELETE FROM Incidente;
    DELETE FROM Evento;

    UPDATE ParametrosSistema p
    SET numero = b.numero
    FROM sim_parametros_base b
    WHERE p.nombre_parametro = b.nombre_parametro;

    INSERT INTO ParametrosSistema (nombre_parametro, numero)
    SELECT b.nombre_parametro, b.numero
    FROM sim_parametros_base b
    WHERE NOT EXISTS (
        SELECT 1
        FROM ParametrosSistema p
        WHERE p.nombre_parametro = b.nombre_parametro
    );

    DELETE FROM ParametrosSistema p
    WHERE NOT EXISTS (
        SELECT 1
        FROM sim_parametros_base b
        WHERE b.nombre_parametro = p.nombre_parametro
    );

    UPDATE Recurso r
    SET fk_estado_recurso_id = b.fk_estado_recurso_id,
        puntaje = b.puntaje
    FROM sim_recursos_base b
    WHERE r.id_recurso = b.id_recurso
      AND (
          r.fk_estado_recurso_id IS DISTINCT FROM b.fk_estado_recurso_id
          OR r.puntaje IS DISTINCT FROM b.puntaje
      );

    DELETE FROM ZonaRecurso zr
    WHERE NOT EXISTS (
        SELECT 1
        FROM sim_zona_recurso_base b
        WHERE b.id_zona = zr.id_zona
          AND b.id_recurso = zr.id_recurso
    );

    INSERT INTO ZonaRecurso (id_zona, id_recurso)
    SELECT b.id_zona, b.id_recurso
    FROM sim_zona_recurso_base b
    WHERE NOT EXISTS (
        SELECT 1
        FROM ZonaRecurso zr
        WHERE zr.id_zona = b.id_zona
          AND zr.id_recurso = b.id_recurso
    );

    DELETE FROM Log;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pg_temp.sim_capturar_error(
    p_escenario TEXT,
    p_prueba TEXT,
    p_error TEXT
) RETURNS VOID AS $$
BEGIN
    PERFORM pg_temp.sim_registrar(
        p_escenario,
        p_prueba,
        'FAIL',
        'Excepcion inesperada: ' || COALESCE(p_error, 'sin detalle')
    );
END;
$$ LANGUAGE plpgsql;

INSERT INTO sim_cobertura (codigo, nombre, objeto_esperado)
VALUES
    ('R1',  'Asignacion automatica de recursos', 'trg_asignacion_automatica'),
    ('R2',  'Cambio automatico de estado', 'trg_asignacion_aplicada'),
    ('R3',  'Registro automatico de auditoria', 'trg_audit_incidente'),
    ('R4',  'Reasignacion automatica por falla', 'trg_asignacion_finalizada'),
    ('R5',  'Asignacion multiple en incidentes criticos', 'fn_recursos_por_gravedad'),
    ('R6',  'Generacion de incidentes relacionados', NULL),
    ('R7',  'Cierre automatico de incidentes', 'trg_asignacion_finalizada'),
    ('R8',  'Validacion de disponibilidad', 'trg_valida_registro_asignacion'),
    ('R9',  'Validacion de estados', 'trg_valida_registro_incidente'),
    ('R10', 'Validacion de zona', 'trg_valida_registro_asignacion'),
    ('R11', 'Validacion de duplicados', 'trg_valida_registro_incidente'),
    ('R12', 'Priorizacion por gravedad', 'trg_prioridad_incidente'),
    ('R13', 'Priorizacion por zona de riesgo', 'trg_prioridad_incidente'),
    ('R14', 'Seleccion del mejor recurso', 'fn_asignar_recursos_incidente'),
    ('R15', 'Rebalanceo de recursos', 'fn_asignar_recursos_incidente'),
    ('R16', 'Control temporal de SLA', 'sp_escalarincidente'),
    ('R17', 'Reactivacion automatica de recursos', 'sp_reactivarrecursos'),
    ('R18', 'Registro de decisiones automaticas', 'Log'),
    ('R19', 'Log de ejecucion de triggers', 'vHistorialTriggers'),
    ('R20', 'Control de capacidad del sistema', 'trg_control_capacidad'),
    ('R21', 'Confiabilidad de sensores', 'trg_evento_promocion'),
    ('P1',  'sp_AsignarRecurso', 'sp_asignarrecurso'),
    ('P2',  'sp_EscalarIncidente', 'sp_escalarincidente'),
    ('P3',  'sp_CerrarIncidente', 'sp_cerrarincidente'),
    ('P4',  'sp_CalcularPenalizacion', 'sp_calcularpenalizacion'),
    ('P5',  'sp_SimularEventos', 'sp_simulareventos');

SELECT pg_temp.sim_registrar(
    'HARNESS',
    'Inicializacion transaccional',
    'PASS',
    'Snapshot base creado; toda mutacion posterior sera revertida por 00_run_all.sql.'
);
