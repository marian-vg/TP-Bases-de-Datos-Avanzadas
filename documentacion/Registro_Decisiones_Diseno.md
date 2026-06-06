  
**Universidad Autónoma de Entre Ríos**

**Facultad de Ciencia y Tecnología**

Licenciatura en Sistemas de Información

*Bases de Datos Avanzadas — 4° Año*

**Trabajo Práctico N° 1**

Bases de Datos Activas

***Registro de Decisiones de Diseño***

**Grupo N° 10**

**Docentes**

Ing. Jorge Schmukler

Lic. Sebastián Trossero

**Año 2026**

# **1\. Propósito del documento**

El presente documento del Grupo N° 10 deja registradas las decisiones de diseño tomadas durante el desarrollo del Trabajo Práctico N° 1, junto con su fundamentación, a fin de facilitar su consulta y defensa.

# **2\. Formato de las decisiones**

Cada decisión se documenta con los siguientes campos:

* **Identificador**: código único de la forma DD-XX.

* **Categoría**: ámbito del diseño al que pertenece.

* **Contexto**: situación o problema que motiva la decisión.

* **Decisión**: enunciado de lo resuelto.

# **3\. Indice de decisiones** 

| Identificador | Título | Categoría |
| :---: | :---- | ----- |
| DD-01 | Incorporación del estado «En tránsito» para recursos | Modelado de datos |
| DD-02 | Umbral de confianza dinámico para sensores | Modelado / Lógica |
| DD-03 | Centralización de auditoría operativa y técnica en una única tabla | Modelado / Arquitectura |
| DD-04 | Resolución de Contradicción R16 y R9 (Escalado de incidentes) | Reglas activas / Lógica |
| DD-05 | R16 (SLA) como Procedimiento Manual | Arquitectura / Reglas activas |
| DD-06 | Semántica de Escalado (R16) | Lógica / Modelado |
| DD-07 | Parametrización de Números Mágicos | Modelado de datos |
| DD-08 | Uso de Prioridad y Gestión del Backlog | Lógica / Reglas activas |
| DD-09 | Nueva Tabla TipoIncidenteTipoRecurso (M:N) | Modelado / Lógica |
| DD-10 | Confianza de Sensores (R21 Simplificada) | Lógica / Reglas activas |
| DD-11 | Nueva Tabla MantenimientoSensor (Historial) | Modelado de datos |
| DD-12 | Nueva Vista vSensoresMantenimiento | Modelado de datos DD-13 Puntaje de recursos Reglas activas / Lógica  |

# **4\. Decisiones registradas**

## **DD-01: Incorporación del estado «En tránsito» para recursos**

## 

| Identificador | DD-01 |
| :---- | :---- |
| **Categoría** | Modelado de datos |

### **Contexto**

Una de las reglas activas y regla de negocio es la penalización de los recursos cuando tardan más de determinado tiempo en responder. Debido a que el enunciado no aclara qué es "penalizar el tiempo de respuesta", el grupo decidió que lo más justo es medir el tiempo que tarda el recurso en responder desde el momento que es asignado. Esto evita penalizaciones injustas (ejemplo, por procesamiento tardío del sistema o falta de recursos disponibles en la zona). La entidad Asignación contempla tres atributos temporales (timestamp\_asignacion, timestamp\_llegada y timestamp\_finalizacion) que fueron incluidos por el grupo, evidenciando tres etapas diferenciables: despacho, arribo y finalización. Para aplicar esta penalización de forma justa y distinguir correctamente las etapas, no es posible con los estados originales (Disponible, Ocupado y Fuera de servicio) diferenciar un recurso ya despachado pero todavía en traslado de uno que se encuentra interviniendo en el lugar.

### **Decisión**

Para permitir la penalización más justa de recursos, se decidió incluir 2 timestamps clave en la entidad Asignación: timestamp\_asignacion (para saber cuándo el sistema asignó el recurso) y timestamp\_llegada (para saber cuándo el recurso arribó a destino). Esta asignación permite simular y aplicar las penalizaciones de forma más justa. Además, se incorpora un cuarto estado denominado «En tránsito», que representa el período entre la asignación de un recurso y su arribo al incidente. Las transiciones se gobiernan mediante triggers sobre Asignación:

* Disponible → En tránsito: al registrarse una nueva asignación.

* En tránsito → Ocupado: al establecerse timestamp\_llegada.

* Ocupado → Disponible: al establecerse timestamp\_finalizacion.

El tiempo de traslado se calcula como:

tiempo\_traslado \= timestamp\_llegada \- timestamp\_asignacion

Si este intervalo excede el SLA correspondiente a la gravedad del incidente, se genera la penalización pertinente sobre el recurso.

## **DD-02: Umbral de confianza dinámico para sensores**

## 

| Identificador | DD-02 |
| :---- | :---- |
| **Categoría** | Modelado de datos / Lógica de negocio |

### **Contexto**

La sección 2.6 del enunciado establece que los eventos generados por sensores pueden originar incidentes de manera automática. En un escenario IoT realista, las detecciones no poseen idéntica confiabilidad: un dispositivo sin mantenimiento prolongado es más propenso a producir falsos positivos. El atributo fecha\_mantenimiento de Sensor se aprovecha como referencia para cuantificar dicha confiabilidad.

### **Decisión**

Se define un atributo derivado denominado umbral de confianza, calculado dinámicamente para cada sensor en función del tiempo transcurrido desde su última fecha de mantenimiento. El umbral se expresa como un valor porcentual entre 0 % y 100 %, según las siguientes reglas: todo sensor nace con un umbral del 100 % al instalarse; por cada semana transcurrida sin mantenimiento, el umbral decrece 5 %; cada operación de mantenimiento restablece el umbral al 100 %. El cálculo aplicado es:

umbral \= MAX(0, 100 \- 5 \* semanas\_desde\_ultima\_revision)

Cuando fecha\_mantenimiento es nula, se toma fecha\_instalado como referencia. El trigger de generación automática de incidentes adapta su comportamiento según el valor del umbral:

* Umbral ≥ 80 %: se genera el incidente con prioridad normal.

* Umbral entre 50 % y 80 %: se genera el incidente con prioridad reducida.

* Umbral entre 20 % y 50 %: el evento se registra en el log; no se genera incidente.

* Umbral \< 20 %: el evento se descarta como probable falso positivo.

Los valores de corte se externalizan en la tabla ParametrosSistema.

## **DD-03: Centralización de auditoría operativa y técnica en una única tabla**

## 

| Identificador | DD-03  |
| :---- | :---- |
| **Categoría** | Modelado de datos / Arquitectura |

### **Contexto**

El sistema requiere mantener un historial completo de auditoría que registre tanto los cambios de estado y decisiones automáticas del negocio (operaciones sobre las tablas), como la ejecución técnica de las reglas activas (triggers disparados).

### **Decisión**

Se decidió implementar una única tabla centralizada y polimórfica denominada Log, consolidando tanto la auditoría del negocio como el registro técnico de ejecución, garantizando que cada evento sea una única fuente de verdad inmutable. Para soportar esta centralización, la tabla se diseña con las siguientes características clave: 

● **tablaAfectada e idTablaAfectada:** Actúan como punteros lógicos hacia cualquier registro del sistema que haya sido mutado. 

**● trigger\_disparador:** Se define como una columna que permite valores NULL. Esta es la pieza arquitectónica central: si el cambio fue originado por una regla activa, el trigger inserta su propio nombre mediante variables de entorno (ej. TG\_NAME). Si el cambio es una actualización directa (ej. una intervención del operador), el valor queda en NULL, logrando distinguir la operatividad técnica de la manual en la misma estructura. 

**● detalle:** Se utilizará un tipo de dato estructurado (como JSONB) para almacenar dinámicamente la carga útil (estado anterior, estado nuevo y motivos de decisión) sin romper la normalización.

## **DD-04: Resolución de Contradicción R16 y R9 (Escalado de incidentes)**

## 

| Identificador | DD-04  |
| :---- | :---- |
| **Categoría** | Reglas activas / Lógica de negocio |

### **Contexto**

Existe una contradicción entre las reglas R16 y R9. R16 intentaba escalar incidentes en estado "Pendiente", pero R9 prohíbe la transición del estado "Pendiente" a "Escalado".

### **Decisión**

Se resuelve mediante la decisión de dominio (ver DD-06): R16 (sp\_escalar\_incidente) escala únicamente incidentes en estado "En proceso".

## **DD-05: R16 (SLA) como Procedimiento Manual**

## 

| Identificador | DD-05  |
| :---- | :---- |
| **Categoría** | Arquitectura / Reglas activas |

### **Contexto**

Se requiere implementar la regla R16 (Control de SLA para escalamiento). Debido a restricciones de la cátedra, no se pueden usar cronjobs para la ejecución automática de procesos periódicos.

### **Decisión**

R16 se implementa como un procedimiento almacenado (CREATE PROCEDURE sp\_escalar\_incidente()) que debe ser invocado manualmente (CALL).

## **DD-06: Semántica de Escalado (R16)**

## 

| Identificador | DD-06  |
| :---- | :---- |
| **Categoría** | Lógica de negocio / Modelado de datos |

### **Contexto**

Definir la semántica de la transición de estado "Escalado". La regla R16 habla de tiempo de resolución.

### **Decisión**

Solo se escalan los incidentes que están "En proceso". Los incidentes "Pendiente" que hayan vencido su SLA no se escalan; en su lugar, se incrementa su prioridad.

## **DD-07: Parametrización de Números Mágicos**

## 

| Identificador | DD-07  |
| :---- | :---- |
| **Categoría** | Modelado de datos |

### **Contexto**

Externalizar valores de corte ("números mágicos") en el sistema.

### **Decisión**

Se modelan en la tabla ParametrosSistema: UMBRAL\_INCIDENTES\_ACTIVOS, SENSOR\_DECAIMIENTO\_CONFIANZA\_SEMANAL \= 5 y SENSOR\_UMBRAL\_CONFIANZA\_MINIMO \= 80\.

## **DD-08: Uso de Prioridad y Gestión del Backlog**

## 

| Identificador | DD-08  |
| :---- | :---- |
| **Categoría** | Lógica de negocio / Reglas activas |

### **Contexto**

Definir cómo se utiliza la prioridad de un incidente en la asignación de recursos y cómo se gestiona el backlog de incidentes "Pendientes" cuando los recursos se agotan.

### **Decisión**

Al liberarse un recurso: Se atiende el backlog de incidentes "Pendientes" por mayor prioridad. Esto es event-driven y se implementa como un trigger en la liberación del recurso.

## **DD-09: Nueva Tabla TipoIncidenteTipoRecurso (M:N)**

## 

| Identificador | DD-09  |
| :---- | :---- |
| **Categoría** | Modelado de datos / Lógica de negocio |

### **Contexto**

El motor de asignación actual asigna recursos sin validar si el tipo de recurso es apropiado para el tipo de incidente.

### **Decisión**

Se crea una nueva tabla M:N, TipoIncidenteTipoRecurso, para definir qué tipos de recurso aplican a cada tipo de incidente.

## **DD-10: Confianza de Sensores (Nueva Regla R21, Simplificada)**

## 

| Identificador | DD-10  |
| :---- | :---- |
| **Categoría** | Lógica de negocio / Reglas activas |

### **Contexto**

Implementación de la confianza de sensores (R21) y su efecto en la promoción de eventos a incidentes.

### **Decisión**

Un evento se promueve a incidente solo si la confianza es \> 80%; si no, se registra solo en el Log. Esto simplifica el modelo previo a uno binario.

## **DD-11: Nueva Tabla MantenimientoSensor (Historial)**

## 

| Identificador | DD-11  |
| :---- | :---- |
| **Categoría** | Modelado de datos |

### **Contexto**

Se requiere guardar el historial de mantenimientos de los sensores.

### **Decisión**

Se crea una nueva tabla MantenimientoSensor para almacenar el historial de mantenimientos.

## **DD-12: Nueva Vista vSensoresMantenimiento**

## 

| Identificador | DD-12  |
| :---- | :---- |
| **Categoría** | Modelado de datos |

### **Contexto**

Se necesita una vista consolidada para visualizar la información de mantenimiento y confianza de los sensores.

### **Decisión**

Se crea una nueva vista vSensoresMantenimiento.

## **DD-13: Puntaje de recursos**

## 

| Identificador | DD-13 |
| :---- | :---- |
| **Categoría** | Reglas activas / Lógica de negocio |

### **Contexto**

La decisión nace de encontrar un mecanismo eficiente para regular cuál es el mejor recurso para asignar a un incidente.

### **Decisión**

Se establece un sistema de puntaje para rankear los recursos disponibles y seleccionar el más adecuado para un incidente. El recurso comienza con 0 puntos. La asignación de puntajes se rige por los siguientes eventos: Si una asignación es exitosa, suma 1 punto. Si un recurso es penalizado, según el tipo de penalización, pierde una cantidad variable de puntos. Por cada 3 asignaciones exitosas, el recurso suma 2 puntos. Los recursos que logren acatar un incidente en el tiempo establecido por el SLA, son recompensados con más puntos según la gravedad. 

El sistema elige el mejor recurso a asignar basándose en este ranking de puntos. 

## **DD-14: Gestión de Backlog por Umbral de Incidentes Activos**

## 

| Identificador | DD-14 |
| :---- | :---- |
| **Categoría** | Reglas activas / Lógica de negocio |

### **Contexto**

Se requiere implementar la regla activa de colocar nuevos incidentes en estado de espera cuando la cantidad de incidentes activos supera un umbral. Existían dos ambigüedades: el estado a utilizar ("En espera") y el alcance del umbral (general del sistema).

### **Decisión**

Para respetar la regla activa, se tomaron dos decisiones de diseño:

* **Estado a utilizar:** Se utilizará el estado "Pendiente" en vez de "En espera" para los incidentes en backlog, ya que ambos se consideran semánticamente equivalentes.

* **Umbral de control:** Se implementará un umbral de incidentes activos POR ZONA, en lugar de considerarlo como un parámetro general del sistema.

## **DD-15: Bloqueo temporal e historial de inhabilitaciones**

| Identificador | DD-15 |
| :---- | :---- |
| **Categoría** | Modelado de datos / Reglas activas |

### **Contexto**

La consigna exige bloquear recursos con múltiples penalizaciones y reactivarlos
automáticamente luego de un período. El puntaje de rendimiento permite ordenar candidatos,
pero no reemplaza un bloqueo operativo ni identifica qué recursos corresponden a R17.

### **Decisión**

Se incorpora `MAX_CANTIDAD_PENALIZACIONES_RECURSO` como parámetro configurable. Al alcanzar
esa cantidad de penalizaciones vigentes, el recurso pasa a `Fuera de servicio` y se crea una
fila en `InhabilitacionRecurso` con las fechas de inhabilitación, reactivación programada y
reactivación efectiva.

La relación entre `Recurso` e `InhabilitacionRecurso` es 1:N para conservar el historial. Un
índice único parcial permite una sola inhabilitación activa por recurso sin limitar las filas
históricas. R17 consulta esta tabla y reactiva únicamente bloqueos originados por
penalizaciones; otras causas de `Fuera de servicio` no se modifican automáticamente.

Las penalizaciones se agrupan por ciclos. Al reactivar un recurso, el contador vigente vuelve
a cero y comienza un ciclo nuevo, mientras que las penalizaciones e inhabilitaciones previas
permanecen disponibles para auditoría.
