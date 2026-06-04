# Bitácora de Trabajo (Walkthrough) - Procedimientos Almacenados

Este documento detalla las tareas realizadas, los resultados de las pruebas y las optimizaciones aplicadas sobre los procedimientos almacenados de la base de datos `smart_city`.

---

## 1. Modificaciones Realizadas

### Corrección en `sp_SimularEventoSensor`
- **Archivo afectado:** [simular-eventos.sql](file:///C:/Users/Administrador/herd/tp-bda/database/store-procedures/simular-eventos.sql)
- **Problema detectado:** Se declaraba la variable `v_tipo_evento_existe` pero nunca se utilizaba. La validación del tipo de evento (Paso 2) estaba completamente ausente, lo que provocaba que al ingresar un tipo de evento no válido, la base de datos fallara debido a una violación de clave foránea (`fk_evento_tipo`) en lugar de levantar una excepción limpia y controlada por el procedimiento.
- **Solución implementada:** Se agregó la validación explícita de existencia del tipo de evento antes de intentar la inserción en la tabla `Evento`:
  ```sql
  -- 2. Validar existencia del tipo de evento
  SELECT id_tipo_evento INTO v_tipo_evento_existe
  FROM TipoEvento
  WHERE id_tipo_evento = p_id_tipo_evento;

  IF NOT FOUND THEN
      RAISE EXCEPTION 'El tipo de evento con ID % no existe.', p_id_tipo_evento;
  END IF;
  ```

---

## 2. Resultados de las Pruebas

Se ejecutaron las pruebas de integración en [test-procedures.sql](file:///C:/Users/Administrador/herd/tp-bda/tests/test-procedures.sql) utilizando PostgreSQL 18 local:

```powershell
$env:PGPASSWORD="Eduardo130#"; & "D:\Program Files (D)\PostgreSQL\18\bin\psql.exe" -h localhost -U postgres -d smart_city -f tests/test-procedures.sql
```

### Resumen de la Ejecución:
- **Prueba 9 (Parámetros inválidos):** Éxito. Ahora se controlan limpiamente ambas excepciones:
  - `El sensor con ID -9999 no existe.`
  - `El tipo de evento con ID -9999 no existe.` (Anteriormente fallaba por violación de restricción FK).
- **Prueba 10 (Promoción única):** Éxito. El sensor 1 simuló el evento 2 y se creó automáticamente el incidente 8 con 2 recursos asignados automáticamente.
- **Prueba 11 (Mapeo múltiple / No promoción):** Éxito. El evento 2 se registró pero no se promovió a incidente (Motivo: mapeo a tipo de incidente no es único).
- **Resultado final:** `>>> TODAS LAS PRUEBAS DE PROCEDIMIENTOS OK <<<`

---

## 3. Próximos Pasos recomendados
- Integrar las mejoras propuestas para el procedimiento almacenado `sp_CerrarIncidente` detalladas en el informe presentado.
- Mantener la suite de pruebas automatizadas actualizada ante futuros cambios en las reglas de negocio.
