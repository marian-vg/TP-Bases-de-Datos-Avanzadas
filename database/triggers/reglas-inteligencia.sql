-- =============================================================================================================
-- REGLAS DE INTELIGENCIA — Smart City (PostgreSQL 16)
-- =============================================================================================================
--
-- Implementación de R14 (Selección del mejor recurso) mediante un PUNTAJE de desempeño
-- materializado en Recurso.puntaje. La selección del mejor recurso NO se calcula al asignar
-- (sería caro recorrer historial en cada incidente): el puntaje se mantiene precalculado por
-- los triggers de este archivo, y el motor de asignación (reglas-automatizacion.sql) solo
-- tiene que ordenar por ese campo ya listo.
--
-- SEPARACIÓN DE CAPAS:
--   Este archivo NO conoce ni invoca al motor de automatización. Reacciona a HECHOS que ya
--   ocurrieron en las tablas base (una asignación marcada exitosa, una penalización insertada),
--   sin importar qué regla los provocó. Los triggers se encadenan a través de las tablas, no
--   por llamadas directas: cuando R4 (reglas-automatizacion.sql) inserta en Penalizacion, el
--   trigger de resta de puntaje de acá se dispara solo.
--
-- FÓRMULA DEL PUNTAJE:
--   + 1               por cada asignación marcada exitosa (estado_exito -> TRUE).
--   + 1 extra         cada vez que el recurso completa una racha de 3 éxitos consecutivos
--                     (en el 3.º, 6.º, 9.º… éxito seguido; una falla reinicia la cuenta).
--   + id_gravedad     si la asignación exitosa cumplió el SLA: llegó dentro del tiempo de
--                     respuesta pactado para la gravedad del incidente (Baja=+1 … Catastrófica=+5).
--   - TipoPenalizacion.puntaje   por cada penalización registrada (escala 1 a 5).
--   Los fracasos NO restan acá: ya conllevan una penalización que descuenta por su cuenta.
--
-- Orden de carga: create-tables.sql -> carga-dataset.sql -> reglas-validadoras.sql ->
--                 reglas-inteligencia.sql -> reglas-automatizacion.sql
--                 (la columna Recurso.puntaje la crea create-tables; el dataset base no trae
--                  historial operativo, así que todos los recursos arrancan en 0).
--
-- Nota de auditoría: cada cambio de puntaje hace UPDATE Recurso, que dispara trg_audit_recurso
-- (R3) y deja una fila en Log. Es ruido esperado y aceptable: el puntaje es trazable.
-- Convención: funciones fn_*, triggers trg_*; idempotente (CREATE OR REPLACE + DROP TRIGGER IF EXISTS).
-- =============================================================================================================


-- =============================================================================================================
-- 1. fn_puntaje_por_penalizacion / trg_puntaje_por_penalizacion — R14 (resta)
-- =============================================================================================================
--
-- Al registrarse una penalización, descuenta del recurso los puntos definidos en el tipo de
-- penalización (TipoPenalizacion.puntaje, escala 1 a 5). El puntaje puede quedar negativo:
-- es deseable, porque hunde a los recursos problemáticos al fondo del ranking de R14.

CREATE OR REPLACE FUNCTION fn_puntaje_por_penalizacion()
RETURNS TRIGGER AS $$
DECLARE
    v_resta INT;
BEGIN
    SELECT COALESCE(puntaje, 0)
    INTO v_resta
    FROM TipoPenalizacion
    WHERE id_tipo_penalizacion = NEW.fk_tipo_penalizacion_id;

    UPDATE Recurso
    SET puntaje = puntaje - v_resta
    WHERE id_recurso = NEW.fk_recurso_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_puntaje_por_penalizacion ON Penalizacion;
CREATE TRIGGER trg_puntaje_por_penalizacion
AFTER INSERT ON Penalizacion
FOR EACH ROW
EXECUTE FUNCTION fn_puntaje_por_penalizacion();


-- =============================================================================================================
-- 2. fn_puntaje_por_exito / trg_puntaje_por_exito — R14 (suma: éxito + racha + SLA)
-- =============================================================================================================
--
-- Se dispara SOLO en la transición estado_exito -> TRUE. Es deliberado: la Rama 1 de
-- fn_asignacion_finalizada (R4) cierra las asignaciones FALLIDAS seteando timestamp_finalizacion,
-- así que gatillar por la finalización premiaría a un fracaso. Gatillando por el éxito, un fallo
-- nunca entra acá, aunque haya llegado dentro del SLA.
--
-- En el momento del éxito suma, en un único UPDATE:
--   a) +1 base.
--   b) +1 de racha si la cantidad de éxitos consecutivos del recurso es múltiplo de 3.
--   c) + id_gravedad si la asignación cumplió el SLA (requiere timestamp_llegada cargado).

CREATE OR REPLACE FUNCTION fn_puntaje_por_exito()
RETURNS TRIGGER AS $$
DECLARE
    v_racha        INT;
    v_bonus_racha  INT := 0;
    v_bonus_sla    INT := 0;
    v_gravedad     INT;
    v_sla_minutos  INT;
    v_minutos      NUMERIC;
BEGIN
    IF OLD.estado_exito IS DISTINCT FROM TRUE AND NEW.estado_exito = TRUE THEN

        -- b) Racha: cuántos éxitos consecutivos lleva el recurso. Como el motor nunca le da una
        --    asignación nueva mientras tenga otra abierta, las asignaciones de un recurso son
        --    secuenciales y el id_asignacion refleja su orden. Contamos los éxitos posteriores
        --    a su último fallo; la fila recién marcada (NEW) ya es visible y entra en la cuenta.
        SELECT count(*)
        INTO v_racha
        FROM Asignacion
        WHERE fk_recurso_id = NEW.fk_recurso_id
          AND estado_exito = TRUE
          AND id_asignacion > COALESCE(
              (SELECT max(id_asignacion)
               FROM Asignacion
               WHERE fk_recurso_id = NEW.fk_recurso_id
                 AND estado_exito = FALSE),
              0
          );

        IF v_racha > 0 AND (v_racha % 3) = 0 THEN
            v_bonus_racha := 1;
        END IF;

        -- c) SLA: solo si el operador cargó la llegada. Comparamos el tiempo de respuesta real
        --    (asignación -> llegada) contra el SLA pactado para la gravedad del incidente.
        SELECT i.fk_gravedad_id, s.tiempo_respuesta_minutos
        INTO v_gravedad, v_sla_minutos
        FROM Incidente i
        JOIN SLA s ON s.fk_gravedad_id = i.fk_gravedad_id
        WHERE i.id_incidente = NEW.fk_incidente_id;

        IF NEW.timestamp_llegada IS NOT NULL AND v_sla_minutos IS NOT NULL THEN
            v_minutos := EXTRACT(EPOCH FROM (NEW.timestamp_llegada - NEW.timestamp_asignacion)) / 60;
            IF v_minutos <= v_sla_minutos THEN
                v_bonus_sla := v_gravedad;   -- a mayor gravedad atendida a tiempo, mayor premio
            END IF;
        END IF;

        -- a) +1 base, más los bonus calculados. Un solo UPDATE.
        UPDATE Recurso
        SET puntaje = puntaje + 1 + v_bonus_racha + v_bonus_sla
        WHERE id_recurso = NEW.fk_recurso_id;

    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_puntaje_por_exito ON Asignacion;
CREATE TRIGGER trg_puntaje_por_exito
AFTER UPDATE ON Asignacion
FOR EACH ROW
EXECUTE FUNCTION fn_puntaje_por_exito();
