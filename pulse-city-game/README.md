# Pulse City Game

Simulador visual para la BD activa `smart_city`, encapsulado dentro de este repo en `pulse-city-game/` sin modificar el esquema canonico del TP.

## Estructura

- `backend/`: FastAPI, scheduler, operador simulado y mundo fisico.
- `frontend/`: React + Vite para mapa, hotbar y paneles.
- `resources/`: assets visuales.

## Ejecutar

### One click

Desde la raiz del repo puedes levantar todo junto con:

```powershell
.\start-pulse-city.ps1
```

O con doble click / terminal clasica de Windows:

```cmd
start-pulse-city.cmd
```

Opciones utiles:

```powershell
.\start-pulse-city.ps1 -NoBuild
.\start-pulse-city.ps1 -NoOpenBrowser
```

### Stack Docker recomendado

Desde la raiz del TP, levantar primero la BD canonica:

```powershell
Set-Location "C:\Users\Gime\Desktop\TP-Bases-de-Datos-Avanzadas"
docker compose up -d
```

Luego levantar el simulador:

```powershell
Set-Location "C:\Users\Gime\Desktop\TP-Bases-de-Datos-Avanzadas\pulse-city-game"
docker compose up -d
```

URLs:

- Frontend: `http://localhost:5173`
- Backend: `http://localhost:8000/api/v1/health`

### Backend

```powershell
Set-Location "C:\Users\Gime\Desktop\TP-Bases-de-Datos-Avanzadas\pulse-city-game\backend"
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

### Frontend

```powershell
Set-Location "C:\Users\Gime\Desktop\TP-Bases-de-Datos-Avanzadas\pulse-city-game\frontend"
npm run dev -- --host 0.0.0.0 --port 5173
```

## Requisitos

- La BD del TP debe estar levantada en `localhost:5433`.
- La BD se levanta desde el `docker-compose.yml` canonico de la raiz del TP, no desde este subproyecto.
- Credenciales por defecto:
  - DB `smart_city`
  - user `postgres`
  - password `password`

## Notas

- El juego usa polling contra `/api/v1/state`.
- No agregar logica de negocio duplicada al backend si ya existe en triggers/procedures.
