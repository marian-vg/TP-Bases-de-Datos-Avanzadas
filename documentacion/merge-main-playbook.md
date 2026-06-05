# Merge con `main`: conflictos previsibles y resolución rápida

Este documento resume los conflictos que ya aparecieron al actualizar `dev/simulacion` desde `main` y deja una guía corta para resolverlos rápido sin romper la rama.

## Criterio general

- Priorizar compatibilidad estructural con `main`.
- Preservar la batería de simulación agregada en `dev/simulacion`.
- Cuando haya diferencias entre "script que define comportamiento real" y "archivo accesorio", cuidar primero el script ejecutable.
- Si un conflicto toca carga de dataset, Docker o migración, no resolver "Accept Current" o "Accept Incoming" a ciegas.

## Conflictos previsibles

### 1. `docker/init-db.sh`

Qué puede pasar:
- `main` puede venir con una versión más corta del inicializador.
- `dev/simulacion` agrega carga explícita de triggers y stored procedures.

Error esperable si se resuelve mal:
- La base levanta, pero faltan reglas activas.
- No se cargan `reglas-validadoras`, `reglas-inteligencia`, `reglas-automatizacion`, `reglas-temporales` o procedimientos usados por pruebas y simulaciones.

Qué hacer:
- Mantener la secuencia de `dev/simulacion` que carga módulos.
- Conservar también los procedures nuevos de `main`:
  - `database/store-procedures/cerrar-incidente.sql`
  - `database/store-procedures/simular-eventos.sql`

Resolución rápida:
- Dejar `run database/create-tables.sql`, `run database/carga-dataset.sql`, `run database/create-views.sql`.
- Después cargar:
  - `run database/triggers/reglas-validadoras.sql`
  - `run database/triggers/reglas-inteligencia.sql`
  - `run database/triggers/reglas-automatizacion.sql`
  - `run database/triggers/reglas-temporales.sql`
  - `run database/store-procedures/asignar-recurso.sql`
  - `run database/store-procedures/cerrar-incidente.sql`
  - `run database/store-procedures/simular-eventos.sql`

### 2. `migrate.sql`

Qué puede pasar:
- `main` agrega procedures nuevos.
- `dev/simulacion` conserva el orden correcto de carga de reglas activas.

Error esperable si se resuelve mal:
- La migración termina sin cargar parte de la lógica operativa.
- O bien quedan fuera los procedures nuevos de `main`.

Qué hacer:
- Mantener el bloque de reglas activas de `dev/simulacion`.
- Sumar al final los procedures nuevos de `main`.

Resolución rápida:
- Conservar:
  - `\ir database/triggers/reglas-validadoras.sql`
  - `\ir database/triggers/reglas-inteligencia.sql`
  - `\ir database/triggers/reglas-automatizacion.sql`
  - `\ir database/triggers/reglas-temporales.sql`
  - `\ir database/store-procedures/asignar-recurso.sql`
- Agregar:
  - `\ir database/store-procedures/cerrar-incidente.sql`
  - `\ir database/store-procedures/simular-eventos.sql`

### 3. `data/04_sla.csv`

Qué puede pasar:
- `main` puede traer un CSV viejo o simplificado sin la columna `minutos_por_punto_demora`.

Error esperable si se resuelve mal:
- Falla `\copy` en `database/carga-dataset.sql`.
- La tabla `SLA` queda incompatible con el dataset.
- Se rompe la lógica de penalización proporcional por demora.

Qué hacer:
- Mantener la versión con cuatro columnas:
  - `id`
  - `gravedad_id`
  - `tiempo_respuesta_minutos`
  - `minutos_por_punto_demora`

Resolución rápida:
- Si el conflicto ofrece una versión de tres columnas y otra de cuatro, dejar la de cuatro.

### 4. `data/15_parametros_sistema.csv`

Qué puede pasar:
- `main` puede agregar parámetros nuevos.
- `dev/simulacion` puede tener más parámetros usados por reglas temporales o simulación.

Error esperable si se resuelve mal:
- No explota siempre al migrar, pero reglas como R20 o automatizaciones pueden quedar con defaults inesperados o sin configuración.

Qué hacer:
- Unir filas, no elegir una rama completa.
- Verificar especialmente que exista `UMBRAL_INCIDENTES_ACTIVOS`.

Resolución rápida:
- Mantener todos los parámetros existentes de `dev/simulacion`.
- Sumar cualquier parámetro nuevo de `main` que no esté repetido.

### 5. `database/triggers/reglas-temporales.sql`

Qué puede pasar:
- `main` y `dev/simulacion` pueden divergir en la lógica de `sp_ReactivarRecursos`.

Error esperable si se resuelve mal:
- Reactivación incorrecta de recursos.
- Recursos que no se reactivan nunca o que se reactivan por un log no representativo.

Qué hacer:
- Mantener la lógica de `dev/simulacion` basada en el `MAX(timestamp)` del último paso real a estado `Fuera de servicio`.
- Esa variante es más estable cuando existen updates posteriores no relacionados.

Resolución rápida:
- Si el conflicto enfrenta `MAX(timestamp)` contra "tomar solo el último log del recurso", dejar `MAX(timestamp)` filtrado por transición a `Fuera de servicio`.

### 6. `simulacion/08_simulacion_20_incidentes.sql`

Qué puede pasar:
- `main` puede borrar el archivo aunque el runner de simulación todavía lo invoque.

Error esperable si se resuelve mal:
- `simulacion/00_run_all.sql` falla al ejecutar el escenario 08.
- La suite de simulación queda incompleta.

Qué hacer:
- Mantener el archivo mientras siga referenciado por:
  - `simulacion/00_run_all.sql`
  - `simulacion/README.md`

Resolución rápida:
- Si aparece como `deleted by them`, conservar la versión de `dev/simulacion` y marcarla como resuelta.

### 7. `database/triggers/reglas-validadoras.sql`

Qué puede pasar:
- `main` puede borrar este archivo aunque `migrate.sql`, `docker/init-db.sh`, tests y simulaciones todavía lo referencian.

Error esperable si se resuelve mal:
- La migración falla por archivo inexistente.
- O bien la base carga sin validaciones R8/R9/R10/R11 si se eliminan también las referencias.

Qué hacer:
- Mantener `database/triggers/reglas-validadoras.sql` mientras existan referencias activas en scripts, tests o simulaciones.

Resolución rápida:
- Si el conflicto lo deja como borrado en una rama y vivo en la otra, conservar el archivo.
- Después confirmar que siga siendo invocado desde `migrate.sql` y `docker/init-db.sh`.

### 8. Esquema y dataset de tablas puente (`TipoIncidenteTipoRecurso`, `TipoEventoTipoIncidente`, `MantenimientoSensor`)

Qué puede pasar:
- `main` puede traer una versión reducida de `database/create-tables.sql` o `database/carga-dataset.sql` que omite estas tablas o sus cargas.

Error esperable si se resuelve mal:
- Fallan tests y simulaciones que usan:
  - `TipoIncidenteTipoRecurso`
  - `TipoEventoTipoIncidente`
  - `MantenimientoSensor`
- También puede fallar la lógica de:
  - asignación compatible por tipo
  - promoción automática desde sensores
  - confianza de sensores

Qué hacer:
- Verificar que `database/create-tables.sql` siga creando esas tres tablas.
- Verificar que `database/carga-dataset.sql` siga cargando:
  - `data/16_tipo_incidente_tipo_recurso.csv`
  - `data/17_tipo_evento_tipo_incidente.csv`
- Si `Sensor` guarda `fecha_mantenimiento`, poblar además `MantenimientoSensor` a partir de esa columna.

Resolución rápida:
- No aceptar una versión de `create-tables.sql` que elimine esas tablas si el resto del repo todavía las usa.
- No aceptar una versión de `carga-dataset.sql` que deje de cargar `16` y `17`.

## Checklist después de cada merge desde `main`

1. Ejecutar `git diff --name-only --diff-filter=U` y revisar primero archivos de `database/`, `docker/` y `simulacion/`.
2. Buscar marcadores pendientes con `rg -n "<<<<<<<|=======|>>>>>>>"`.
3. Confirmar que `migrate.sql` y `docker/init-db.sh` incluyan todos los módulos activos y procedures nuevos.
4. Confirmar que `data/04_sla.csv` siga con `minutos_por_punto_demora`.
5. Confirmar que `data/15_parametros_sistema.csv` incluya `UMBRAL_INCIDENTES_ACTIVOS`.
6. Confirmar que `database/triggers/reglas-validadoras.sql` siga existiendo y siendo cargado.
7. Confirmar que `database/create-tables.sql` siga creando `TipoIncidenteTipoRecurso`, `TipoEventoTipoIncidente` y `MantenimientoSensor`.
8. Confirmar que `database/carga-dataset.sql` siga cargando `data/16_tipo_incidente_tipo_recurso.csv` y `data/17_tipo_evento_tipo_incidente.csv`.
9. Confirmar que `simulacion/00_run_all.sql` siga apuntando a archivos que existen.

## Decisión tomada en este merge

Para este merge se resolvió así:

- Se mantuvo la infraestructura activa de `dev/simulacion`.
- Se incorporaron los procedures nuevos de `main` en `migrate.sql` y `docker/init-db.sh`.
- Se preservó el escenario `simulacion/08_simulacion_20_incidentes.sql`.
- Se mantuvo el dataset de `SLA` compatible con el esquema actual.
- Se incorporó `UMBRAL_INCIDENTES_ACTIVOS` al CSV de parámetros.
