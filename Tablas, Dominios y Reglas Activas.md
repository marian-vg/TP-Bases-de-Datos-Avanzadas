**Modelo relacional de nuestra base de datos:**

**TipoIncidente**(PKid, nombre, descripcion)  
**EstadoIncidente**(PKid, nombre)  
**Gravedad**(PKid, nombre)  
**SLA**(PKid, FKgravedad\_id, tiempo\_respuesta\_minutos)  
**NivelRiesgo**(PKid, nombre, valor)  
**Zona**(PKid, nombre, FKnivel\_riesgo\_id)  
**TipoSensor**(PKid, nombre)  
**Sensor**(PKid, FKtipo\_sensor\_id, FKzona\_id, marca, modelo, nombre, fecha\_instalado, fecha\_mantenimiento)  
**TipoEvento**(PKid, nombre, descripcion)  
**Evento**(PKid, FKsensor\_id, FKtipo\_evento\_id, fecha\_evento, hora\_evento)  
**Incidente**(PKid, FKevento\_id NULL, FKtipo\_incidente\_id, FKgravedad\_id, FKestado\_incidente\_id, FKzona\_id, fecha\_hora\_registro, descripcion, prioridad)  
**TipoRecurso**(PKid, nombre, descripcion)  
**EstadoRecurso**(PKid, nombre)  
**Recurso**(PKid, FKtipo\_recurso\_id, FKzona\_id, FKestado\_recurso\_id)  
**Asignacion**(PK id, FK recurso\_id, FK incidente\_id, timestamp\_asignacion, NULL timestamp\_llegada, timestamp\_finalizacion NULL, estado\_exito)  
**TipoPenalizacion**(PKid, nombre, puntaje)  
**Penalizacion**(PKid, FKrecurso\_id, FKtipo\_penalizacion\_id, fecha, hora, motivo)  
**Log**(PKid, tablaAfectada, idTablaAfectada, detalle, timestamp)

**Tablas nuevas que fui descubriendo:**

**ZonaRecurso** (PKFK idZona, PKFK idRecurso)  
**RecursoFuera**(PKFK idRecurso, fecha\_salida, fecha\_reincorporacion)  
**ParametrosSistema**(PK NombreParametro, Número

Log guarda el historial de cada requerimiento que pide el TP.  
Para no tener que crear una tabla por entidad a futuro, el Log ahora utiliza tablaAfectada para ver qué tabla tuvo el cambio. De la otra forma seria muy poco escalable.

# Dominios

# Reglas activas

## 7.2 Reglas de Automatización (Tomchad)

R1. Asignación automática de recursos  
Al registrarse un incidente, el sistema deberá asignar automáticamente un recurso  
disponible.  
R2. Cambio automático de estado  
Al asignar un recurso, el incidente deberá pasar automáticamente a estado “En proceso”.  
R3. Registro automático de auditoría  
Cada operación relevante (alta, modificación, eliminación) deberá registrarse en una tabla  
de auditoría.  
R4. Reasignación automática de recursos  
Si un recurso asignado no responde o falla, el sistema deberá:  
• marcar la asignación como fallida  
• asignar un nuevo recurso disponible

- Penalizar el recurso 

R5. Asignación múltiple en incidentes críticos  
Si la gravedad del incidente es alta, el sistema deberá asignar más de un recurso.  
Ejemplo: un incendio puede generar una emergencia médica.

R7. Cierre automático de incidentes  
Cuando todos los recursos asignados finalicen su intervención, el incidente deberá pasar  
automáticamente a estado “Resuelto”.  
R8. Cambiar estado de los recursos automáticamente según su asignación.  
R9: Generar penalizaciones automaticamente segun si fallo en asignarse el recurso o tardo en responder.

## 7.3 Reglas de Validación (Mariano aura)

R8. Validación de disponibilidad de recursos  
No se podrá asignar un recurso que ya esté ocupado.

R9. Validación de coherencia de estados  
Se deberán evitar cambios de estado inválidos.  
Ejemplo:  
• No se puede pasar de “Pendiente” directamente a “Resuelto”.

R10. Validación de zona del recurso  
Un recurso solo podrá asignarse a incidentes dentro de su zona habilitada.

R11. Validación de duplicación de incidentes  
Se deberá evitar registrar incidentes duplicados en un corto período (misma zona y tipo).

## 7.4 Reglas de Inteligencia (dani)

R12. Priorización automática por gravedad  
La prioridad del incidente deberá calcularse automáticamente según su nivel de  
gravedad.

R13. Priorización por zona de riesgo  
Si el incidente ocurre en una zona de alto riesgo, su prioridad deberá incrementarse  
automáticamente.

R14. Selección del mejor recurso  
El sistema deberá asignar recursos considerando:  
• disponibilidad  
• carga de trabajo  
• historial de desempeño

R15. Rebalanceo de recursos  
Si una zona queda sin recursos disponibles, el sistema deberá redistribuir recursos desde  
otras zonas. \-\> R15 rompe con R10. O no……

## 7.5 Reglas Temporales

R16. Control de tiempo de resolución (SLA)  
Si un incidente supera el tiempo máximo establecido, deberá cambiar automáticamente a  
estado “Escalado”.

R17. Reactivación automática de recursos  
Un recurso fuera de servicio deberá volver automáticamente a estado disponible luego de  
un período determinado.

## 7.6 Reglas de Auditoría y Control

R18. Registro de decisiones automáticas  
Cada acción ejecutada por reglas activas deberá registrar:  
• acción realizada  
• fecha y hora  
• motivo o criterio utilizado

R19. Log de ejecución de triggers  
Se deberá registrar cada ejecución de trigger indicando:  
• nombre del trigger  
• operación ejecutada  
• fecha y hora

R20. Control de capacidad del sistema  
Si el número de incidentes activos supera un umbral, los nuevos incidentes deberán  
marcarse como “En espera”.

# Procedures

P1. sp\_AsignarRecurso  
• Busca recursos disponibles.  
• Aplica criterio de selección.  
• Asigna automáticamente.

P2. sp\_EscalarIncidente  
• Aumenta gravedad si se supera el SLA.

P3. sp\_CerrarIncidente  
• Finaliza el incidente.  
• Libera recursos.

P4. sp\_CalcularPenalizacion  
• Calcula penalizaciones por demora.

P5. sp\_SimularEventos  
• Genera incidentes automáticamente.

# Vistas

¿Qué es? \-\> La reutilización de una consulta con el objetivo de minimizar redundancia.  
Son consultas predefinidas con un nombre asignado.

* vIncidentesActivos: *Incidentes CON recursos pero SIN terminar.*  
* vRecursosDisponibles   
* vRecursosOcupados  
* vIncidentesCriticos   
* vHistorialIncidentes   
* vRecursosPenalizados  
* vRecursosCandidatos: *Listado por ID de recursos DISPONIBLES, con Carga de Trabajo (hs, dias, no se), y Ranking de Rendimiento (Puntaje). Utilizado para calcular asignación de recursos.*  
* vHistorialAsignaciones  
* vHistorialTriggers  
* vZonasIncidentadas

