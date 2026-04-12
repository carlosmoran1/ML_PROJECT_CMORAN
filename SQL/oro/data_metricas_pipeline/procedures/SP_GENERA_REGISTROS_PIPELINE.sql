CREATE OR REPLACE PROCEDURE `proyectos-cmoran-489000.data_metricas_pipeline.SP_GENERA_REGISTROS_PIPELINE`()
BEGIN
  DECLARE v_today DATE DEFAULT CURRENT_DATE("America/Santiago");
  DECLARE v_now TIMESTAMP DEFAULT CURRENT_TIMESTAMP();

  DELETE
  FROM `proyectos-cmoran-489000.data_metricas_pipeline.registros_pipeline`
  WHERE fecha_ejecucion = v_today;

  INSERT INTO `proyectos-cmoran-489000.data_metricas_pipeline.registros_pipeline` (
    fecha_ejecucion,
    ts_evento,
    etapa,
    estado,
    tabla_objetivo,
    registros,
    data_min,
    data_max,
    umbral_esperado,
    detalle
  )
  WITH raw_stage AS (
    SELECT
      'RAW_EXTERNAL' AS etapa,
      'data_raw_indicadores.hechos_data_raw_commodities' AS tabla_objetivo,
      COUNT(*) AS registros,
      MIN(CAST(Date AS DATE)) AS data_min,
      MAX(CAST(Date AS DATE)) AS data_max,
      NULL AS umbral_esperado
    FROM `proyectos-cmoran-489000.data_raw_indicadores.hechos_data_raw_commodities`
    WHERE Date IS NOT NULL
  ),
  proc_stage AS (
    SELECT
      'DATA_PROC' AS etapa,
      'data_procesada_commodities.hechos_data_proc_commodities' AS tabla_objetivo,
      COUNT(*) AS registros,
      MIN(CAST(Date AS DATE)) AS data_min,
      MAX(CAST(Date AS DATE)) AS data_max,
      NULL AS umbral_esperado
    FROM `proyectos-cmoran-489000.data_procesada_commodities.hechos_data_proc_commodities`
    WHERE Date IS NOT NULL
  ),
  pred_stage AS (
    SELECT
      CASE modelo
        WHEN 'sarimax' THEN 'PRED_SARIMAX'
        WHEN 'autogluon' THEN 'PRED_AUTOGLUON'
        WHEN 'model_mixto' THEN 'PRED_MODELO_MIXTO'
        ELSE CONCAT('PRED_', UPPER(modelo))
      END AS etapa,
      'data_procesada_commodities.predicciones_commodities' AS tabla_objetivo,
      COUNT(*) AS registros,
      MIN(fecha_prediccion) AS data_min,
      MAX(fecha_prediccion) AS data_max,
      10 AS umbral_esperado
    FROM `proyectos-cmoran-489000.data_procesada_commodities.predicciones_commodities`
    WHERE modelo IN ('sarimax', 'autogluon', 'model_mixto')
    GROUP BY modelo
  ),
  hist_stage AS (
    SELECT
      CASE modelo
        WHEN 'sarimax' THEN 'HIST_SARIMAX_HOY'
        WHEN 'autogluon' THEN 'HIST_AUTOGLUON_HOY'
        WHEN 'model_mixto' THEN 'HIST_MODELO_MIXTO_HOY'
        ELSE CONCAT('HIST_', UPPER(modelo), '_HOY')
      END AS etapa,
      'data_procesada_commodities.predicciones_commodities_historico' AS tabla_objetivo,
      COUNT(*) AS registros,
      MIN(fecha_prediccion) AS data_min,
      MAX(fecha_prediccion) AS data_max,
      10 AS umbral_esperado
    FROM `proyectos-cmoran-489000.data_procesada_commodities.predicciones_commodities_historico`
    WHERE data_date_part = v_today
      AND modelo IN ('sarimax', 'autogluon', 'model_mixto')
    GROUP BY modelo
  ),
  all_stages AS (
    SELECT * FROM raw_stage
    UNION ALL
    SELECT * FROM proc_stage
    UNION ALL
    SELECT * FROM pred_stage
    UNION ALL
    SELECT * FROM hist_stage
  )
  SELECT
    v_today AS fecha_ejecucion,
    v_now AS ts_evento,
    etapa,
    CASE
      WHEN etapa IN ('RAW_EXTERNAL', 'DATA_PROC') AND registros > 0 THEN 'ok'
      WHEN etapa IN ('RAW_EXTERNAL', 'DATA_PROC') AND registros = 0 THEN 'error'
      WHEN etapa LIKE 'PRED_%' AND registros = umbral_esperado THEN 'ok'
      WHEN etapa LIKE 'PRED_%' AND registros BETWEEN 1 AND umbral_esperado - 1 THEN 'warn'
      WHEN etapa LIKE 'PRED_%' AND registros = 0 THEN 'error'
      WHEN etapa LIKE 'HIST_%' AND registros = umbral_esperado THEN 'ok'
      WHEN etapa LIKE 'HIST_%' AND registros BETWEEN 1 AND umbral_esperado - 1 THEN 'warn'
      WHEN etapa LIKE 'HIST_%' AND registros = 0 THEN 'error'
      ELSE 'warn'
    END AS estado,
    tabla_objetivo,
    registros,
    data_min,
    data_max,
    umbral_esperado,
    FORMAT('registros=%d | rango=%s a %s', registros, CAST(data_min AS STRING), CAST(data_max AS STRING)) AS detalle
  FROM all_stages;
END;