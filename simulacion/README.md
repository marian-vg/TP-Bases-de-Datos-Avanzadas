# Simulacion profesional Smart City

Esta carpeta contiene una suite transaccional para demostrar el comportamiento real del
sistema de emergencias. Reemplaza las demostraciones manuales anteriores por escenarios
con aserciones, metricas, cobertura y un reporte final.

## Objetivo

La consigna pide demostrar casos basicos, intermedios, avanzados y un minimo de veinte
incidentes simultaneos. La suite verifica esos flujos sin ocultar capacidades ausentes:

- `PASS`: el comportamiento requerido fue observado.
- `FAIL`: ocurrio una regresion o un resultado inesperado.
- `XFAIL`: se demostro una brecha conocida del motor actual.
- `XPASS`: una capacidad considerada ausente aparecio funcionando y debe revisarse.
- `SKIP`: no pudo ejecutarse la prueba porque falta una dependencia.
- `INFO`: diagnostico sin criterio de aprobacion.

Solo `FAIL` provoca un codigo de salida no exitoso.

## Ejecucion

Requisitos:

- PostgreSQL 16 inicializado mediante la migracion canonica del proyecto.
- `psql` disponible.
- Una base de desarrollo sin trafico concurrente.

Desde la raiz del repositorio:

```powershell
$env:PGPASSWORD="password"
psql -v ON_ERROR_STOP=1 -h localhost -p 5433 -U postgres -d smart_city -f simulacion/00_run_all.sql
```

El runner abre una transaccion, toma snapshots temporales, ejecuta todos los escenarios,
imprime el reporte y termina con `ROLLBACK`. Ningun incidente, recurso, parametro,
puntaje, permiso de zona o log generado por la simulacion queda persistido.

Durante la corrida se modifican filas y se toman locks dentro de la sesion. Por eso no debe
ejecutarse sobre una base compartida con usuarios activos.

## Arquitectura

El flujo funcional evaluado es:

```text
Sensor -> Evento -> Incidente -> Asignacion -> Intervencion -> Resolucion
                         |              |
                         |              +-> falla -> penalizacion -> reasignacion
                         +-> prioridad, capacidad, SLA y rebalanceo
```

`lib/harness.sql` crea tablas y funciones temporales para resultados, metricas, cobertura,
resolucion dinamica de catalogos y restauracion entre escenarios. Los scripts numerados se
incluyen desde `00_run_all.sql`; el reporte se imprime antes del rollback.

## Escenarios

| Archivo | Demostracion |
| --- | --- |
| `01_preflight.sql` | Dataset, vistas, triggers, funciones y procedimientos instalados |
| `02_asignacion_inteligencia.sql` | Asignacion, estados, prioridad, compatibilidad y mejor recurso |
| `03_ciclo_vida.sql` | Exito, cierre, liberacion, falla, penalizacion y reasignacion |
| `04_validaciones.sql` | Disponibilidad, tipo, zona, estados y duplicados |
| `05_sensores_iot.sql` | Confianza, promocion, rechazo, ambiguedad y duplicados IoT |
| `06_saturacion_rebalanceo.sql` | Agotamiento local, rebalanceo y umbral de capacidad |
| `07_brechas_conocidas.sql` | Capacidades requeridas pero ausentes o no cargadas |
| `08_simulacion_20_incidentes.sql` | Rafaga deterministica de veinte incidentes |
| `09_reporte_operativo.sql` | Veredicto, cobertura, SLA, ranking, auditoria y brechas |

La rafaga obligatoria usa un unico `INSERT` de veinte filas con pares tipo/zona unicos.
Esto representa simultaneidad logica y ejercita triggers fila a fila. No reemplaza una
prueba de concurrencia real con dos conexiones.

## Auditoria del repositorio

La revision comparo la consigna, migracion, Docker, esquema, dataset, reglas modulares,
procedimientos, vistas, tests y simulaciones anteriores.

Hallazgos principales:

- Las simulaciones anteriores borraban globalmente datos, usaban IDs magicos y no fallaban
  cuando el resultado era incorrecto.
- Algunas esperaban el estado `En transito`, aunque el motor modular marca el recurso
  directamente como `Ocupado`.
- Tener un archivo SQL no implica que la migracion canonica lo instale.
- `reglas-temporales.sql` contiene R16/R17, pero la migracion actual no lo incluye.
- `reglas-auditoriaYcontrol.sql` contiene R20, pero tampoco se incluye.
- Existe P1 y se carga. P2 existe en un archivo no cargado. P3, P4 y P5 no existen.
- R6 no esta implementada.
- La penalizacion automatica por demora y el bloqueo por acumulacion de penalizaciones no
  estan implementados en los modulos cargados.
- Algunos comentarios y tests todavia describen R12, R13 y R15 como pendientes, aunque
  actualmente poseen implementacion modular.

## Estado esperado de cobertura

La matriz final se calcula contra los objetos realmente instalados y la evidencia de la
corrida. En la migracion actual se esperan brechas visibles para:

- R6: generacion de incidentes relacionados.
- R16/R17: codigo existente pero no cargado.
- R20: codigo existente pero no cargado.
- P2: codigo existente pero no cargado.
- P3/P4/P5: procedimientos ausentes.
- Penalizacion automatica por demora.
- Bloqueo automatico por penalizaciones acumuladas.

Estas brechas se reportan como `XFAIL`; no se implementan dentro de la simulacion porque
eso produciria una demostracion engañosa del motor.

## Lectura del reporte

Para una defensa oral, leer el reporte en este orden:

1. Veredicto general y resumen de aserciones.
2. Matriz R1-R21 / P1-P5.
3. Metricas del lote de veinte incidentes.
4. Estado final, SLA y ranking de recursos.
5. Auditoria de triggers.
6. Brechas conocidas.

Un resultado `PASS CON BRECHAS CONOCIDAS` significa que la suite se ejecuto correctamente,
las capacidades implementadas respondieron como se esperaba y las ausencias conocidas
quedaron demostradas de forma honesta.
