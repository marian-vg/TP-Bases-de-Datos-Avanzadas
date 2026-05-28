-- ============================================================================
-- SMART CITY - SCRIPT DE CREACIÓN DE BASE DE DATOS
-- ============================================================================
-- Este script se ejecuta conectado a la base de datos administrativa 'postgres'
-- para limpiar y crear la base de datos 'smart_city' desde cero de forma limpia.
--
-- ============================================================================
--
-- Elimina la BD en caso de que exista y la tengan ocupada con cosas nada que ver 
-- (comenten esta linea si no es el caso)
DROP DATABASE IF EXISTS smart_city;

-- Crear la base de datos
CREATE DATABASE smart_city;
