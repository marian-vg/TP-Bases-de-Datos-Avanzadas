## Universidad Autónoma de Entre Rios.

## Facultad de Ciencia y Tecnología.

## Carrera: Licenciatura en Sistemas de Información.

## Catedra: BASES DE DATOS AVANZADAS. 4to. Año.

# TRABAJO PRÁCTICO Nro. 1

## Tema: Bases de Datos Activas

```
Docentes
Ing. Jorge Schmukler
Lic. Sebastián Trossero
```
**2026
UADER – FCyT – Bases de Datos Avanzadas**


## Trabajo Práctico Nro 1 – Bases de Datos Activas

📅 **Fecha Límite de Entrega: 05/06/**
👥 **Modalidad:** Grupal (2 a 4 integrantes)
🛠 **SGBD:** PostgreSQL 9.3 o superior

### Sistema Inteligente de Gestión de Emergencias Urbanas

### (Smart City)

### 1. Planteo del Problema

Las ciudades requieren de un sistema de gestión de datos que sea capaz de administrar
emergencias y servicios en tiempo real, optimizando el uso de recursos críticos como
ambulancias, bomberos, policías, defensa civil, servicios municipales, red de gas, servicios
de energía eléctrica y otros que se consideren a tener cuenta.

Se propone el desarrollo de un sistema basado en **Bases de Datos Activas** , que permita
no solo almacenar información, sino también **reaccionar automáticamente ante eventos** ,
aplicando reglas de negocio, validaciones y automatizaciones mediante triggers,
procedimientos almacenados y vistas.

El sistema deberá comportarse como un **centro de monitoreo inteligente** , capaz de:

- Detectar incidentes.
- Asignar recursos automáticamente.
- Escalar situaciones críticas.
- Penalizar demoras.
- Mantener un historial completo de eventos.

### 2. Dominio del Problema

El sistema deberá contemplar los siguientes elementos:

**2.1 Incidentes**

Representan eventos que requieren intervención.

Ejemplos:

- Accidentes de tránsito


- Incendios
- Emergencias médicas
- Delitos

Características:

- Poseen un nivel de gravedad (1 a 5).
- Evolucionan en el tiempo.
- Cambian de estado (Pendiente, En proceso, Resuelto, Escalado).

**2.2 Recursos**

Son los medios disponibles para atender incidentes.

Tipos:

- Ambulancias
- Bomberos
- Patrulleros

Estados:

- Disponible
- Ocupado
- Fuera de servicio

**2.3 Asignaciones**

Relacionan incidentes con recursos.

Condiciones:

- Un incidente puede tener múltiples recursos.
- Un recurso no puede estar asignado a más de un incidente simultáneamente.

**2.4 Zonas**

División geográfica de la ciudad.

Atributos:

- Nivel de riesgo (Alto, Medio, Bajo)

**2.5 Sensores (IoT simulado)**


Dispositivos que generan eventos automáticamente.

Ejemplos:

- Cámaras
- Detectores de humo
- Botones de pánico

**2.6 Eventos Automáticos**

Eventos generados por sensores.

Características:

- Pueden generar incidentes automáticamente.
- Deben registrarse y procesarse.

**2.7 SLA (Tiempos de Respuesta** )

Define el tiempo máximo permitido según gravedad.

Ejemplo:

- Gravedad alta → 5 minutos
- Gravedad media → 10 minutos

**2.8 Penalizaciones**

Se generan cuando:

- Un recurso excede el tiempo de respuesta.
- Un recurso falla en su tarea.

**2.9 Historial / Auditoría**

Debe registrar:

- Cambios de estado
- Decisiones del sistema
- Ejecución de triggers

### 3. Reglas de Negocio


El sistema deberá cumplir con las siguientes reglas:

✔ Asignación automática de recursos al generarse un incidente.
✔ No asignar recursos ocupados.
✔ Escalar automáticamente incidentes no atendidos en tiempo.
✔ Penalizar recursos por demoras.
✔ Bloquear recursos con múltiples penalizaciones.
✔ Permitir múltiples recursos en incidentes críticos.

✔ Generación automática de incidentes desde sensores.
✔ Registro completo de auditoría.

### 4. Modelo de Datos

El grupo deberá definir:

**4.1 DER No Normalizado**

Debe incluir:

- Atributos multivaluados.
- Atributos derivados.
- Atributos compuestos.

**4.2 DER Normalizado (3FN)**

Debe incluir:

- Claves primarias naturales
- Relaciones correctas
- Integridad referencial

**4.3 Entidades mínimas sugeridas**

- Incidentes
- Recursos
- Asignaciones
- Zonas
- Sensores
- Eventos
- SLA
- Penalizaciones
- Historial

### 5. Implementación de Base de Datos


Crear la base de datos correspondiente. Deberá entregar el esquema con las siguientes
consideraciones:

a. El grupo tendrá libertad para diseñar las tablas, elegir los tipos de datos y extensión de
cada atributo.

Nota: con la única restricción de utilizar los conceptos teóricos desarrollados en las
materias Bases de Datos y Bases de Datos Avanzadas y además el sentido común para la
elección.

El grupo deberá desarrollar:

**5.1 Script SQL completo**

Incluyendo:

- CREATE TABLE
- PRIMARY KEY / FOREIGN KEY
- Restricciones
- Índices

**5.2 Validaciones**

Ejemplos:

- Un recurso no puede tener dos asignaciones simultáneas.
- No se puede cerrar un incidente sin asignación.
- No asignar recursos fuera de servicio.

### 6. Procedimientos Almacenados

El sistema deberá incluir como mínimo:

**P1. sp_AsignarRecurso**

- Busca recursos disponibles.
- Aplica criterio de selección.
- Asigna automáticamente.


**P2. sp_EscalarIncidente**

- Aumenta gravedad si se supera el SLA.

**P3. sp_CerrarIncidente**

- Finaliza el incidente.
- Libera recursos.

**P4. sp_CalcularPenalizacion**

- Calcula penalizaciones por demora.

**P5. sp_SimularEventos**

- Genera incidentes automáticamente.

### 7. Reglas Activas (Triggers)

El sistema deberá implementar un conjunto de **reglas activas** que automaticen
comportamientos y garanticen la consistencia de la información.

Una regla activa sigue el modelo:

**Evento → Condición → Acción (ECA)**

Esto implica que, ante un evento en la base de datos, si se cumple una determinada
condición, se ejecutará automáticamente una acción sin intervención del usuario.

**7.1 Consideraciones Generales**

Las reglas activas deberán implementarse mediante **triggers y funciones en PostgreSQL**.

Se deberá diferenciar el uso de:

```
o BEFORE (validaciones y control)
o AFTER (automatización y auditoría)
```
Cada regla deberá estar correctamente documentada (ver sección 7.7).

Se deberán evitar:


```
o loops de ejecución
o inconsistencias
o impactos negativos en el rendimiento
```
**7.2 Reglas de Automatización**

**R1. Asignación automática de recursos**

Al registrarse un incidente, el sistema deberá asignar automáticamente un recurso
disponible.

**R2. Cambio automático de estado**

Al asignar un recurso, el incidente deberá pasar automáticamente a estado **“En proceso”**.

**R3. Registro automático de auditoría**

Cada operación relevante (alta, modificación, eliminación) deberá registrarse en una tabla
de auditoría.

**R4. Reasignación automática de recursos**

Si un recurso asignado no responde o falla, el sistema deberá:

- marcar la asignación como fallida
- asignar un nuevo recurso disponible

**R5. Asignación múltiple en incidentes críticos**

Si la gravedad del incidente es alta, el sistema deberá asignar más de un recurso.

**R6. Generación de incidentes relacionados**

Determinados incidentes podrán generar automáticamente otros incidentes
relacionados.

Ejemplo: un incendio puede generar una emergencia médica.

**R7. Cierre automático de incidentes**

Cuando todos los recursos asignados finalicen su intervención, el incidente deberá pasar
automáticamente a estado **“Resuelto”**.

**7.3 Reglas de Validación**


**R8. Validación de disponibilidad de recursos**

No se podrá asignar un recurso que ya esté ocupado.

**R9. Validación de coherencia de estados**

Se deberán evitar cambios de estado inválidos.

Ejemplo:

- No se puede pasar de “Pendiente” directamente a “Resuelto”.

**R10. Validación de zona del recurso**

Un recurso solo podrá asignarse a incidentes dentro de su zona habilitada.

**R11. Validación de duplicación de incidentes**

Se deberá evitar registrar incidentes duplicados en un corto período (misma zona y tipo).

**7.4 Reglas de Inteligencia**

**R12. Priorización automática por gravedad**

La prioridad del incidente deberá calcularse automáticamente según su nivel de
gravedad.

**R13. Priorización por zona de riesgo**

Si el incidente ocurre en una zona de alto riesgo, su prioridad deberá incrementarse
automáticamente.

**R14. Selección del mejor recurso**

El sistema deberá asignar recursos considerando:

- disponibilidad
- carga de trabajo
- historial de desempeño


**R15. Rebalanceo de recursos**

Si una zona queda sin recursos disponibles, el sistema deberá redistribuir recursos desde
otras zonas.

**7.5 Reglas Temporales**

**R16. Control de tiempo de resolución (SLA)**

Si un incidente supera el tiempo máximo establecido, deberá cambiar automáticamente a
estado **“Escalado”**.

**R17. Reactivación automática de recursos**

Un recurso fuera de servicio deberá volver automáticamente a estado disponible luego de
un período determinado.

**7.6 Reglas de Auditoría y Control**

**R18. Registro de decisiones automáticas**

Cada acción ejecutada por reglas activas deberá registrar:

- acción realizada
- fecha y hora
- motivo o criterio utilizado

**R19. Log de ejecución de triggers**

Se deberá registrar cada ejecución de trigger indicando:

- nombre del trigger
- operación ejecutada
- fecha y hora

**R20. Control de capacidad del sistema**

Si el número de incidentes activos supera un umbral, los nuevos incidentes deberán
marcarse como **“En espera”**.

**7.7 Documentación Obligatoria de Reglas Activas**


Cada regla implementada deberá documentarse con el siguiente formato:

- **Nombre de la regla**
- **Tipo** (automatización, validación, inteligencia, auditoría)
- **Evento que la dispara**
- **Condición de ejecución**
- **Acción realizada**
- **Tablas afectadas**
- **Ejemplo de ejecución (caso de prueba)**

**7.8 Requisitos de Implementación**

- Cada grupo deberá implementar al menos **12 reglas activas**.
- Se deberán incluir reglas de **al menos 3 categorías distintas**.
- Las reglas deberán ser:
    o coherentes
    o eficientes
    o correctamente justificadas

**7.9 Criterios de Evaluación**

Se evaluará:

- Correcta implementación técnica
- Uso adecuado de triggers (BEFORE / AFTER)
- Calidad de la lógica aplicada
- Nivel de complejidad de las reglas
- Documentación clara
- Correcto funcionamiento mediante casos de prueba

### 8. Vistas

El sistema deberá incluir vistas como mínimo:

- vIncidentesActivos
- vRecursosDisponibles
- vIncidentesCriticos
- vHistorialIncidentes
- vRecursosPenalizados

### 9. Casos de Prueba


El grupo deberá demostrar:

**Casos básicos**

- Asignación correcta de recursos
- Cambio de estados

**Casos intermedios**

- Falta de recursos
- Incidentes múltiples

**Casos avanzados**

- Escalamiento automático
- Penalizaciones
- Bloqueo de recursos

Simulación obligatoria

- Mínimo 20 incidentes simultáneos

### 10. Etapas de Desarrollo

- DER no normalizado
- DER normalizado
- Reglas de negocio
- Script de base de datos
- Tablas y relaciones
- Triggers básicos
- Procedimientos
- Sistema completo
- Simulación
- Auditoría

### 11. Modalidad de Entrega


Informe (Formato A4)

Debe incluir:

- Carátula
- Descripción del problema
- Modelo de datos
- Explicación de reglas
- Casos de prueba

Adjuntos

- Script SQL completo
- Procedimientos y triggers
- Datos de prueba
- Evidencia de ejecución

### 12. Evaluación

- Modelo de datos: 20%
- Implementación: 25 %
- Reglas activas: 30%
- Pruebas: 15 %
- Defensa oral: 10%

### 13. Condiciones Especiales

- Cada grupo deberá definir sus propios parámetros:
    o tiempos SLA
    o cantidad de recursos
    o reglas de penalización
- Se evaluará:
    o originalidad
    o coherencia
    o justificación técnica

### 14. Objetivo Final

El objetivo del trabajo es que el grupo de alumnos logre:

A partir de una implementación técnica, se busca que se logre analizar, diseñar y justificar
un sistema que actúa de forma autónoma.


- Diseñar sistemas reactivos
- Implementar lógica basada en eventos
- Resolver problemas de concurrencia
- Comprender el uso real de triggers



