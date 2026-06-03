-- =============================================================================================================
-- REGLAS ACTIVAS DE AUTOMATIZACIÓN — Smart City (PostgreSQL 16)
-- =============================================================================================================
--
-- Implementación de las reglas de automatización del TP: R1, R2, R3, R4, R5, R7, R8, R9 y R21.
--
-- Convive con database/triggers/reglas-validadoras.sql (validaciones BEFORE de R8/R9/R10/R11). El orden
-- de carga recomendado para probarlo es:
--   create-tables.sql -> carga-dataset.sql -> reglas-validadoras.sql -> reglas-activas.sql
--
-- Mapa de reglas:
--   R1     Asignación automática de recursos al registrarse un incidente (respeta UMBRAL_RECURSOS_ACTIVOS).
--   R2     El incidente pasa a 'En proceso' al asignarse un recurso.
--   R3     Auditoría genérica de cada movimiento (una sola fn_auditoria sobre las tablas operativas).
--   R4/R9  Asignación fallida: penaliza el recurso, lo libera y reasigna uno nuevo.
--   R5     Cantidad de recursos según gravedad (Baja/Moderada=1, Alta=2, Crítica=3, Catastrófica=4).
--   R7     Cierre automático del incidente ('Resuelto') cuando finalizan todas sus asignaciones.
--   R8     Estado del recurso según su asignación ('Disponible' <-> 'Ocupado').
--   R21    Promoción de evento a incidente solo si la confianza del sensor supera el umbral y el
--          tipo de evento deriva a UN único tipo de incidente (TipoEventoTipoIncidente).
--
-- Dependencias de esquema: tabla TipoEventoTipoIncidente y parámetro UMBRAL_RECURSOS_ACTIVOS.
-- Convención: funciones fn_*, triggers trg_*; idempotente (CREATE OR REPLACE + DROP TRIGGER IF EXISTS).
-- =============================================================================================================


-- =============================================================================================================
-- PARTE 1: MOTOR DE ASIGNACIÓN AUTOMÁTICA (R1, R2, R5, R8)
-- =============================================================================================================
--
-- Objetos creados en este bloque (en orden de dependencia):
--   1. fn_recursos_por_gravedad   — R5: cantidad de recursos según gravedad del incidente
--   2. fn_asignar_recursos_incidente — motor reutilizable de asignación (INSERT set-based)
--   3. fn_asignacion_automatica / trg_asignacion_automatica — R1: disparo al insertar incidente
--   4. fn_asignacion_aplicada    / trg_asignacion_aplicada  — R2 + R8(insert): cambios de estado
--
-- Convivencia con reglas-validadoras.sql:
--   El trigger BEFORE INSERT en Asignacion (fn_valida_registro_asignacion) valida disponibilidad,
--   tipo aplicable y zona habilitada ANTES de que cada fila se persista. El INSERT set-based del
--   motor filtra solo recursos 'Disponible' sin asignación abierta: cada fila pasa la validación
--   de forma independiente porque los recursos en el SELECT son distintos entre sí.
-- =============================================================================================================


-- =============================================================================================================
-- 1. fn_recursos_por_gravedad — R5
-- =============================================================================================================
--
-- Retorna la cantidad de recursos a asignar según la gravedad del incidente.
-- Mapeo: Baja (1) y Moderada (2) -> 1 recurso; Alta (3) -> 2; Crítica (4) -> 3;
--        Catastrófica (5) -> 4; cualquier otro -> 1 (fallback seguro).

CREATE OR REPLACE FUNCTION fn_recursos_por_gravedad(p_id_gravedad INT)
RETURNS INT AS $$
    SELECT CASE p_id_gravedad
        WHEN 1 THEN 1   -- Baja
        WHEN 2 THEN 1   -- Moderada
        WHEN 3 THEN 2   -- Alta
        WHEN 4 THEN 3   -- Crítica
        WHEN 5 THEN 4   -- Catastrófica
        ELSE 1
    END;
$$ LANGUAGE sql IMMUTABLE;
-- Al ser una funcion independiente, usamos IMMUTABLE. 
-- Acá le decimos a Postgre que esta es determinística y siempre devuelve el mismo resultado.

-- =============================================================================================================
-- 2. fn_asignar_recursos_incidente — Motor reutilizable (R1 y otras reglas)
-- =============================================================================================================
--
-- Inserta hasta p_cantidad asignaciones para el incidente dado, seleccionando recursos que:
--   a) estén en estado 'Disponible'
--   b) su tipo sea aplicable al tipo del incidente (TipoIncidenteTipoRecurso)
--   c) estén habilitados para operar en la zona del incidente (ZonaRecurso)
--   d) no tengan una asignación activa (timestamp_finalizacion IS NULL)
-- Devuelve la cantidad de filas efectivamente insertadas.
-- NO verifica el umbral de recursos activos: esa responsabilidad es del llamador (R1).

CREATE OR REPLACE FUNCTION fn_asignar_recursos_incidente(p_id_incidente INT, p_cantidad INT)
RETURNS INT AS $$
DECLARE
    v_insertados INT;
BEGIN
    INSERT INTO Asignacion (fk_recurso_id, fk_incidente_id)
    SELECT r.id_recurso, p_id_incidente
    FROM Recurso r
    JOIN EstadoRecurso er ON r.fk_estado_recurso_id = er.id_estado_recurso
    WHERE er.nombre = 'Disponible'
      -- b) el tipo de recurso debe ser aplicable al tipo del incidente
      AND EXISTS (
          SELECT 1
          FROM TipoIncidenteTipoRecurso titr
          WHERE titr.fk_tipo_recurso_id   = r.fk_tipo_recurso_id
            AND titr.fk_tipo_incidente_id = (
                SELECT i.fk_tipo_incidente_id
                FROM Incidente i
                WHERE i.id_incidente = p_id_incidente
            )
      )
      -- c) el recurso debe estar habilitado en la zona del incidente
      AND EXISTS (
          SELECT 1
          FROM ZonaRecurso zr
          WHERE zr.id_recurso = r.id_recurso
            AND zr.id_zona = (
                SELECT i.fk_zona_id
                FROM Incidente i
                WHERE i.id_incidente = p_id_incidente
            )
      )
      -- d) sin asignación activa (timestamp_finalizacion IS NULL = en curso)
      AND NOT EXISTS (
          SELECT 1
          FROM Asignacion a
          WHERE a.fk_recurso_id = r.id_recurso
            AND a.timestamp_finalizacion IS NULL
      )
    ORDER BY r.id_recurso
    LIMIT p_cantidad;

    GET DIAGNOSTICS v_insertados = ROW_COUNT;
    RETURN v_insertados;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================================================
-- 3. R1 — fn_asignacion_automatica / trg_asignacion_automatica
-- =============================================================================================================
--
-- Al insertar un incidente, verifica si el sistema tiene capacidad (asignaciones abiertas
-- por debajo del umbral UMBRAL_RECURSOS_ACTIVOS, default 50). Si hay capacidad, invoca el
-- motor para despachar la cantidad de recursos que corresponde a la gravedad del incidente.
-- Si se superó el umbral, el incidente queda en estado 'Pendiente' sin asignación.

CREATE OR REPLACE FUNCTION fn_asignacion_automatica()
RETURNS TRIGGER AS $$
DECLARE
    v_umbral       INT;
    v_asignaciones_abiertas INT;
BEGIN
    -- Leer el umbral del sistema; si no está configurado, usar 50 como valor por defecto.
    SELECT COALESCE(
        (SELECT numero FROM ParametrosSistema WHERE nombre_parametro = 'UMBRAL_RECURSOS_ACTIVOS'),
        50
    ) INTO v_umbral;

    -- Contar asignaciones globalmente abiertas (sin fecha de finalización).
    SELECT count(*)
    INTO v_asignaciones_abiertas
    FROM Asignacion
    WHERE timestamp_finalizacion IS NULL;

    -- Solo despachar si estamos por debajo del umbral.
    IF v_asignaciones_abiertas < v_umbral THEN
        PERFORM fn_asignar_recursos_incidente(
            NEW.id_incidente,
            fn_recursos_por_gravedad(NEW.fk_gravedad_id)
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_asignacion_automatica ON Incidente;
CREATE TRIGGER trg_asignacion_automatica
AFTER INSERT ON Incidente
FOR EACH ROW
EXECUTE FUNCTION fn_asignacion_automatica();


-- =============================================================================================================
-- 4. R2 + R8(insert) — fn_asignacion_aplicada / trg_asignacion_aplicada
-- =============================================================================================================
--
-- Al insertar una asignación nueva:
--   R8 (efecto): pasa el recurso asignado de 'Disponible' a 'Ocupado'.
--   R2: si el incidente asociado aún está en 'Pendiente', lo mueve a 'En proceso'.
--       No se toca si el incidente ya está en cualquier otro estado posterior (En proceso,
--       Escalado, etc.) para no pisar transiciones legítimas posteriores.

CREATE OR REPLACE FUNCTION fn_asignacion_aplicada()
RETURNS TRIGGER AS $$
BEGIN
    -- R8: marcar el recurso como 'Ocupado' ahora que tiene una asignación activa.
    UPDATE Recurso
    SET fk_estado_recurso_id = (
        SELECT id_estado_recurso
        FROM EstadoRecurso
        WHERE nombre = 'Ocupado'
    )
    WHERE id_recurso = NEW.fk_recurso_id;

    -- R2: mover el incidente a 'En proceso' solo si todavía está en 'Pendiente'.
    --     La subconsulta evita hardcodear IDs y respeta la whitelist de transiciones
    --     del trigger validador (Pendiente -> En proceso está permitida).
    UPDATE Incidente
    SET fk_estado_incidente_id = (
        SELECT id_estado_incidente
        FROM EstadoIncidente
        WHERE nombre = 'En proceso'
    )
    WHERE id_incidente = NEW.fk_incidente_id
      AND fk_estado_incidente_id = (
          SELECT id_estado_incidente
          FROM EstadoIncidente
          WHERE nombre = 'Pendiente'
      );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_asignacion_aplicada ON Asignacion;
CREATE TRIGGER trg_asignacion_aplicada
AFTER INSERT ON Asignacion
FOR EACH ROW
EXECUTE FUNCTION fn_asignacion_aplicada();
-- =============================================================================================================
-- BLOQUE: GESTIÓN DE FINALIZACIÓN DE ASIGNACIONES (R8 + R4/R9 + R7)
-- =============================================================================================================
--
-- Este trigger unifica tres reglas de automatización que se activan cuando una asignación
-- cambia de estado (falla o finaliza). Las dos ramas son INDEPENDIENTES (no ELSIF) y cada
-- una está protegida por su propia condición de transición para garantizar terminación.
--
-- FLUJO DE EJECUCIÓN Y TERMINACIÓN:
--
--   Pasada 1 (usuario setea estado_exito = FALSE):
--     → Rama 1 activa  (OLD.estado_exito IS DISTINCT FROM FALSE AND NEW.estado_exito = FALSE)
--     → Rama 2 inactiva (NEW.timestamp_finalizacion sigue NULL, el usuario no lo tocó)
--     → Acciones: penalizar → reasignar → self-UPDATE timestamp_finalizacion
--
--   Pasada 2 (provocada por el self-UPDATE del paso c de Rama 1):
--     → Rama 1 inactiva (OLD.estado_exito = FALSE, la guarda ya no se cumple)
--     → Rama 2 activa  (OLD.timestamp_finalizacion IS NULL AND NEW.timestamp_finalizacion IS NOT NULL)
--     → Acciones: liberar recurso fallido a 'Disponible', evaluar cierre del incidente (R7)
--
--   Sin más updates a Asignacion → FIN.
--   La nueva asignación creada en 1b está abierta (timestamp_finalizacion IS NULL), por lo que
--   R7 no cierra el incidente prematuramente en la pasada 2. Correcta convergencia garantizada.
-- =============================================================================================================

CREATE OR REPLACE FUNCTION fn_asignacion_finalizada()
RETURNS TRIGGER AS $$
DECLARE
    v_id_tipo_penalizacion INT;
    v_id_estado_disponible INT;
    v_id_estado_resuelto   INT;
BEGIN
    -- -------------------------------------------------------------------------
    -- RAMA 1 — FALLA (R4/R9)
    -- Condición de transición: la asignación pasa a estado fallido por primera vez.
    -- Se ejecuta en la pasada 1 (usuario marca estado_exito = FALSE).
    -- NO libera el recurso ni evalúa cierre: esas acciones quedan para la Rama 2,
    -- que se dispara en la pasada 2 al cerrarse esta misma asignación (ver paso c).
    -- -------------------------------------------------------------------------
    IF OLD.estado_exito IS DISTINCT FROM FALSE AND NEW.estado_exito = FALSE THEN

        -- a) Registrar penalización al recurso fallido.
        SELECT id_tipo_penalizacion
        INTO v_id_tipo_penalizacion
        FROM TipoPenalizacion
        WHERE nombre = 'Falla en intervención';

        INSERT INTO Penalizacion (fk_recurso_id, fk_tipo_penalizacion_id, motivo)
        VALUES (
            NEW.fk_recurso_id,
            v_id_tipo_penalizacion,
            'Falla en intervención registrada en asignación #' || NEW.id_asignacion ||
            ' para el incidente #' || NEW.fk_incidente_id || '.'
        );

        -- b) Reasignar un recurso nuevo para el incidente.
        --    La asignación fallida aún está abierta (timestamp_finalizacion IS NULL),
        --    por lo que el motor de asignación NO reelige el recurso fallido (lo ve como ocupado).
        PERFORM fn_asignar_recursos_incidente(NEW.fk_incidente_id, 1);

        -- c) Cerrar la asignación fallida para liberar lógicamente al recurso.
        --    Este UPDATE re-dispara el trigger (pasada 2), pero con OLD.estado_exito = FALSE,
        --    por lo que la Rama 1 no vuelve a entrar. La Rama 2 toma el control en esa pasada.
        --    La guarda AND timestamp_finalizacion IS NULL garantiza idempotencia.
        UPDATE Asignacion
        SET timestamp_finalizacion = CURRENT_TIMESTAMP
        WHERE id_asignacion = NEW.id_asignacion
          AND timestamp_finalizacion IS NULL;

    END IF;

    -- -------------------------------------------------------------------------
    -- RAMA 2 — FINALIZACIÓN (R8 + R7)
    -- Condición de transición: la asignación se cierra (timestamp_finalizacion pasa de NULL a NOT NULL).
    -- Se ejecuta tanto en finalizaciones normales como en la pasada 2 del flujo de falla.
    -- -------------------------------------------------------------------------
    IF OLD.timestamp_finalizacion IS NULL AND NEW.timestamp_finalizacion IS NOT NULL THEN

        -- a) R8: Liberar el recurso, marcándolo como 'Disponible'.
        SELECT id_estado_recurso
        INTO v_id_estado_disponible
        FROM EstadoRecurso
        WHERE nombre = 'Disponible';

        UPDATE Recurso
        SET fk_estado_recurso_id = v_id_estado_disponible
        WHERE id_recurso = NEW.fk_recurso_id;

        -- b) R7: Si el incidente ya no tiene asignaciones abiertas Y al menos una fue exitosa,
        --    marcarlo como 'Resuelto' (solo si su estado actual lo permite).
        --    La nueva asignación generada por una reasignación está abierta, por lo que el NOT EXISTS
        --    falla y el incidente NO se cierra prematuramente.
        IF NOT EXISTS (
            SELECT 1
            FROM Asignacion
            WHERE fk_incidente_id = NEW.fk_incidente_id
              AND timestamp_finalizacion IS NULL
        )
        AND EXISTS (
            SELECT 1
            FROM Asignacion
            WHERE fk_incidente_id = NEW.fk_incidente_id
              AND estado_exito = TRUE
        )
        THEN
            SELECT id_estado_incidente
            INTO v_id_estado_resuelto
            FROM EstadoIncidente
            WHERE nombre = 'Resuelto';

            -- Actualizamos solo si el incidente no está ya en un estado terminal.
            -- Esto evita re-disparar R9 (que bloquea cambios desde 'Resuelto' o 'Cancelado').
            UPDATE Incidente
            SET fk_estado_incidente_id = v_id_estado_resuelto
            WHERE id_incidente = NEW.fk_incidente_id
              AND fk_estado_incidente_id NOT IN (
                  SELECT id_estado_incidente
                  FROM EstadoIncidente
                  WHERE nombre IN ('Resuelto', 'Cancelado')
              );
        END IF;

    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_asignacion_finalizada ON Asignacion;
CREATE TRIGGER trg_asignacion_finalizada
AFTER UPDATE ON Asignacion
FOR EACH ROW
EXECUTE FUNCTION fn_asignacion_finalizada();
-- ============================================================================
-- BLOQUE 3: AUDITORÍA GENÉRICA (R3) + CONFIABILIDAD DE SENSORES (R21)
-- ============================================================================
-- ============================================================================
-- 1. fn_confianza_sensor — R21 (valor derivado)
-- ============================================================================
--
-- Calcula la confianza de un sensor en base a la última fecha de mantenimiento.
-- Si no tiene mantenimientos registrados, se usa la fecha de instalación.
-- Confianza = GREATEST(100 - decaimiento_semanal * semanas_sin_mantenimiento, 0)
-- El parámetro de decaimiento viene de ParametrosSistema (COALESCE 5 si no existe).

CREATE OR REPLACE FUNCTION fn_confianza_sensor(p_sensor_id INT)
RETURNS NUMERIC AS $$
DECLARE
    v_base               DATE;
    v_decaimiento        NUMERIC;
    v_semanas            NUMERIC;
    v_confianza          NUMERIC;
BEGIN
    -- Base: última fecha de mantenimiento o, si no hay ninguna, fecha de instalación
    SELECT COALESCE(
        (SELECT MAX(fecha) FROM MantenimientoSensor WHERE fk_sensor_id = p_sensor_id),
        (SELECT fecha_instalado FROM Sensor WHERE id_sensor = p_sensor_id)
    ) INTO v_base;

    -- Decaimiento semanal configurado en ParametrosSistema (default 5 si no existe)
    SELECT COALESCE(
        (SELECT numero FROM ParametrosSistema WHERE nombre_parametro = 'SENSOR_DECAIMIENTO_CONFIANZA_SEMANAL'),
        5
    ) INTO v_decaimiento;

    -- Semanas transcurridas desde la base (CURRENT_DATE - base devuelve días como INT)
    v_semanas := floor((CURRENT_DATE - v_base) / 7);

    v_confianza := GREATEST(100 - v_decaimiento * v_semanas, 0);

    RETURN v_confianza;
END;
$$ LANGUAGE plpgsql;


-- ============================================================================
-- 2. fn_auditoria — R3 (auditoría genérica, un trigger por tabla)
-- ============================================================================
--
-- Recibe el nombre de la columna PK de cada tabla como TG_ARGV[0].
-- Extrae el valor de la PK desde el registro NEW o OLD según la operación.
-- El campo 'detalle' nunca es NULL:
--   INSERT -> to_jsonb(NEW)
--   UPDATE -> {'antes': OLD, 'despues': NEW}
--   DELETE -> to_jsonb(OLD)

CREATE OR REPLACE FUNCTION fn_auditoria()
RETURNS TRIGGER AS $$
DECLARE
    v_id_tabla  BIGINT;
    v_detalle   JSONB;
BEGIN
    -- Extraemos el valor de la PK usando el nombre pasado como argumento del trigger
    v_id_tabla := (to_jsonb(COALESCE(NEW, OLD)) ->> TG_ARGV[0])::bigint;

    -- Construimos el detalle según la operación
    IF TG_OP = 'INSERT' THEN
        v_detalle := to_jsonb(NEW);
    ELSIF TG_OP = 'UPDATE' THEN
        v_detalle := jsonb_build_object('antes', to_jsonb(OLD), 'despues', to_jsonb(NEW));
    ELSE
        -- DELETE
        v_detalle := to_jsonb(OLD);
    END IF;

    INSERT INTO Log (tablaAfectada, idTablaAfectada, operacion, trigger_disparador, detalle)
    VALUES (TG_TABLE_NAME, v_id_tabla, TG_OP, TG_NAME, v_detalle);

    -- AFTER trigger: el valor de retorno es ignorado por el motor,
    -- pero la convención del repo es retornar OLD en DELETE, NEW en el resto.
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ---- Incidente ----
DROP TRIGGER IF EXISTS trg_audit_incidente ON Incidente;
CREATE TRIGGER trg_audit_incidente
AFTER INSERT OR UPDATE OR DELETE ON Incidente
FOR EACH ROW
EXECUTE FUNCTION fn_auditoria('id_incidente');

-- ---- Asignacion ----
DROP TRIGGER IF EXISTS trg_audit_asignacion ON Asignacion;
CREATE TRIGGER trg_audit_asignacion
AFTER INSERT OR UPDATE OR DELETE ON Asignacion
FOR EACH ROW
EXECUTE FUNCTION fn_auditoria('id_asignacion');

-- ---- Recurso ----
DROP TRIGGER IF EXISTS trg_audit_recurso ON Recurso;
CREATE TRIGGER trg_audit_recurso
AFTER INSERT OR UPDATE OR DELETE ON Recurso
FOR EACH ROW
EXECUTE FUNCTION fn_auditoria('id_recurso');

-- ---- Penalizacion ----
DROP TRIGGER IF EXISTS trg_audit_penalizacion ON Penalizacion;
CREATE TRIGGER trg_audit_penalizacion
AFTER INSERT OR UPDATE OR DELETE ON Penalizacion
FOR EACH ROW
EXECUTE FUNCTION fn_auditoria('id_penalizacion');

-- ---- Evento ----
DROP TRIGGER IF EXISTS trg_audit_evento ON Evento;
CREATE TRIGGER trg_audit_evento
AFTER INSERT OR UPDATE OR DELETE ON Evento
FOR EACH ROW
EXECUTE FUNCTION fn_auditoria('id_evento');


-- ============================================================================
-- 3. fn_evento_promocion + trg_evento_promocion — R21
-- ============================================================================
--
-- Evalúa la confianza del sensor que generó el evento.
-- Si la confianza es <= umbral: registra en Log y NO crea incidente.
-- Si la confianza es > umbral y el evento tiene exactamente 1 mapeo
--   en TipoEventoTipoIncidente: intenta crear el incidente.
--   Si falla (ej. duplicado por otra regla): registra en Log gracefully.
-- Si hay 0 o >1 mapeos: registra en Log y NO crea incidente.
-- El evento SIEMPRE queda registrado, independientemente del resultado.

CREATE OR REPLACE FUNCTION fn_evento_promocion()
RETURNS TRIGGER AS $$
DECLARE
    v_confianza          NUMERIC;
    v_umbral             NUMERIC;
    v_cant_mapeos        INT;
    v_tipo_incidente_id  INT;
    v_gravedad_id        INT;
    v_zona_id            INT;
    v_estado_pendiente   INT;
BEGIN
    -- Calculamos la confianza del sensor que generó el evento
    v_confianza := fn_confianza_sensor(NEW.fk_sensor_id);

    -- Umbral mínimo desde ParametrosSistema (default 80 si no existe)
    SELECT COALESCE(
        (SELECT numero FROM ParametrosSistema WHERE nombre_parametro = 'SENSOR_UMBRAL_CONFIANZA_MINIMO'),
        80
    ) INTO v_umbral;

    -- -------------------------------------------------------------------------
    -- Sensor no confiable: registramos en Log y no promovemos
    -- -------------------------------------------------------------------------
    IF v_confianza <= v_umbral THEN
        INSERT INTO Log (tablaAfectada, idTablaAfectada, operacion, trigger_disparador, detalle)
        VALUES (
            'evento',
            NEW.id_evento,
            'INSERT',
            TG_NAME,
            jsonb_build_object(
                'confianza', v_confianza,
                'motivo',    'Evento de baja fiabilidad, no se promueve a incidente'
            )
        );
        RETURN NEW;
    END IF;

    -- -------------------------------------------------------------------------
    -- Sensor confiable: verificamos cuántos mapeos existen para el tipo de evento
    -- -------------------------------------------------------------------------
    SELECT count(*)
    INTO v_cant_mapeos
    FROM TipoEventoTipoIncidente
    WHERE fk_tipo_evento_id = NEW.fk_tipo_evento_id;

    IF v_cant_mapeos = 1 THEN
        -- Exactamente un mapeo: obtenemos tipo de incidente y gravedad
        SELECT fk_tipo_incidente_id, fk_gravedad_id
        INTO v_tipo_incidente_id, v_gravedad_id
        FROM TipoEventoTipoIncidente
        WHERE fk_tipo_evento_id = NEW.fk_tipo_evento_id;

        -- Zona del sensor que generó el evento
        SELECT fk_zona_id
        INTO v_zona_id
        FROM Sensor
        WHERE id_sensor = NEW.fk_sensor_id;

        -- Estado 'Pendiente' del catálogo
        SELECT id_estado_incidente
        INTO v_estado_pendiente
        FROM EstadoIncidente
        WHERE nombre = 'Pendiente';

        -- Insertamos el incidente de forma graceful:
        -- si otra regla lo rechaza (ej. duplicado por R11), registramos en Log
        -- y el evento queda igualmente guardado.
        BEGIN
            INSERT INTO Incidente (
                fk_evento_id,
                fk_tipo_incidente_id,
                fk_gravedad_id,
                fk_estado_incidente_id,
                fk_zona_id,
                descripcion,
                prioridad
            )
            VALUES (
                NEW.id_evento,
                v_tipo_incidente_id,
                v_gravedad_id,
                v_estado_pendiente,
                v_zona_id,
                'Incidente generado automáticamente a partir del evento #' || NEW.id_evento,
                v_gravedad_id   -- baseline/placeholder hasta R12
            );
        EXCEPTION WHEN OTHERS THEN
            INSERT INTO Log (tablaAfectada, idTablaAfectada, operacion, trigger_disparador, detalle)
            VALUES (
                'Evento',
                NEW.id_evento,
                'INSERT',
                TG_NAME,
                jsonb_build_object(
                    'motivo', 'No se pudo crear el incidente automático',
                    'error',  SQLERRM
                )
            );
        END;

    ELSE
        -- 0 o >1 mapeos: no es posible determinar un incidente unívoco
        INSERT INTO Log (tablaAfectada, idTablaAfectada, operacion, trigger_disparador, detalle)
        VALUES (
            'evento',
            NEW.id_evento,
            'INSERT',
            TG_NAME,
            jsonb_build_object(
                'cant_mapeos', v_cant_mapeos,
                'motivo',      'Evento no promovido: mapeo a tipo de incidente no es único'
            )
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_evento_promocion ON Evento;
CREATE TRIGGER trg_evento_promocion
AFTER INSERT ON Evento
FOR EACH ROW
EXECUTE FUNCTION fn_evento_promocion();
