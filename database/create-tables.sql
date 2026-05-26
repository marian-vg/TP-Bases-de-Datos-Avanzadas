-- ============================================================================
-- 1. TABLAS INDEPENDIENTES (CATÁLOGOS Y PARÁMETROS BASE)
--
-- $env:PGPASSWORD="password"; psql -h localhost -U postgres -d db_name -f
-- database/create-tables.sql  
-- ============================================================================

CREATE TABLE EstadoIncidente (
    id_estado_incidente SERIAL PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE TipoIncidente (
    id_tipo_incidente SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE,
    descripcion TEXT
);

CREATE TABLE Gravedad (
    id_gravedad SERIAL PRIMARY KEY,
    nombre VARCHAR(30) NOT NULL UNIQUE
);

CREATE TABLE NivelRiesgo (
    id_nivel_riesgo SERIAL PRIMARY KEY,
    nombre VARCHAR(30) NOT NULL UNIQUE,
    valor INT NOT NULL
);

CREATE TABLE TipoSensor (
    id_tipo_sensor SERIAL PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE TipoEvento (
    id_tipo_evento SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE,
    descripcion TEXT
);

CREATE TABLE TipoRecurso (
    id_tipo_recurso SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE,
    descripcion TEXT
);

CREATE TABLE EstadoRecurso (
    id_estado_recurso SERIAL PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE TipoPenalizacion (
    id_tipo_penalizacion SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE,
    puntaje INT NOT NULL
);

CREATE TABLE ParametrosSistema (
    nombre_parametro VARCHAR(100) PRIMARY KEY,
    numero NUMERIC(12, 4) NOT NULL
);

-- ============================================================================
-- 2. TABLAS CON DEPENDENCIAS DE PRIMER NIVEL (CONFIGURACIÓN GEOGRÁFICA Y SLA)
-- ============================================================================

CREATE TABLE SLA (
    id_sla SERIAL PRIMARY KEY,
    fk_gravedad_id INT NOT NULL,
    tiempo_respuesta_minutos INT NOT NULL,
    CONSTRAINT fk_sla_gravedad FOREIGN KEY (fk_gravedad_id) 
        REFERENCES Gravedad(id_gravedad) ON DELETE RESTRICT
);

CREATE TABLE Zona (
    id_zona SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE,
    fk_nivel_riesgo_id INT NOT NULL,
    CONSTRAINT fk_zona_nivel_riesgo FOREIGN KEY (fk_nivel_riesgo_id) 
        REFERENCES NivelRiesgo(id_nivel_riesgo) ON DELETE RESTRICT
);

-- ============================================================================
-- 3. TABLAS ASOCIADAS A ENTIDADES OPERATIVAS Y DISPOSITIVOS (SENSORES E IoT)
-- ============================================================================

CREATE TABLE Sensor (
    id_sensor SERIAL PRIMARY KEY,
    fk_tipo_sensor_id INT NOT NULL,
    fk_zona_id INT NOT NULL,
    marca VARCHAR(100),
    modelo VARCHAR(100),
    nombre VARCHAR(100) NOT NULL,
    fecha_instalado DATE NOT NULL,
    fecha_mantenimiento DATE,
    CONSTRAINT fk_sensor_tipo FOREIGN KEY (fk_tipo_sensor_id) 
        REFERENCES TipoSensor(id_tipo_sensor) ON DELETE RESTRICT,
    CONSTRAINT fk_sensor_zona FOREIGN KEY (fk_zona_id) 
        REFERENCES Zona(id_zona) ON DELETE RESTRICT
);

CREATE TABLE Recurso (
    id_recurso SERIAL PRIMARY KEY,
    fk_tipo_recurso_id INT NOT NULL,
    fk_zona_base_id INT NOT NULL, -- Representa su base física/pertenencia original
    fk_estado_recurso_id INT NOT NULL,
    CONSTRAINT fk_recurso_tipo FOREIGN KEY (fk_tipo_recurso_id) 
        REFERENCES TipoRecurso(id_tipo_recurso) ON DELETE RESTRICT,
    CONSTRAINT fk_recurso_zona_base FOREIGN KEY (fk_zona_base_id) 
        REFERENCES Zona(id_zona) ON DELETE RESTRICT,
    CONSTRAINT fk_recurso_estado FOREIGN KEY (fk_estado_recurso_id) 
        REFERENCES EstadoRecurso(id_estado_recurso) ON DELETE RESTRICT
);

-- Tabla intermedia (M:N) para gestionar las zonas en las que un recurso está habilitado (R10 / R15)
CREATE TABLE ZonaRecurso (
    id_zona INT NOT NULL,
    id_recurso INT NOT NULL,
    PRIMARY KEY (id_zona, id_recurso),
    CONSTRAINT fk_zonarecurso_zona FOREIGN KEY (id_zona) 
        REFERENCES Zona(id_zona) ON DELETE CASCADE,
    CONSTRAINT fk_zonarecurso_recurso FOREIGN KEY (id_recurso) 
        REFERENCES Recurso(id_recurso) ON DELETE CASCADE
);

-- ============================================================================
-- 4. TABLAS DE EVENTOS E INCIDENTES
-- ============================================================================

CREATE TABLE Evento (
    id_evento SERIAL PRIMARY KEY,
    fk_sensor_id INT NOT NULL,
    fk_tipo_evento_id INT NOT NULL,
    fecha_evento DATE NOT NULL DEFAULT CURRENT_DATE,
    hora_evento TIME NOT NULL DEFAULT CURRENT_TIME,
    CONSTRAINT fk_evento_sensor FOREIGN KEY (fk_sensor_id) 
        REFERENCES Sensor(id_sensor) ON DELETE RESTRICT,
    CONSTRAINT fk_evento_tipo FOREIGN KEY (fk_tipo_evento_id) 
        REFERENCES TipoEvento(id_tipo_evento) ON DELETE RESTRICT
);

CREATE TABLE Incidente (
    id_incidente SERIAL PRIMARY KEY,
    fk_evento_id INT NULL, -- Permite NULL si el incidente es cargado manualmente por un operador
    fk_tipo_incidente_id INT NOT NULL,
    fk_gravedad_id INT NOT NULL,
    fk_estado_incidente_id INT NOT NULL,
    fk_zona_id INT NOT NULL,
    fecha_hora_registro TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    descripcion TEXT NOT NULL,
    prioridad INT NOT NULL,
    CONSTRAINT fk_incidente_evento FOREIGN KEY (fk_evento_id) 
        REFERENCES Evento(id_evento) ON DELETE SET NULL,
    CONSTRAINT fk_incidente_tipo FOREIGN KEY (fk_tipo_incidente_id) 
        REFERENCES TipoIncidente(id_tipo_incidente) ON DELETE RESTRICT,
    CONSTRAINT fk_incidente_gravedad FOREIGN KEY (fk_gravedad_id) 
        REFERENCES Gravedad(id_gravedad) ON DELETE RESTRICT,
    CONSTRAINT fk_incidente_estado FOREIGN KEY (fk_estado_incidente_id) 
        REFERENCES EstadoIncidente(id_estado_incidente) ON DELETE RESTRICT,
    CONSTRAINT fk_incidente_zona FOREIGN KEY (fk_zona_id) 
        REFERENCES Zona(id_zona) ON DELETE RESTRICT
);

-- ============================================================================
-- 5. TABLAS DE ASIGNACIÓN, LOGÍSTICA Y CONTROL SANCIONATORIO
-- ============================================================================

CREATE TABLE Asignacion (
    id_asignacion SERIAL PRIMARY KEY,
    fk_recurso_id INT NOT NULL,
    fk_incidente_id INT NOT NULL,
    timestamp_asignacion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    timestamp_llegada TIMESTAMP NULL, -- Se completa mediante trigger/SP al arribar al lugar (DD-01)
    timestamp_finalizacion TIMESTAMP NULL, -- Se completa al liberar el recurso
    estado_exito BOOLEAN NULL, -- NULL = En curso, TRUE = Exitoso, FALSE = Fallido (R4)
    CONSTRAINT fk_asignacion_recurso FOREIGN KEY (fk_recurso_id) 
        REFERENCES Recurso(id_recurso) ON DELETE RESTRICT,
    CONSTRAINT fk_asignacion_incidente FOREIGN KEY (fk_incidente_id) 
        REFERENCES Incidente(id_incidente) ON DELETE RESTRICT
);

CREATE TABLE Penalizacion (
    id_penalizacion SERIAL PRIMARY KEY,
    fk_recurso_id INT NOT NULL,
    fk_tipo_penalizacion_id INT NOT NULL,
    fecha DATE NOT NULL DEFAULT CURRENT_DATE,
    hora TIME NOT NULL DEFAULT CURRENT_TIME,
    motivo TEXT NOT NULL,
    CONSTRAINT fk_penalizacion_recurso FOREIGN KEY (fk_recurso_id) 
        REFERENCES Recurso(id_recurso) ON DELETE CASCADE,
    CONSTRAINT fk_penalizacion_tipo FOREIGN KEY (fk_tipo_penalizacion_id) 
        REFERENCES TipoPenalizacion(id_tipo_penalizacion) ON DELETE RESTRICT
);

-- ============================================================================
-- 6. TABLA DE AUDITORÍA UNIFICADA (SISTEMA DE LOG COMPLETO)
-- ============================================================================

-- Estructura de auditoría centralizada polimórfica (DD-03).
-- Mantiene relaciones lógicas a través de 'tablaAfectada' e 'idTablaAfectada'.
CREATE TABLE Log (
    id_log BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    tablaAfectada VARCHAR(50) NOT NULL,    -- Nombre de la tabla física mutada
    idTablaAfectada BIGINT NOT NULL,       -- ID / PK del registro afectado
    operacion VARCHAR(10) NOT NULL,        -- 'INSERT', 'UPDATE' o 'DELETE' (R19)
    trigger_disparador VARCHAR(100) NULL,  -- Nombre del trigger. Es NULL si la acción fue manual (R19)
    detalle JSONB NOT NULL                 -- Payload con datos consolidados, estados y motivos (R18)
);
