"""
Generador de dataset base para TP1 - Bases de Datos Activas
Sistema Inteligente de Gestión de Emergencias Urbanas (Smart City)
UADER - FCyT - 2026

Este script genera los CSVs para poblar las entidades base de la DB.
No incluye Incidentes, Eventos, Asignaciones, Penalizaciones ni Logs
(esos se generan en la etapa de simulación).
"""

import csv
import random
from datetime import date, timedelta
from pathlib import Path

random.seed(42)  # reproducibilidad
OUT = Path(__file__).parent

# =============================================================================
# 1. CATÁLOGOS (datos de referencia / lookup tables)
# =============================================================================

# ----- TipoIncidente -----
tipos_incidente = [
    (1,  "Accidente de tránsito",   "Colisiones, atropellamientos, vuelcos en vía pública"),
    (2,  "Incendio estructural",    "Incendio en viviendas, comercios o edificios"),
    (3,  "Incendio forestal",       "Fuego en pastizales, basurales o zonas con vegetación"),
    (4,  "Emergencia médica",       "Paro cardíaco, ACV, traumatismo, descompensación"),
    (5,  "Robo / Asalto",           "Hechos delictivos en curso o recientes"),
    (6,  "Violencia doméstica",     "Situaciones de violencia en el ámbito familiar"),
    (7,  "Disturbios",              "Tumultos, riñas, alteración del orden público"),
    (8,  "Fuga de gas",             "Pérdidas de gas natural o GLP"),
    (9,  "Corte de energía",        "Cortes prolongados o fallas en red eléctrica"),
    (10, "Inundación urbana",       "Anegamientos por lluvia o desborde de cuencas"),
    (11, "Derrumbe",                "Caída de estructuras, mampostería o árboles"),
    (12, "Persona desaparecida",    "Búsqueda de personas extraviadas"),
    (13, "Materiales peligrosos",   "Derrame químico, vertido tóxico, fugas industriales"),
    (14, "Rescate acuático",        "Personas en riesgo en ríos, arroyos o piletas"),
]

# ----- EstadoIncidente -----
estados_incidente = [
    (1, "Pendiente"),
    (2, "En proceso"),
    (3, "Resuelto"),
    (4, "Escalado"),
    (5, "Cancelado"),
]

# ----- Gravedad (1 a 5) -----
gravedades = [
    (1, "Baja"),
    (2, "Moderada"),
    (3, "Alta"),
    (4, "Crítica"),
    (5, "Catastrófica"),
]

# ----- SLA (tiempo de respuesta en minutos por nivel de gravedad) -----
slas = [
    (1, 1, 30),   # Baja        -> 30 min
    (2, 2, 20),   # Moderada    -> 20 min
    (3, 3, 10),   # Alta        -> 10 min
    (4, 4, 5),    # Crítica     -> 5 min
    (5, 5, 3),    # Catastrófica-> 3 min
]

# ----- NivelRiesgo -----
niveles_riesgo = [
    (1, "Bajo",     1),
    (2, "Medio",    2),
    (3, "Alto",     3),
    (4, "Crítico",  4),
]

# ----- TipoSensor -----
tipos_sensor = [
    (1, "Cámara de vigilancia"),
    (2, "Detector de humo"),
    (3, "Detector de gas"),
    (4, "Botón de pánico"),
    (5, "Sensor de movimiento"),
    (6, "Sensor sísmico"),
    (7, "Sensor de inundación"),
    (8, "Detector acústico de disparos"),
    (9, "Sensor de temperatura"),
    (10, "Sensor de calidad del aire"),
]

# ----- TipoEvento -----
tipos_evento = [
    (1,  "Detección de humo",            "Activación de sensor por presencia de humo"),
    (2,  "Detección de gas",             "Lectura anómala de concentración de gas"),
    (3,  "Movimiento sospechoso",        "Patrón de movimiento inusual detectado por cámara o PIR"),
    (4,  "Activación de botón de pánico", "Pulsado manual de dispositivo de emergencia"),
    (5,  "Detección acústica de disparo", "Patrón sonoro compatible con arma de fuego"),
    (6,  "Temperatura crítica",          "Lectura por encima del umbral configurado"),
    (7,  "Inundación detectada",         "Presencia de agua en zona monitoreada"),
    (8,  "Vibración sísmica",            "Movimiento telúrico registrado"),
    (9,  "Calidad de aire degradada",    "Partículas o gases por encima del umbral"),
    (10, "Cámara fuera de línea",        "Pérdida de señal de dispositivo de video"),
]

# ----- TipoRecurso -----
tipos_recurso = [
    (1,  "Ambulancia SAME",           "Unidad de emergencia médica avanzada"),
    (2,  "Ambulancia básica",         "Unidad de traslado y atención primaria"),
    (3,  "Autobomba",                 "Camión de bomberos para incendios estructurales"),
    (4,  "Bomberos forestales",       "Unidad especializada en incendios de vegetación"),
    (5,  "Patrullero",                "Móvil policial de respuesta rápida"),
    (6,  "Móvil de tránsito",         "Unidad de control y siniestros viales"),
    (7,  "Defensa civil",             "Móvil de asistencia ante catástrofes"),
    (8,  "Cuadrilla de gas",          "Personal técnico de red de gas"),
    (9,  "Cuadrilla eléctrica",       "Personal técnico de red eléctrica"),
    (10, "Móvil municipal",           "Servicios urbanos generales"),
    (11, "Rescate acuático",          "Equipo de salvamento en agua"),
    (12, "Helicóptero sanitario",     "Aeronave de emergencias médicas"),
]

# ----- EstadoRecurso -----
estados_recurso = [
    (1, "Disponible"),
    (2, "Ocupado"),
    (3, "Fuera de servicio"),
    (4, "En mantenimiento"),
    (5, "En tránsito"),
]

# ----- TipoPenalizacion -----
tipos_penalizacion = [
    (1, "Demora leve",            5),
    (2, "Demora moderada",       15),
    (3, "Demora grave",          25),
    (4, "Falla en intervención", 30),
    (5, "Abandono de servicio",  40),
    (6, "No respuesta",          50),
    (7, "Error de procedimiento", 20),
]

# =============================================================================
# 2. ZONAS (barrios de Paraná, ER - contexto UADER)
# =============================================================================

# 12 zonas con nivel de riesgo asignado (mix realista)
zonas_data = [
    ("Centro",            3),  # Alto - mucha circulación, comercio
    ("Puerto Viejo",      3),  # Alto - zona ribereña, conflictiva
    ("Bajada Grande",     2),  # Medio
    ("Echeverría",        2),  # Medio
    ("Los Pinos",         1),  # Bajo - residencial
    ("San Agustín",       2),  # Medio
    ("Anacleto Medina",   3),  # Alto
    ("Mosconi",           4),  # Crítico - barrio popular
    ("La Floresta",       1),  # Bajo
    ("Macarone",          2),  # Medio
    ("Pueblo Belgrano",   1),  # Bajo
    ("Cinco Esquinas",    3),  # Alto
]
zonas = [(i + 1, nombre, riesgo) for i, (nombre, riesgo) in enumerate(zonas_data)]

# =============================================================================
# 3. SENSORES (10 a 20 por zona, aleatorio)
# =============================================================================

marcas_sensor = ["Bosch", "Honeywell", "Hikvision", "Dahua", "Siemens",
                 "Schneider", "Axis", "ABB", "Sensata", "Pelco", "Tyco"]

def gen_modelo():
    """Genera un código de modelo realista del tipo MARCA-X-NNN."""
    letra = random.choice("ABCDEFGHKMPRTX")
    return f"{letra}{random.randint(100, 9999)}-{random.choice(['A','B','C','S','X','PRO','LITE'])}"

def fecha_aleatoria(inicio: date, fin: date) -> date:
    delta = (fin - inicio).days
    return inicio + timedelta(days=random.randint(0, delta))

sensores = []
sensor_id = 1
for zona_id, _, _ in zonas:
    cantidad = random.randint(10, 20)
    for _ in range(cantidad):
        tipo_id = random.randint(1, len(tipos_sensor))
        tipo_nombre = tipos_sensor[tipo_id - 1][1]
        marca = random.choice(marcas_sensor)
        modelo = gen_modelo()
        nombre = f"SEN-{zona_id:02d}-{sensor_id:04d}"
        # Las fechas de instalación y mantenimiento NO se guardan en el CSV: se generan
        # en carga-dataset.sql relativas a CURRENT_DATE (para que el dataset no caduque).
        # Igual consumimos los mismos valores aleatorios, para no alterar el resto del
        # dataset (recursos y zona_recurso, que vienen después en el mismo stream).
        fecha_inst = fecha_aleatoria(date(2020, 1, 1), date(2025, 6, 30))
        if random.random() < 0.4:
            _ = fecha_aleatoria(fecha_inst, date(2026, 5, 1))
        sensores.append((sensor_id, tipo_id, zona_id, marca, modelo, nombre))
        sensor_id += 1

# =============================================================================
# 4. RECURSOS (20 a 40 por zona, aleatorio)
# =============================================================================

# Distribución de tipos de recurso (no todos equiprobables - hay más patrulleros
# y ambulancias que helicópteros sanitarios)
pesos_tipo_recurso = {
    1: 15,   # Ambulancia SAME
    2: 10,   # Ambulancia básica
    3: 10,   # Autobomba
    4: 5,    # Bomberos forestales
    5: 20,   # Patrullero
    6: 8,    # Móvil de tránsito
    7: 7,    # Defensa civil
    8: 6,    # Cuadrilla de gas
    9: 6,    # Cuadrilla eléctrica
    10: 8,   # Móvil municipal
    11: 3,   # Rescate acuático
    12: 2,   # Helicóptero sanitario
}
tipos_ids = list(pesos_tipo_recurso.keys())
pesos = list(pesos_tipo_recurso.values())

# Distribución de estados para el SEED INICIAL.
# Sólo se usan estados que NO dependen de una asignación activa:
#   - Ocupado y En tránsito requieren un registro en Asignacion (no existe aún
#     en el dataset base; se genera en la etapa de simulación), por lo que se
#     excluyen acá para no dejar la DB en un estado inconsistente.
pesos_estado_recurso = {
    1: 85,   # Disponible
    3: 7,    # Fuera de servicio
    4: 8,    # En mantenimiento
}
estados_ids = list(pesos_estado_recurso.keys())
pesos_estados = list(pesos_estado_recurso.values())

recursos = []
recurso_id = 1
for zona_id, _, _ in zonas:
    cantidad = random.randint(20, 40)
    for _ in range(cantidad):
        tipo_id = random.choices(tipos_ids, weights=pesos, k=1)[0]
        estado_id = random.choices(estados_ids, weights=pesos_estados, k=1)[0]
        recursos.append((recurso_id, tipo_id, zona_id, estado_id))
        recurso_id += 1

# =============================================================================
# 5. ZonaRecurso (tabla N:M para zonas habilitadas adicionales)
# =============================================================================
# Cada recurso siempre está habilitado en su zona base. Adicionalmente,
# entre el 25% y 35% de los recursos están habilitados en 1 o 2 zonas vecinas
# (esto habilita la regla R15 de rebalanceo y R10 de validación de zona).

zona_recurso = []
total_zonas = len(zonas)
for recurso_id_x, _, zona_base, _ in recursos:
    # zona base siempre habilitada
    zona_recurso.append((zona_base, recurso_id_x))
    if random.random() < 0.30:
        cantidad_extra = random.choice([1, 1, 2])  # mayoría 1 extra
        zonas_disponibles = [z for z in range(1, total_zonas + 1) if z != zona_base]
        zonas_extras = random.sample(zonas_disponibles, cantidad_extra)
        for ze in zonas_extras:
            zona_recurso.append((ze, recurso_id_x))

# =============================================================================
# 6. ParametrosSistema (parámetros configurables del sistema)
# =============================================================================
parametros = [
    ("MAX_RECURSOS_POR_INCIDENTE",           "5"),
    ("MIN_RECURSOS_INCIDENTE_CRITICO",       "2"),    # R5: asignación múltiple
    ("PUNTAJE_BLOQUEO_RECURSO",              "75"),   # bloquear recurso si suma X puntos
    ("MINUTOS_REACTIVACION_RECURSO",         "60"),   # R17: reactivación automática
    ("MINUTOS_DUPLICADO_INCIDENTE",          "10"),   # R11: ventana de duplicación
    ("GRAVEDAD_MINIMA_CRITICA",              "4"),    # de qué nivel se considera crítico
    ("BONUS_PRIORIDAD_ZONA_RIESGO",          "10"),   # R13: extra por zona de riesgo alto
    ("MINUTOS_REVISION_SENSOR",              "90"),   # cada cuánto debe revisarse un sensor
    ("ESCALAR_FACTOR_GRAVEDAD",              "1"),    # R16: cuánto sube la gravedad al escalar
    ("SENSOR_DECAIMIENTO_CONFIANZA_SEMANAL", "5"),    # R21: % de confianza que pierde el sensor por semana
    ("SENSOR_UMBRAL_CONFIANZA_MINIMO",       "80"),   # R21: confianza mínima para generar incidente
]

# =============================================================================
# 7. TipoIncidenteTipoRecurso (qué tipos de recurso aplican a cada tipo de incidente)
# =============================================================================
# Define la flota válida por tipo de incidente. El motor de asignación solo
# despacha recursos cuyo tipo figure aquí (un incendio no recibe un patrullero).
tipo_incidente_tipo_recurso = [
    (1, 1), (1, 2), (1, 5), (1, 6),          # Accidente de tránsito
    (2, 3), (2, 1), (2, 7),                   # Incendio estructural
    (3, 4), (3, 3), (3, 7),                   # Incendio forestal
    (4, 1), (4, 2), (4, 12),                  # Emergencia médica
    (5, 5),                                   # Robo / Asalto
    (6, 5), (6, 2),                           # Violencia doméstica
    (7, 5), (7, 7),                           # Disturbios
    (8, 8), (8, 3), (8, 7),                   # Fuga de gas
    (9, 9), (9, 10),                          # Corte de energía
    (10, 7), (10, 10), (10, 11),             # Inundación urbana
    (11, 7), (11, 3), (11, 1),               # Derrumbe
    (12, 5), (12, 7),                         # Persona desaparecida
    (13, 7), (13, 8), (13, 3), (13, 1),      # Materiales peligrosos
    (14, 11), (14, 1), (14, 7),              # Rescate acuático
]

# =============================================================================
# ESCRITURA DE LOS CSVs
# =============================================================================

def write_csv(filename, header, rows):
    path = OUT / filename
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, quoting=csv.QUOTE_MINIMAL, lineterminator="\n")
        w.writerow(header)
        w.writerows(rows)
    print(f"  {filename:35s}  {len(rows):>5d} filas")

print("\n=== Generando dataset base ===\n")

write_csv("01_tipo_incidente.csv",
          ["id", "nombre", "descripcion"], tipos_incidente)

write_csv("02_estado_incidente.csv",
          ["id", "nombre"], estados_incidente)

write_csv("03_gravedad.csv",
          ["id", "nombre"], gravedades)

write_csv("04_sla.csv",
          ["id", "gravedad_id", "tiempo_respuesta_minutos"], slas)

write_csv("05_nivel_riesgo.csv",
          ["id", "nombre", "valor"], niveles_riesgo)

write_csv("06_zona.csv",
          ["id", "nombre", "nivel_riesgo_id"], zonas)

write_csv("07_tipo_sensor.csv",
          ["id", "nombre"], tipos_sensor)

write_csv("08_tipo_evento.csv",
          ["id", "nombre", "descripcion"], tipos_evento)

write_csv("09_tipo_recurso.csv",
          ["id", "nombre", "descripcion"], tipos_recurso)

write_csv("10_estado_recurso.csv",
          ["id", "nombre"], estados_recurso)

write_csv("11_tipo_penalizacion.csv",
          ["id", "nombre", "puntaje"], tipos_penalizacion)

write_csv("12_sensor.csv",
          ["id", "tipo_sensor_id", "zona_id", "marca", "modelo", "nombre"], sensores)

write_csv("13_recurso.csv",
          ["id", "tipo_recurso_id", "zona_id", "estado_recurso_id"], recursos)

write_csv("14_zona_recurso.csv",
          ["zona_id", "recurso_id"], zona_recurso)

write_csv("15_parametros_sistema.csv",
          ["nombre_parametro", "valor"], parametros)

write_csv("16_tipo_incidente_tipo_recurso.csv",
          ["tipo_incidente_id", "tipo_recurso_id"], tipo_incidente_tipo_recurso)

# =============================================================================
# RESUMEN
# =============================================================================
print("\n=== Resumen ===")
print(f"  Zonas:                {len(zonas)}")
print(f"  Sensores totales:     {len(sensores)}")
print(f"  Recursos totales:     {len(recursos)}")
print(f"  Filas zona_recurso:   {len(zona_recurso)}")
print(f"  Mapeos inc/recurso:   {len(tipo_incidente_tipo_recurso)}")

# Distribución de sensores por zona
print("\n  Distribución sensores por zona:")
for zona_id, nombre, _ in zonas:
    cant = sum(1 for s in sensores if s[2] == zona_id)
    print(f"    Zona {zona_id:2d} ({nombre:18s}): {cant:3d} sensores")

# Distribución de recursos por zona
print("\n  Distribución recursos por zona:")
for zona_id, nombre, _ in zonas:
    cant = sum(1 for r in recursos if r[2] == zona_id)
    print(f"    Zona {zona_id:2d} ({nombre:18s}): {cant:3d} recursos")
