-- ============================================================================
-- REGLAS DE AUDITORÍA Y CONTROL
-- ============================================================================
-- R18/R19 se implementan en reglas-automatizacion.sql mediante fn_registrar_decision
-- y fn_auditoria. R20 queda centralizada en fn_asignacion_automatica usando
-- Zona.umbral_incidentes_activos (DD-14), no un umbral global en ParametrosSistema.
--
-- Este archivo se mantiene porque main carga reglas mediante create-triggers.sql.
-- Si una versión anterior creó el control global, lo desinstala idempotentemente.
-- ============================================================================

DROP TRIGGER IF EXISTS trg_control_capacidad ON Incidente;
DROP FUNCTION IF EXISTS fn_control_capacidad();
