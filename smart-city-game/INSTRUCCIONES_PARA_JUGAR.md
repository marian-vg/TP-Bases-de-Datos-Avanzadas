# Instrucciones para jugar Smart City Game

Guía rápida para levantar el juego que prueba la BD `smart_city` usando Docker.

## Levantar el juego

Ejecutar desde la raíz del repo (`TP-Bases-de-Datos-Avanzadas`):

```bash
# 1) Levantar la BD canónica del TP
docker compose up -d

# 2) Crear el archivo de entorno del juego si todavía no existe
cp -n smart-city-game/.env.example smart-city-game/.env

# 3) Levantar backend + frontend del juego
cd smart-city-game
docker compose up -d --build
```

Luego abrir:

- Juego: <http://localhost:5173>
- Healthcheck backend: <http://localhost:8000/api/v1/health>

## Cerrar el juego

Desde la carpeta `smart-city-game`:

```bash
docker compose down
```

Si también querés cerrar la BD del TP, volver a la raíz del repo y ejecutar:

```bash
cd ..
docker compose down
```

## Reiniciar desde cero la BD

Usar esto solo si necesitás recargar esquema/datos desde cero, porque borra el volumen de PostgreSQL:

```bash
cd ..
docker compose down -v
docker compose up -d
```

Después, levantar de nuevo el juego:

```bash
cd smart-city-game
docker compose up -d --build
```
