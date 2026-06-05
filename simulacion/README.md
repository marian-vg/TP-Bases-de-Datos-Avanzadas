# Simulacion profesional Smart City

Esta carpeta contiene la suite transaccional usada para mostrar el comportamiento real del
sistema de emergencias.

La idea de fondo es simple: dejar atras las simulaciones manuales y pasar a una corrida
ordenada, con aserciones, metricas, cobertura y un reporte final que permita ver con
claridad que funciona y que decisiones de alcance se tomaron.

## Objetivo

La consigna pide demostrar casos basicos, intermedios, avanzados y un minimo de veinte
incidentes simultaneos. Esta suite cubre esos flujos respetando las decisiones de diseno del equipo:

- `PASS`: el comportamiento requerido fue observado.
- `FAIL`: ocurrio una regresion o un resultado inesperado.

Solo `FAIL` representa una regresion o error inesperado. La corrida esperada del dataset
canonico queda completa en `PASS`; las decisiones de alcance del equipo tambien se validan
como `PASS` cuando el comportamiento observado coincide con el diseno adoptado.

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
imprime el reporte y termina con `ROLLBACK`.

Eso significa que ningun incidente, recurso, parametro, umbral por zona, puntaje, permiso
de zona, log ni avance de secuencia generado por la simulacion queda persistido. Las
secuencias se restauran en forma explicita porque PostgreSQL no las revierte
automaticamente con `ROLLBACK`.

Durante la corrida se modifican filas y se toman locks dentro de la sesion. Por eso no debe
ejecutarse sobre una base compartida con usuarios activos.

## Arquitectura

El flujo funcional evaluado es:

```text
Sensor -> Evento -> Incidente -> Asignacion -> En transito -> Ocupado -> Resolucion
                         |              |             |
                         |              |             +-> demora -> penalizacion proporcional
                         |              +-> falla -> penalizacion -> reasignacion
                         +-> prioridad, capacidad por zona, SLA y rebalanceo
```

`lib/harness.sql` crea las tablas y funciones temporales que sostienen toda la corrida:
resultados, metricas, cobertura, resolucion dinamica de catalogos y restauracion entre
escenarios. Los scripts numerados se incluyen desde `00_run_all.sql`; el reporte se imprime
antes del rollback.

## Escenarios

| Archivo | Demostracion |
| --- | --- |
| `01_preflight.sql` | Dataset, vistas, triggers, funciones y procedimientos instalados |
| `02_asignacion_inteligencia.sql` | Asignacion, estados, prioridad, compatibilidad y mejor recurso |
| `03_ciclo_vida.sql` | Exito, cierre, liberacion, falla, penalizacion y reasignacion |
| `04_validaciones.sql` | Disponibilidad, tipo, zona, estados y duplicados |
| `05_sensores_iot.sql` | Confianza, promocion, rechazo, ambiguedad y duplicados IoT |
| `06_saturacion_rebalanceo.sql` | Agotamiento local, recurso externo, ciclo completo y capacidad por zona |
| `07_capacidades_avanzadas.sql` | SLA, escalamiento, reactivacion, arribo, penalizacion proporcional, P1, P3, P5 y R6 |
| `08_simulacion_20_incidentes.sql` | Rafaga deterministica de veinte incidentes |
| `09_reporte_operativo.sql` | Veredicto, cobertura, SLA, ranking, auditoria y observaciones |

La rafaga obligatoria usa un unico `INSERT` de veinte filas con pares tipo/zona unicos.
Eso representa simultaneidad logica y ejercita triggers fila a fila. No reemplaza una
prueba de concurrencia real con dos conexiones.

## Auditoria del repositorio

La revision comparo la consigna, la migracion, Docker, el esquema, el dataset, las reglas
modulares, los procedimientos, las vistas, los tests y las simulaciones anteriores.

Los hallazgos principales fueron estos:

- Las simulaciones anteriores borraban globalmente datos, usaban IDs magicos y no fallaban
  cuando el resultado era incorrecto.
- El motor integrado representa el ciclo operativo completo:
  `Disponible -> En transito -> Ocupado -> Disponible`.
- Tener un archivo SQL no implica que la migracion canonica lo instale.
- `reglas-temporales.sql` se carga y permite validar R16/P2 y R17.
- R20 controla la capacidad mediante un umbral propio de cada zona.
- P4 calcula penalizaciones proporcionales por exceso sobre el SLA.
- P1 se conserva y se prueba mediante una asignacion diferida.
- P3 se valida cerrando un incidente real, finalizando asignaciones y liberando recursos.
- P5 se valida simulando un evento de sensor confiable que genera un incidente automatico.
- R6 se valida con el mapeo `TipoEventoTipoIncidente`: el incidente generado queda relacionado al evento que lo origino.
- El bloqueo por acumulacion de penalizaciones no esta implementado en los modulos cargados.
- R18 registra varias decisiones centrales, pero no cada accion de todas las reglas activas.
- R19 ofrece historial de auditoria y decisiones, pero no registra cada ejecucion de trigger.
- R20 usa `Pendiente` como espera operativa porque el catalogo no contiene `En espera`.
- R16 y R17 funcionan al invocar sus procedimientos, pero no incluyen un planificador temporal.

## Estado esperado de cobertura

La matriz final se calcula contra los objetos realmente instalados y la evidencia de la
corrida. La suite demuestra el mecanismo funcional de R6, R16, R17, R20, P1, P2, P3, P4 y P5.
Tambien distingue decisiones de alcance documentadas para:

- Bloqueo automatico por penalizaciones acumuladas.
- R18/R19: cobertura parcial de decisiones y ejecuciones.
- R20: capacidad implementada usando `Pendiente` como espera operativa por decision de diseno.
- R16/R17: procedimientos disponibles sin planificador integrado.

Estas decisiones se reportan como `PASS` cuando el comportamiento observado coincide con el alcance definido por el equipo.

## Lectura del reporte

Para una defensa oral, conviene leer el reporte en este orden:

1. Veredicto general y resumen de aserciones.
2. Tablero ejecutivo con pruebas, capacidades, decisiones y lote obligatorio.
3. Matriz R1-R21 / P1-P5.
4. Metricas del lote de veinte incidentes.
5. Estado final, SLA, penalizaciones y ranking de recursos.
6. Decisiones automaticas y auditoria de triggers.
7. Observaciones y decisiones de alcance.

Un resultado `PASS` significa que la suite se ejecuto correctamente y que las capacidades observadas respondieron segun el diseno adoptado.
