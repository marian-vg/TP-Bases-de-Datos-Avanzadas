#!/bin/bash
# ============================================================================
# SMART CITY - ORQUESTADOR DE INICIALIZACIÓN PARA DOCKER
# ============================================================================
# Ejecutado por PostgreSQL una única vez, durante el primer arranque del
# contenedor (cuando el volumen de datos está vacío).
#
# Motivo de usar un .sh en lugar de scripts .sql sueltos:
#   1. Garantiza el orden de ejecución: estructura -> datos -> vistas. Los
#      archivos sueltos en docker-entrypoint-initdb.d se ejecutan por orden
#      alfabético, lo que rompe las dependencias entre scripts.
#   2. El 'cd /project' permite que las rutas relativas 'data/...' del comando
#      \copy en carga-dataset.sql resuelvan correctamente, sin necesidad de
#      modificar los scripts SQL.
#
# create-database.sql no se utiliza aquí: la base la crea PostgreSQL a partir
# de la variable POSTGRES_DB definida en docker-compose.yml.
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

echo ">>> Base de datos 'smart_city' inicializada correctamente."
