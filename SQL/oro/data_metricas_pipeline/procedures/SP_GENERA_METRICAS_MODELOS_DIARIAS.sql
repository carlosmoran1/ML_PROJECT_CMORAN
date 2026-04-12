CREATE OR REPLACE PROCEDURE `proyectos-cmoran-489000.data_metricas_pipeline.SP_GENERA_METRICAS_MODELOS_DIARIAS`()
BEGIN

  -- Paso 1: materializar predicciones sin duplicados
  CREATE OR REPLACE TEMP TABLE tmp_pred_long AS
  WITH pred_long_raw AS (
    SELECT data_date_part, fecha_prediccion, modelo, 'oro'            AS commodity, CAST(oro            AS FLOAT64) AS predicted_value FROM `proyectos-cmoran-489000.data_procesada_commodities.predicciones_commodities_historico`
    UNION ALL
    SELECT data_date_part, fecha_prediccion, modelo, 'plata',                        CAST(plata          AS FLOAT64) FROM `proyectos-cmoran-489000.data_procesada_commodities.predicciones_commodities_historico`
    UNION ALL
    SELECT data_date_part, fecha_prediccion, modelo, 'cobre',                        CAST(cobre          AS FLOAT64) FROM `proyectos-cmoran-489000.data_procesada_commodities.predicciones_commodities_historico`
    UNION ALL
    SELECT data_date_part, fecha_prediccion, modelo, 'petroleo_brent',               CAST(petroleo_brent AS FLOAT64) FROM `proyectos-cmoran-489000.data_procesada_commodities.predicciones_commodities_historico`
    UNION ALL
    SELECT data_date_part, fecha_prediccion, modelo, 'gas_natural',                  CAST(gas_natural    AS FLOAT64) FROM `proyectos-cmoran-489000.data_procesada_commodities.predicciones_commodities_historico`
  )
  SELECT data_date_part, fecha_prediccion, modelo, commodity, predicted_value
  FROM (
    SELECT *,
      ROW_NUMBER() OVER (
        PARTITION BY data_date_part, fecha_prediccion, modelo, commodity
        ORDER BY data_date_part DESC
      ) AS rn
    FROM pred_long_raw
    WHERE modelo IN ('sarimax', 'autogluon', 'model_mixto','ensamblado')
      AND predicted_value IS NOT NULL
  )
  WHERE rn = 1;

  -- Paso 2: materializar actuals con previo (deduplicado por fecha+commodity)
  CREATE OR REPLACE TEMP TABLE tmp_actual AS
  WITH actual_long AS (
    SELECT CAST(Date AS DATE) AS fecha, 'oro'            AS commodity, CAST(oro            AS FLOAT64) AS actual_real FROM `proyectos-cmoran-489000.data_procesada_commodities.hechos_data_proc_commodities`
    UNION ALL
    SELECT CAST(Date AS DATE),          'plata',                        CAST(plata          AS FLOAT64) FROM `proyectos-cmoran-489000.data_procesada_commodities.hechos_data_proc_commodities`
    UNION ALL
    SELECT CAST(Date AS DATE),          'cobre',                        CAST(cobre          AS FLOAT64) FROM `proyectos-cmoran-489000.data_procesada_commodities.hechos_data_proc_commodities`
    UNION ALL
    SELECT CAST(Date AS DATE),          'petroleo_brent',               CAST(petroleo_brent AS FLOAT64) FROM `proyectos-cmoran-489000.data_procesada_commodities.hechos_data_proc_commodities`
    UNION ALL
    SELECT CAST(Date AS DATE),          'gas_natural',                  CAST(gas_natural    AS FLOAT64) FROM `proyectos-cmoran-489000.data_procesada_commodities.hechos_data_proc_commodities`
  ),
  actual_dedup AS (
    -- Deduplicar por si la tabla procesada tiene filas repetidas por fecha
    SELECT fecha, commodity, actual_real
    FROM (
      SELECT *, ROW_NUMBER() OVER (PARTITION BY fecha, commodity ORDER BY fecha) AS rn
      FROM actual_long
      WHERE actual_real IS NOT NULL
    )
    WHERE rn = 1
  )
  SELECT
    fecha,
    commodity,
    actual_real,
    LAG(actual_real) OVER (PARTITION BY commodity ORDER BY fecha) AS actual_previo
  FROM actual_dedup;

  -- Paso 3: overwrite partición por partición (evita TRUNCATE + INSERT global)
  -- Borra solo las particiones que seran sobreescritas
  DELETE FROM `proyectos-cmoran-489000.data_metricas_pipeline.metricas_modelos_diarias`
  WHERE data_date_part IN (SELECT DISTINCT data_date_part FROM tmp_pred_long);

  -- Paso 4: insertar resultados
  INSERT INTO `proyectos-cmoran-489000.data_metricas_pipeline.metricas_modelos_diarias` (
    data_date_part,
    fecha_prediccion,
    modelo,
    commodity,
    actual_previo,
    actual_real,
    predicted_value,
    abs_error,
    ape,
    direccion_predicha,
    direccion_real,
    direccion_ok
  )
  SELECT
    p.data_date_part,
    p.fecha_prediccion,
    p.modelo,
    p.commodity,
    a.actual_previo,
    a.actual_real,
    p.predicted_value,
    ABS(a.actual_real - p.predicted_value)                                                        AS abs_error,
    SAFE_DIVIDE(ABS(a.actual_real - p.predicted_value), NULLIF(ABS(a.actual_real), 0))     AS ape,
    CASE
      WHEN a.actual_previo IS NULL THEN NULL
      WHEN p.predicted_value > a.actual_previo THEN 1
      WHEN p.predicted_value < a.actual_previo THEN -1
      ELSE 0
    END AS direccion_predicha,
    CASE
      WHEN a.actual_previo IS NULL THEN NULL
      WHEN a.actual_real > a.actual_previo THEN 1
      WHEN a.actual_real < a.actual_previo THEN -1
      ELSE 0
    END AS direccion_real,
    CASE
      WHEN a.actual_previo IS NULL THEN NULL
      WHEN (
        CASE WHEN p.predicted_value > a.actual_previo THEN 1 WHEN p.predicted_value < a.actual_previo THEN -1 ELSE 0 END
      ) = (
        CASE WHEN a.actual_real   > a.actual_previo THEN 1 WHEN a.actual_real   < a.actual_previo THEN -1 ELSE 0 END
      ) THEN 1
      ELSE 0
    END AS direccion_ok
  FROM tmp_pred_long p
  JOIN tmp_actual a
    ON p.commodity     = a.commodity
   AND p.fecha_prediccion = a.fecha  -- ← si sigue sin datos, loguea las fechas de ambas temp tables
  WHERE a.actual_real IS NOT NULL;

DELETE FROM `proyectos-cmoran-489000.data_metricas_pipeline.metricas_modelos_diarias` t
WHERE t.predicted_value IS NOT NULL
  AND EXISTS (
    SELECT 1
    FROM `proyectos-cmoran-489000.data_metricas_pipeline.metricas_modelos_diarias` x
    WHERE x.fecha_prediccion = t.fecha_prediccion
      AND x.modelo           = t.modelo
      AND x.commodity        = t.commodity
      AND x.predicted_value  = t.predicted_value
      AND x.predicted_value IS NOT NULL
      AND x.data_date_part < t.data_date_part
  );
END;