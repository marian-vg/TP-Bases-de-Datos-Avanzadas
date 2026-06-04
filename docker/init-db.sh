#!/bin/bash
# ============================================================================
# SMART CITY - ORQUESTADOR DE INICIALIZACIÓN PARA DOCKER
# ============================================================================
# Ejecutado por PostgreSQL una única vez, durante el primer arranque del
# contenedor (cuando el volumen de datos está vacío).
#
# Motivo de usar un .sh en lugar de scripts .sql sueltos:
#   1. Garantiza el orden de ejecución: estructura -> datos -> vistas -> triggers. Los
#      archivos sueltos en docker-entrypoint-initdb.d se ejecutan por orden
#      alfabético, lo que rompe las dependencias entre scripts.
#   2. El 'cd /project' permite que las rutas relativas 'data/...' del comando
#      \copy en carga-dataset.sql resuelvan correctamente, sin necesidad de
#      modificar los scripts SQL.
#
# create-database.sql no se utiliza aquí: la base la crea PostgreSQL a partir
# de la variable POSTGRES_DB definida en docker-compose.yml. Solo se usa si 
# el usuario que quiera ejecutar la DB no tiene acceso a docker.
# ============================================================================

set -e  # Aborta ante el primer comando con error; evita cargas a medias.

cd /project

run() {
  echo ">>> Ejecutando: $1"
  # ON_ERROR_STOP=1: ante un fallo en una sentencia SQL, psql aborta y retorna
  # error. Sin esta opción los errores se ignoran de forma silenciosa.
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f "$1"
}

run database/create-tables.sql
run database/carga-dataset.sql
run database/create-views.sql

# Reglas activas en módulos. ORDEN IMPORTANTE:
#   validadoras  -> validaciones BEFORE (R8/R9/R10/R11 + tipo aplicable)
#   inteligencia -> mantiene Recurso.puntaje (R14); DEBE ir antes del motor
#   automatizacion -> motor de asignación y ciclo operativo; ordena por ese puntaje
#   temporales   -> reglas temporales R16/R17 (procedures para cron/manual)
#
# database/create-triggers.sql NO se carga a propósito: es un script de REFERENCIA generado
# con IA que no respeta las reglas del proyecto. Se conserva solo a mano. Las reglas que vivían
# ahí ya están implementadas en módulos (R12/R13/R15 en inteligencia, R20 en automatizacion).
run database/triggers/reglas-validadoras.sql
run database/triggers/reglas-inteligencia.sql
run database/triggers/reglas-automatizacion.sql
run database/triggers/reglas-temporales.sql
run database/store-procedures/asignar-recurso.sql

echo ">>> Base de datos 'smart_city' inicializada correctamente."
