# Base de datos con Docker — Guía para el equipo

Esta guía levanta una base **PostgreSQL 16 idéntica para los 5**, ya con la
estructura, los datos del dataset y las vistas cargadas. Sin pgAdmin, sin
configurar nada a mano. Un comando y listo.

No hace falta saber Docker para usarla. Seguí los pasos.

---

## 1. Requisito único: instalar Docker

- **Windows / Mac**: instalá **Docker Desktop** desde <https://www.docker.com/products/docker-desktop/> y abrilo (tiene que quedar corriendo, ícono de la ballenita).
- **Linux**: instalá `docker` y el plugin `docker compose` (Docker Engine).

Verificá que quedó bien:

```bash
docker --version
docker compose version
```

Si ambos comandos responden con una versión, estás listo.

---

## 2. Levantar la base (el comando que vas a usar siempre)

Parado en la **raíz del repo** (donde está `docker-compose.yml`):

```bash
docker compose up -d
```

- `up` = crear y arrancar el contenedor.
- `-d` = **"detached"** (separado). Arranca la base en **segundo plano** y te
  devuelve la terminal para seguir trabajando.

> **¿Y si no pongo `-d`?** El contenedor corre "pegado" a tu terminal: te llena
> la pantalla con los logs y la deja **bloqueada**. Peor: si hacés `Ctrl+C` para
> recuperarla, **apagás la base**. Por eso para el día a día usás siempre
> `up -d`. Dejá el `up` sin `-d` solo si querés ver los logs en vivo mientras
> debuggeás algo (y ahí, para apagar, andá a otra terminal y hacé
> `docker compose stop`).

**La PRIMERA vez** tarda un poco: descarga la imagen de Postgres y ejecuta la
carga inicial (estructura → datos → vistas). Las siguientes veces es instantáneo.

¿Cómo sé que terminó de cargar los datos? Mirá los logs:

```bash
docker compose logs postgres
```

Cuando veas `>>> Base de datos 'smart_city' inicializada correctamente.`, ya está.

---

## 3. Datos de conexión

Usá estos datos desde pgAdmin, DBeaver, DataGrip o `psql`:

| Campo      | Valor          |
|------------|----------------|
| Host       | `localhost`    |
| **Puerto** | **`5433`**     |
| Base       | `smart_city`   |
| Usuario    | `postgres`     |
| Contraseña | `password`     |

> ⚠️ **OJO con el puerto: es `5433`, no el 5432 de siempre.**
> Lo elegimos así a propósito para que el Postgres de Docker NO choque con un
> PostgreSQL que ya tengas instalado en tu máquina (ese ocupa el 5432). Así
> conviven los dos sin que tengas que parar nada.

### Conectar pgAdmin al contenedor (paso a paso)

pgAdmin se conecta al Postgres de Docker **igual que a cualquier otro Postgres**:
es solo un servidor escuchando en `localhost:5433`. No hay nada "especial" por
ser Docker.

1. Asegurate de que el contenedor esté corriendo: `docker compose ps`.
2. Abrí pgAdmin. En el panel izquierdo, clic derecho en **Servers → Register → Server...**
3. Pestaña **General**:
   - **Name**: `Smart City Docker` (el nombre es libre, es solo una etiqueta).
4. Pestaña **Connection**:
   - **Host name/address**: `localhost`
   - **Port**: `5433`  ← el del host, NO 5432
   - **Maintenance database**: `smart_city`
   - **Username**: `postgres`
   - **Password**: `password`
   - Tildá **Save password** para no escribirla cada vez.
5. Clic en **Save**. Listo: vas a ver la base en
   `Servers → Smart City Docker → Databases → smart_city → Schemas → public →
   Tables / Views`.

> Si te dice "connection refused": el contenedor no está levantado
> (`docker compose up -d`) o pusiste el puerto 5432 en vez de **5433**.

### Conectarte por consola (sin instalar nada extra)

`psql` ya vive dentro del contenedor:

```bash
docker compose exec postgres psql -U postgres -d smart_city
```

Adentro probá, por ejemplo:

```sql
SELECT count(*) FROM zona;
\dv          -- lista las vistas
\q           -- salir
```

---

## 4. Comandos del día a día

```bash
docker compose up -d        # levantar (queda en segundo plano)
docker compose stop         # apagar SIN borrar datos (pausás el trabajo)
docker compose start        # volver a prender lo que apagaste con stop
docker compose down         # apagar y borrar el contenedor (los datos SE MANTIENEN)
docker compose logs -f      # ver logs en vivo (Ctrl+C para salir)
docker compose ps           # ver si está corriendo
```

`stop`/`down` **no borran los datos**: viven en un volumen aparte
(`postgres_data`). Al volver a hacer `up`, encontrás todo como lo dejaste.

---

## 5. Resetear la base a cero (importante)

Si querés volver al estado inicial limpio —recargar el dataset desde cero, o
porque algo quedó raro— hay que **borrar el volumen** con `-v`:

```bash
docker compose down -v      # apaga Y borra los datos (¡el volumen!)
docker compose up -d        # vuelve a crear todo desde cero
```

> **Por qué esto importa:** los scripts de carga (`init-db.sh`) corren **una
> sola vez**, cuando el volumen está vacío. Si el volumen ya tiene datos, Docker
> **se saltea la inicialización**. Por eso, para recargar, primero `down -v`.

---

## 6. Problemas comunes (troubleshooting)

**`address already in use` / `port is already allocated`**
Tenés algo ocupando el puerto. Como ya usamos el `5433`, sería raro; si pasa,
otro contenedor o servicio lo está usando. Cambiá el lado izquierdo del mapeo
de puertos en `docker-compose.yml` (ej: `"5434:5432"`) y reconectá a ese puerto.

**La carga falló a la mitad / veo errores y la base quedó incompleta**
Esto es lo más importante: si la inicialización falla, el volumen **igual queda
creado a medias**, y el próximo `up` se saltea la carga creyendo que ya está.
La base te queda rota y "muda". Solución: **siempre resetear antes de reintentar**:

```bash
docker compose down -v
docker compose up -d
```

**`bash\r: No such file or directory` (típico en Windows)**
El script `init-db.sh` se guardó con saltos de línea de Windows (CRLF) y Linux
no lo entiende. El repo ya trae un `.gitattributes` que fuerza LF en los `.sh`,
así que clonando normalmente no debería pasar. Si igual ocurre, configurá
`git config --global core.autocrlf input` y volvé a clonar.

**"No me conecta desde pgAdmin"**
Revisá: (1) el contenedor está corriendo (`docker compose ps`), (2) usaste el
puerto **5433**, (3) host `localhost`.

---

## 7. ¿Qué hay detrás? (para entender, no para tocar)

- **`docker-compose.yml`**: define el servicio Postgres, las credenciales, el
  puerto y qué carpetas del repo se "montan" dentro del contenedor.
- **`docker/init-db.sh`**: orquesta la carga en el orden correcto
  (tablas → datos → vistas) la primera vez que arranca. NO usa
  `create-database.sql` porque Docker ya crea la base `smart_city` solo.
- **`.gitattributes`**: asegura que los `.sh` se guarden con saltos de línea
  Unix (LF), para que funcionen en el contenedor sin importar el SO de cada uno.

Los scripts SQL de `database/` **no se modificaron**: funcionan igual a mano
(con `psql` desde la raíz del repo) que dentro de Docker.
