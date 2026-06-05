# TP Bases de Datos Avanzadas — Smart City

Repositorio del **Trabajo Práctico de Bases de Datos Avanzadas** sobre una **base de datos activa** para gestión de emergencias urbanas, implementada con **PostgreSQL 16**.

El proyecto modela incidentes, sensores, recursos, asignaciones, penalizaciones, auditoría y reglas activas mediante triggers, procedimientos almacenados, vistas y dataset reproducible.

> [!NOTE]
> La base final se llama `smart_city`. El flujo recomendado para el equipo es Docker, porque garantiza la misma versión de PostgreSQL y la misma carga inicial para todos.

---

## Contenido principal

| Ruta | Descripción |
| --- | --- |
| `database/create-tables.sql` | Crea tablas, constraints y relaciones. |
| `database/carga-dataset.sql` | Carga el dataset base desde `data/*.csv`. |
| `database/create-views.sql` | Crea vistas operativas y de monitoreo. |
| `database/create-triggers.sql` | Carga las reglas activas en el orden definido para `main`. |
| `database/triggers/` | Implementación modular de reglas validadoras, inteligencia, automatización, temporales y auditoría/control. |
| `database/store-procedures/` | Procedimientos almacenados complementarios. |
| `tests/` | Scripts SQL auto-verificables para validaciones, reglas activas, inteligencia y procedures. |
| `simulacion/` | Escenarios transaccionales de demostración. |

---

## Levantar con Docker — recomendado

### 1. Requisitos

- Docker Desktop en Windows/Mac, o Docker Engine + plugin `docker compose` en Linux.
- Verificación rápida:

```bash
docker --version
docker compose version
```

### 2. Crear la base desde cero

Desde la raíz del repo:

```bash
docker compose up -d
```

Docker expone PostgreSQL en el puerto **5433** del host para no chocar con un PostgreSQL local.

Datos de conexión:

| Campo | Valor |
| --- | --- |
| Host | `localhost` |
| Puerto | `5433` |
| Base | `smart_city` |
| Usuario | `postgres` |
| Contraseña | `password` |

Para ver cuándo terminó la inicialización:

```bash
docker compose logs postgres
```

Buscá el mensaje:

```txt
>>> Base de datos 'smart_city' inicializada correctamente.
```

### 3. Conectarse por consola dentro del contenedor

```bash
docker compose exec postgres psql -U postgres -d smart_city
```

Ejemplos útiles dentro de `psql`:

```sql
SELECT count(*) FROM Zona;
\dt
\dv
\q
```

### 4. Resetear la base Docker

> [!IMPORTANT]
> Los scripts de inicialización corren solo cuando el volumen está vacío. Si querés recargar tablas, dataset, vistas y triggers desde cero, tenés que borrar el volumen.

```bash
docker compose down -v
docker compose up -d
```

---

## Levantar sin Docker

### 1. Requisitos

- PostgreSQL 16 instalado localmente.
- `psql` disponible en la terminal.
- Un usuario con permisos para crear bases de datos. Los scripts asumen por defecto:
  - usuario: `postgres`
  - contraseña: `password`

### 2. Ejecutar migración completa

Desde la raíz del repo:

```bash
PGPASSWORD=password psql -h localhost -U postgres -f migrate.sql
```

En Windows PowerShell:

```powershell
$env:PGPASSWORD="password"
psql -h localhost -U postgres -f migrate.sql
```

`migrate.sql` recrea la base `smart_city` y ejecuta el flujo completo:

1. base de datos;
2. tablas;
3. dataset;
4. vistas;
5. reglas activas;
6. procedimientos almacenados.

> [!TIP]
> Si tu PostgreSQL local usa otro puerto, agregá `-p <puerto>` al comando `psql`.

---

## Ejecutar tests uno por uno

Los tests están pensados para correr contra una base `smart_city` cargada desde cero.

> [!WARNING]
> Los scripts de `tests/` son destructivos sobre tablas operativas (`Incidente`, `Asignacion`, `Evento`, `Penalizacion`, `Log`) y resetean estados/puntajes necesarios para verificar reglas. Para una corrida limpia, reseteá la base antes de probar.

### Opción A: usando Docker, sin instalar `psql` local

Desde la raíz del repo:

```bash
# 1. Validaciones de integridad y reglas validadoras
cat tests/test-triggers.sql | docker compose exec -T postgres psql -U postgres -d smart_city -v ON_ERROR_STOP=1

# 2. Reglas activas de automatización, sensores, R20 y P4
cat tests/test-reglas-activas.sql | docker compose exec -T postgres psql -U postgres -d smart_city -v ON_ERROR_STOP=1

# 3. Reglas de inteligencia: prioridad, puntaje y rebalanceo
cat tests/test-reglas-inteligencia.sql | docker compose exec -T postgres psql -U postgres -d smart_city -v ON_ERROR_STOP=1

# 4. Procedimientos almacenados
cat tests/test-procedures.sql | docker compose exec -T postgres psql -U postgres -d smart_city -v ON_ERROR_STOP=1
```

### Opción B: usando `psql` local contra Docker

```bash
PGPASSWORD=password psql -h localhost -p 5433 -U postgres -d smart_city -v ON_ERROR_STOP=1 -f tests/test-triggers.sql
PGPASSWORD=password psql -h localhost -p 5433 -U postgres -d smart_city -v ON_ERROR_STOP=1 -f tests/test-reglas-activas.sql
PGPASSWORD=password psql -h localhost -p 5433 -U postgres -d smart_city -v ON_ERROR_STOP=1 -f tests/test-reglas-inteligencia.sql
PGPASSWORD=password psql -h localhost -p 5433 -U postgres -d smart_city -v ON_ERROR_STOP=1 -f tests/test-procedures.sql
```

### Opción C: usando PostgreSQL local sin Docker

```bash
PGPASSWORD=password psql -h localhost -U postgres -d smart_city -v ON_ERROR_STOP=1 -f tests/test-triggers.sql
PGPASSWORD=password psql -h localhost -U postgres -d smart_city -v ON_ERROR_STOP=1 -f tests/test-reglas-activas.sql
PGPASSWORD=password psql -h localhost -U postgres -d smart_city -v ON_ERROR_STOP=1 -f tests/test-reglas-inteligencia.sql
PGPASSWORD=password psql -h localhost -U postgres -d smart_city -v ON_ERROR_STOP=1 -f tests/test-procedures.sql
```

---

## Comandos Docker frecuentes

```bash
docker compose up -d      # levantar en segundo plano
docker compose ps         # ver estado del contenedor
docker compose logs -f    # ver logs en vivo
docker compose stop       # apagar sin borrar datos
docker compose start      # volver a prender
docker compose down       # apagar y borrar contenedor, conserva volumen
docker compose down -v    # apagar y borrar volumen: reset total
```

---

## Documentación del TP

La documentación de consigna, decisiones de diseño y reglas activas está en `documentacion/`.

Archivos especialmente relevantes:

- `documentacion/Registro_Decisiones_Diseno.md`
- `documentacion/Tablas, Dominios y Reglas Activas.md`
- consigna PDF del TP
