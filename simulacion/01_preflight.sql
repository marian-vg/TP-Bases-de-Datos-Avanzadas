\echo '>>> 01 - PREFLIGHT Y CAPACIDADES'

DO $$
DECLARE
    v_codigo TEXT;
    v_objeto TEXT;
    v_instalado BOOLEAN;
BEGIN
    PERFORM pg_temp.sim_afirmar(
        '01-PREFLIGHT', 'Dataset de recursos',
        (SELECT count(*) >= 20 FROM Recurso),
        'Dataset operativo disponible.', 'El dataset no posee recursos suficientes.'
    );
    PERFORM pg_temp.sim_afirmar(
        '01-PREFLIGHT', 'Dataset de sensores',
        (SELECT count(*) > 0 FROM Sensor),
        'Sensores disponibles para escenarios IoT.', 'No hay sensores cargados.'
    );
    PERFORM pg_temp.sim_afirmar(
        '01-PREFLIGHT', 'Vistas minimas',
        pg_temp.sim_relacion_existe('vincidentesactivos')
        AND pg_temp.sim_relacion_existe('vrecursosdisponibles')
        AND pg_temp.sim_relacion_existe('vincidentescriticos')
        AND pg_temp.sim_relacion_existe('vhistorialincidentes')
        AND pg_temp.sim_relacion_existe('vrecursospenalizados'),
        'Las cinco vistas minimas de la consigna estan instaladas.',
        'Falta al menos una vista minima de la consigna.'
    );

    FOR v_codigo, v_objeto IN
        SELECT codigo, objeto_esperado FROM sim_cobertura ORDER BY codigo
    LOOP
        v_instalado := CASE
            WHEN v_objeto IS NULL THEN FALSE
            WHEN v_objeto LIKE 'trg_%' THEN EXISTS (
                SELECT 1 FROM pg_trigger
                WHERE NOT tgisinternal AND lower(tgname) = lower(v_objeto) AND tgenabled <> 'D'
            )
            WHEN v_objeto LIKE 'sp_%' THEN pg_temp.sim_objeto_existe('p', v_objeto)
            WHEN v_objeto LIKE 'fn_%' THEN pg_temp.sim_objeto_existe('f', v_objeto)
            ELSE pg_temp.sim_relacion_existe(v_objeto)
        END;

        UPDATE sim_cobertura
        SET objeto_instalado = v_instalado,
            estado = CASE WHEN v_instalado THEN 'INFO' ELSE 'SKIP' END,
            detalle = CASE
                WHEN v_instalado THEN 'Objeto instalado; pendiente de validacion funcional.'
                ELSE 'Objeto esperado no instalado por la migracion canonica.'
            END
        WHERE codigo = v_codigo;
    END LOOP;

    PERFORM pg_temp.sim_registrar(
        '01-PREFLIGHT', 'Migracion canonica incompleta', 'INFO',
        'La existencia de archivos SQL no implica que sus objetos hayan sido cargados en la base.'
    );
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.sim_capturar_error('01-PREFLIGHT', 'Ejecucion del preflight', SQLERRM);
END;
$$;
