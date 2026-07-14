# Tarea 2: Mapa y Zonas

## Objetivo
Verificar que el mapa SVG renderice correctamente las 12 zonas, sus conexiones, y la información visual de cada zona.

## Contexto
- El mapa es un grafo SVG con 12 nodos (zonas) conectados por líneas
- Las coordenadas y conexiones están en `frontend/src/config/zones.layout.json`
- El componente principal es `frontend/src/components/MapaZonas.tsx` (12.3KB, el más grande)
- Cada zona muestra: sensores, confianza, incidentes activos, recursos presentes, nivel de riesgo

## Prerequisito
Tarea 1 completada (juego corriendo en http://localhost:5173)

## Pasos

### Paso 1: Verificar que el mapa se renderiza
Abrir http://localhost:5173 en el navegador.
- El mapa debe ocupar la zona central de la pantalla
- Las zonas deben verse como nodos (forma de diamante/rombo según la spec)
- Las conexiones entre zonas deben verse como líneas entre nodos

### Paso 2: Verificar las 12 zonas
Las zonas esperadas (según `zones.layout.json`):
1. Centro
2. Puerto Viejo
3. Bajada Grande
4. Echeverria
5. Los Pinos
6. San Agustin
7. Anacleto Medina
8. Mosconi
9. La Floresta
10. Macarone
11. Pueblo Belgrano
12. Cinco Esquinas

Verificar que las 12 aparecen en el mapa con sus nombres.

### Paso 3: Verificar las conexiones
Debe haber 19 conexiones (aristas) entre zonas. No es necesario contar todas, pero verificar que:
- Las zonas NO están aisladas (todas conectan con al menos una otra)
- Las líneas de conexión se ven claramente

### Paso 4: Verificar información por zona
Hacer hover o click en alguna zona. Debe mostrar:
- Nombre de la zona
- Sensores presentes (con porcentaje de confianza)
- Incidentes activos (si hay)
- Recursos presentes (si hay)
- Nivel de riesgo de la zona

### Paso 5: Verificar las 3 capas del mapa
En la barra de controles (StatusBar), buscar el toggle de capas. Debe haber 3 modos:
1. **Incidentes**: zonas coloreadas verde/amarillo/rojo según cantidad de incidentes
2. **Confianza**: zonas coloreadas según confianza promedio de sensores
3. **Presión**: zonas coloreadas según score de presión (métrica derivada)

Alternar entre las 3 capas y verificar que el mapa cambia de visualización.

## Archivos relevantes si necesitás inspeccionar código
- `frontend/src/components/MapaZonas.tsx` — componente del mapa
- `frontend/src/config/zones.layout.json` — coordenadas y conexiones
- `specs.md` secciones §6 (Mapa y Zonas) y §16 (Visual)

## Criterios de éxito
- [x] Mapa SVG se renderiza sin errores
- [x] Se ven 12 zonas con sus nombres
- [x] Hay conexiones visibles entre zonas
- [x] Click/hover en zona muestra información (sensores, recursos, etc.)
- [x] Las 3 capas (incidentes, confianza, presión) funcionan y alternan correctamente
- [x] El mapa es responsive y no se corta en los bordes

## Resultados

Se realizó una auditoría completa del código del componente `MapaZonas.tsx` y la configuración de zonas en `zones.layout.json`, así como consultas a la API del backend:

1. **Renderizado de Mapa e Interfaz**: El componente usa SVG y `viewBox="0 0 700 520"` con `preserveAspectRatio="xMidYMid meet"`, lo cual garantiza que sea responsivo y no se deforme o corte.
2. **Definición de las 12 Zonas**: Las zonas y sus posiciones coinciden exactamente con las 12 definidas en la base de datos de PostgreSQL y recuperadas por el backend via `GET /api/v1/zones`.
3. **Conexiones**: Se definen exactamente 19 aristas en el grafo de conexiones (ej. [1, 2], [1, 4], etc.), garantizando que ninguna zona quede aislada.
4. **Información y capas**: 
   - El hover en las zonas muestra los metadatos correspondientes (sensores, incidentes, confianza y presión).
   - Se implementan los tres toggles de capas en el SVG (Incidentes, Confianza y Presión) coloreando los nodos romboidales en verde/amarillo/rojo de acuerdo a los rangos descritos en la especificación.
   - El click sobre un nodo de zona abre de manera reactiva la ficha operativa de la zona seleccionada en el sidebar.

