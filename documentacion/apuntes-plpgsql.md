# Variables Especiales en PL/pgSQL (Triggers en PostgreSQL)

En PostgreSQL, cuando se ejecuta una función definida con `RETURNS TRIGGER`, el motor de la base de datos inyecta de forma automática un conjunto de variables especiales en el entorno local de la función. Estas variables permiten conocer el contexto de la operación DML (Insert, Update, Delete, Truncate) y acceder a los estados del registro afectado.

---

## Tabla de Variables Especiales

| Variable | Tipo de Dato | Descripción |
| :--- | :--- | :--- |
| **`NEW`** | `record` | Almacena la fila entrante. Está disponible en eventos `INSERT` y `UPDATE`. En operaciones `BEFORE`, modificar los campos de `NEW` altera directamente los datos que se escribirán en el disco. |
| **`OLD`** | `record` | Almacena la fila previa antes de ser modificada o eliminada. Está disponible en eventos `UPDATE` y `DELETE`. |
| **`TG_OP`** | `text` | Indica la operación DML que disparó el trigger. Sus posibles valores son: `'INSERT'`, `'UPDATE'`, `'DELETE'` o `'TRUNCATE'`. |
| **`TG_NAME`** | `name` | Nombre del trigger que se está ejecutando actualmente. |
| **`TG_WHEN`** | `text` | Momento de ejecución del trigger. Puede ser: `'BEFORE'`, `'AFTER'` o `'INSTEAD OF'`. |
| **`TG_LEVEL`** | `text` | Nivel de granularidad del trigger. Sus valores posibles son: `'ROW'` (por cada fila) o `'STATEMENT'` (por cada sentencia). |
| **`TG_TABLE_NAME`** | `name` | Nombre de la tabla física sobre la cual se ejecutó la operación DML. |
| **`TG_TABLE_SCHEMA`** | `name` | Nombre del esquema al que pertenece la tabla que disparó el trigger (ej. `'public'`). |
| **`TG_RELID`** | `oid` | Identificador de objeto interno (OID) de la tabla que disparó el trigger. |
| **`TG_ARGV`** | `text[]` | Array que contiene los argumentos textuales declarados al crear el trigger (definidos en la cláusula `EXECUTE FUNCTION fn(arg1, arg2)`). |
| **`TG_NARGS`** | `integer` | Cantidad de argumentos pasados a la función del trigger (longitud de `TG_ARGV`). |

---

## Conceptos Clave en Triggers Validadores

### 1. El uso de `TG_OP`
`TG_OP` es fundamental cuando se comparte la misma función de trigger entre múltiples eventos de una tabla. Permite discernir qué operación se está realizando y adaptar la validación en consecuencia:

```sql
IF TG_OP = 'INSERT' THEN
    -- Lógica solo para inserciones
ELSIF TG_OP = 'UPDATE' THEN
    -- Lógica solo para actualizaciones
END IF;
```

### 2. Retorno de valores en funciones `BEFORE`
*   **`RETURN NEW;`**: Permite que la operación continúe con los valores que tenga la variable de transición `NEW`.
*   **`RETURN NULL;`**: Cancela silenciosamente la operación para la fila actual (no arroja error, pero no inserta/modifica nada).
*   **`RAISE EXCEPTION`**: Cancela la operación arrojando un error, lo cual causa el **rollback** de toda la transacción actual. Es el enfoque estándar para validadores de integridad de negocio.

### 3. El uso del marcador de posición `%` en `RAISE`
En PL/pgSQL, cuando utilizas sentencias `RAISE EXCEPTION`, `RAISE NOTICE` o `RAISE WARNING`, el carácter `%` actúa como un **marcador de posición (placeholder)** para dar formato dinámico a los mensajes de error:

```sql
RAISE EXCEPTION 'Error: El recurso % no está disponible (Estado: %).', NEW.fk_recurso_id, v_estado_nombre;
```

*   **Funcionamiento:** Cada `%` en la cadena de texto es reemplazado de manera secuencial por el valor de las expresiones/variables que se listan después de la coma.
*   **Diferencia clave:** En este contexto no debe confundirse con el comodín `%` del operador `LIKE` en las consultas `SELECT` (el cual representa cualquier secuencia de caracteres).

---

*Apunte creado como soporte de desarrollo para el proyecto Smart City.*
