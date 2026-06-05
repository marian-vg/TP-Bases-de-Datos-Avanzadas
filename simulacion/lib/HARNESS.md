# Harness de simulacion

Este archivo acompaña a `harness.sql` y resume para qué existe dentro de la simulacion.

## Que es

El harness es la base tecnica de toda la suite.

No forma parte del motor productivo de Smart City. No agrega reglas de negocio, no cambia triggers reales y no corrige el sistema por adentro. Su funcion es darle a la simulacion una estructura ordenada, repetible y facil de seguir.

En otras palabras, evita que la simulacion quede reducida a una serie de `INSERT`, `UPDATE` y consultas sueltas revisadas manualmente.

## Para que sirve

El harness resuelve cinco necesidades concretas:

1. Registrar resultados.
   Cada escenario puede dejar un `PASS`, `FAIL`, `XFAIL`, `XPASS`, `SKIP` o `INFO` con un detalle claro.

2. Medir lo que paso.
   Guarda metricas como cantidad de incidentes creados, asignaciones, fallas inducidas o recursos rebalanceados.

3. Resetear el entorno entre escenarios.
   Limpia incidentes, eventos, asignaciones y penalizaciones creadas durante la corrida, y restaura parametros, puntajes, zonas y relaciones operativas al estado base de la transaccion.

4. Evitar IDs magicos.
   En vez de asumir valores como "estado 3" o "gravedad 2", busca catalogos por nombre. Eso hace que la simulacion sea mas robusta y mas honesta respecto al estado real de la base.

5. Preparar el reporte final.
   Toda la informacion que despues muestra `09_reporte_operativo.sql` sale de las tablas y helpers temporales creados aca.

## Que crea

El harness crea tablas temporales y funciones temporales en `pg_temp`.

Las tablas temporales principales son:

- `sim_resultado`: guarda el resultado de cada prueba.
- `sim_metrica`: guarda metricas numericas.
- `sim_cobertura`: mantiene la matriz R1-R21 y P1-P5.
- tablas base de snapshot: guardan el estado inicial de parametros, recursos, zonas, relaciones y secuencias.

Las funciones mas importantes son:

- `sim_registrar`: registra una fila manualmente en resultados.
- `sim_afirmar`: registra `PASS` o `FAIL` segun una condicion.
- `sim_brecha`: registra `XFAIL` o `XPASS` para capacidades ausentes o parciales.
- `sim_medir`: guarda una metrica.
- `sim_reset_operativo`: limpia y restaura el entorno entre escenarios.
- `sim_restaurar_secuencias`: devuelve las secuencias al valor original antes del `ROLLBACK`.
- `sim_id_catalogo`: busca IDs de catalogo por nombre.
- `sim_regclass` y `sim_relacion_existe`: ayudan a resolver nombres reales de tablas y vistas sin depender de un casing fragil.

## Como encaja en la corrida

El flujo general es este:

1. `00_run_all.sql` abre una transaccion.
2. Incluye `lib/harness.sql`.
3. El harness toma snapshots del estado base.
4. Cada escenario usa sus helpers para probar un comportamiento.
5. `09_reporte_operativo.sql` lee los resultados acumulados.
6. Al final se restauran secuencias y se hace `ROLLBACK`.

La idea es simple: la simulacion puede trabajar con libertad dentro de la transaccion, pero sin dejar cambios persistidos al terminar.

## Que no hace

Tambien conviene dejar claro lo que no hace:

- No implementa reglas faltantes del TP.
- No inventa triggers, procedimientos o vistas productivas.
- No arregla el motor en secreto para que la demo quede linda.
- No garantiza concurrencia real entre sesiones.

Si una capacidad no existe en el motor, el harness no la fabrica. Solo ayuda a que esa ausencia quede registrada de forma clara como `XFAIL` o `SKIP`, en lugar de romper toda la corrida.

## Por que era necesario

Sin este archivo, la simulacion quedaba bastante mas fragil:

- dependia de IDs fijos,
- mezclaba escenarios entre si,
- dejaba mas margen para interpretar resultados manualmente,
- y hacia mas dificil distinguir un error tecnico de una brecha real del motor.

Con el harness, la suite gana orden, aislamiento, trazabilidad y un reporte final bastante mas defendible.

## Idea corta

Si hubiera que resumirlo en una frase:

> el harness no es parte del sistema Smart City; es la estructura que permite probarlo bien y mostrar con claridad que funciono, que fallo y que sigue faltando.
