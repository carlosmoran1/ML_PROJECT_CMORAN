CREATE OR REPLACE PROCEDURE `proyectos-cmoran-489000.data_procesada_commodities.SP_GENERA_MODELO_MIXTO_E_HISTORICO`()
BEGIN

  DECLARE v_load_date DATE DEFAULT CURRENT_DATE();

  -- =========================================================
  -- 0) BORRAR MODELOS CALCULADOS DE LA TABLA DIARIA
  -- =========================================================
  DELETE
  FROM `proyectos-cmoran-489000.data_procesada_commodities.predicciones_commodities`
  WHERE modelo IN ('model_mixto', 'ensamblado');


  -- =========================================================
  -- 1) ÚLTIMO VALOR REAL OBSERVADO (ANCLA INICIAL)
  -- =========================================================
  CREATE TEMP TABLE last_actual_wide AS
  SELECT
    Date,
    oro,
    plata,
    cobre,
    petroleo_brent,
    gas_natural
  FROM `proyectos-cmoran-489000.data_procesada_commodities.hechos_data_proc_commodities`
  QUALIFY ROW_NUMBER() OVER (ORDER BY Date DESC) = 1;

  CREATE TEMP TABLE last_actual_long AS
  SELECT 'oro'            AS commodity, CAST(oro AS FLOAT64)            AS actual_value FROM last_actual_wide
  UNION ALL
  SELECT 'plata'          AS commodity, CAST(plata AS FLOAT64)          AS actual_value FROM last_actual_wide
  UNION ALL
  SELECT 'cobre'          AS commodity, CAST(cobre AS FLOAT64)          AS actual_value FROM last_actual_wide
  UNION ALL
  SELECT 'petroleo_brent' AS commodity, CAST(petroleo_brent AS FLOAT64) AS actual_value FROM last_actual_wide
  UNION ALL
  SELECT 'gas_natural'    AS commodity, CAST(gas_natural AS FLOAT64)    AS actual_value FROM last_actual_wide;


  -- =========================================================
  -- 2) PASAR LAS PREDICCIONES DIARIAS A FORMATO LONG
  --    SOLO SARIMAX Y AUTOGLUON
  -- =========================================================
  CREATE TEMP TABLE preds_long AS
  SELECT fecha_prediccion, modelo, 'oro'            AS commodity, CAST(oro AS FLOAT64)            AS pred
  FROM `proyectos-cmoran-489000.data_procesada_commodities.predicciones_commodities`
  WHERE modelo IN ('sarimax', 'autogluon')

  UNION ALL
  SELECT fecha_prediccion, modelo, 'plata'          AS commodity, CAST(plata AS FLOAT64)          AS pred
  FROM `proyectos-cmoran-489000.data_procesada_commodities.predicciones_commodities`
  WHERE modelo IN ('sarimax', 'autogluon')

  UNION ALL
  SELECT fecha_prediccion, modelo, 'cobre'          AS commodity, CAST(cobre AS FLOAT64)          AS pred
  FROM `proyectos-cmoran-489000.data_procesada_commodities.predicciones_commodities`
  WHERE modelo IN ('sarimax', 'autogluon')

  UNION ALL
  SELECT fecha_prediccion, modelo, 'petroleo_brent' AS commodity, CAST(petroleo_brent AS FLOAT64) AS pred
  FROM `proyectos-cmoran-489000.data_procesada_commodities.predicciones_commodities`
  WHERE modelo IN ('sarimax', 'autogluon')

  UNION ALL
  SELECT fecha_prediccion, modelo, 'gas_natural'    AS commodity, CAST(gas_natural AS FLOAT64)    AS pred
  FROM `proyectos-cmoran-489000.data_procesada_commodities.predicciones_commodities`
  WHERE modelo IN ('sarimax', 'autogluon');


  -- =========================================================
  -- 3) JUNTAR SARIMAX + AUTOGLUON POR FECHA Y COMMODITY
  -- =========================================================
  CREATE TEMP TABLE base_pairs AS
  SELECT
    p.fecha_prediccion,
    p.commodity,
    MAX(IF(p.modelo = 'sarimax',   p.pred, NULL)) AS sarimax_pred,
    MAX(IF(p.modelo = 'autogluon', p.pred, NULL)) AS autogluon_pred,
    la.actual_value AS last_actual
  FROM preds_long p
  LEFT JOIN last_actual_long la
    ON p.commodity = la.commodity
  GROUP BY
    p.fecha_prediccion,
    p.commodity,
    la.actual_value
  HAVING
    COUNTIF(p.modelo = 'sarimax') > 0
    AND COUNTIF(p.modelo = 'autogluon') > 0;


  -- =========================================================
  -- 4) ORDEN TEMPORAL POR COMMODITY
  -- =========================================================
  CREATE TEMP TABLE ordered_base AS
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY commodity
      ORDER BY fecha_prediccion
    ) AS rn
  FROM base_pairs;


  -- =========================================================
  -- 5) CÁLCULO RECURSIVO DEL MODELO MIXTO
  --
  -- PRIMER DÍA:
  --   dirección = signo(SARIMAX_t1 - último_real)
  --   magnitud  = abs((AutoGluon_t1 - último_real) / último_real)
  --
  -- DÍAS SIGUIENTES:
  --   dirección = signo(SARIMAX_t - SARIMAX_t-1)
  --   magnitud  = abs((AutoGluon_t - AutoGluon_t-1) / AutoGluon_t-1)
  --
  --   mixed_t = mixed_t-1 * (1 +/- magnitud)
  -- =========================================================
  CREATE TEMP TABLE mixed_long AS
  WITH RECURSIVE mix AS (

    -- -------------------------
    -- Ancla: primer día
    -- -------------------------
    SELECT
      commodity,
      fecha_prediccion,
      rn,
      sarimax_pred,
      autogluon_pred,
      last_actual,
      CASE
        WHEN sarimax_pred > last_actual THEN  1
        WHEN sarimax_pred < last_actual THEN -1
        ELSE 0
      END AS dir_sarimax,
      COALESCE(ABS(SAFE_DIVIDE(autogluon_pred - last_actual, last_actual)), 0.0) AS pct_abs_autogluon,
      CASE
        WHEN sarimax_pred > last_actual THEN last_actual * (1 + COALESCE(ABS(SAFE_DIVIDE(autogluon_pred - last_actual, last_actual)), 0.0))
        WHEN sarimax_pred < last_actual THEN GREATEST(last_actual * (1 - COALESCE(ABS(SAFE_DIVIDE(autogluon_pred - last_actual, last_actual)), 0.0)), 0)
        ELSE last_actual
      END AS mixed_pred
    FROM ordered_base
    WHERE rn = 1

    UNION ALL

    -- -------------------------
    -- Recursión: días siguientes
    -- -------------------------
    SELECT
      b.commodity,
      b.fecha_prediccion,
      b.rn,
      b.sarimax_pred,
      b.autogluon_pred,
      b.last_actual,
      CASE
        WHEN b.sarimax_pred > m.sarimax_pred THEN  1
        WHEN b.sarimax_pred < m.sarimax_pred THEN -1
        ELSE 0
      END AS dir_sarimax,
      COALESCE(ABS(SAFE_DIVIDE(b.autogluon_pred - m.autogluon_pred, m.autogluon_pred)), 0.0) AS pct_abs_autogluon,
      CASE
        WHEN b.sarimax_pred > m.sarimax_pred THEN m.mixed_pred * (1 + COALESCE(ABS(SAFE_DIVIDE(b.autogluon_pred - m.autogluon_pred, m.autogluon_pred)), 0.0))
        WHEN b.sarimax_pred < m.sarimax_pred THEN GREATEST(m.mixed_pred * (1 - COALESCE(ABS(SAFE_DIVIDE(b.autogluon_pred - m.autogluon_pred, m.autogluon_pred)), 0.0)), 0)
        ELSE m.mixed_pred
      END AS mixed_pred
    FROM ordered_base b
    JOIN mix m
      ON b.commodity = m.commodity
     AND b.rn = m.rn + 1
  )
  SELECT
    commodity,
    fecha_prediccion,
    mixed_pred
  FROM mix;


  -- =========================================================
  -- 6) INSERTAR MODELO MIXTO EN LA TABLA DIARIA
  -- =========================================================
  INSERT INTO `proyectos-cmoran-489000.data_procesada_commodities.predicciones_commodities` (
    fecha_prediccion,
    oro,
    plata,
    cobre,
    petroleo_brent,
    gas_natural,
    modelo
  )
  SELECT
    fecha_prediccion,
    MAX(IF(commodity = 'oro',            mixed_pred, NULL)) AS oro,
    MAX(IF(commodity = 'plata',          mixed_pred, NULL)) AS plata,
    MAX(IF(commodity = 'cobre',          mixed_pred, NULL)) AS cobre,
    MAX(IF(commodity = 'petroleo_brent', mixed_pred, NULL)) AS petroleo_brent,
    MAX(IF(commodity = 'gas_natural',    mixed_pred, NULL)) AS gas_natural,
    'model_mixto' AS modelo
  FROM mixed_long
  GROUP BY fecha_prediccion;


  -- =========================================================
  -- 7) INSERTAR MODELO ENSAMBLADO EN LA TABLA DIARIA
  --    promedio simple = (sarimax + autogluon) / 2
  -- =========================================================
  INSERT INTO `proyectos-cmoran-489000.data_procesada_commodities.predicciones_commodities` (
    fecha_prediccion,
    oro,
    plata,
    cobre,
    petroleo_brent,
    gas_natural,
    modelo
  )
  SELECT
    fecha_prediccion,
    MAX(IF(commodity = 'oro',            SAFE_DIVIDE(sarimax_pred + autogluon_pred, 2), NULL)) AS oro,
    MAX(IF(commodity = 'plata',          SAFE_DIVIDE(sarimax_pred + autogluon_pred, 2), NULL)) AS plata,
    MAX(IF(commodity = 'cobre',          SAFE_DIVIDE(sarimax_pred + autogluon_pred, 2), NULL)) AS cobre,
    MAX(IF(commodity = 'petroleo_brent', SAFE_DIVIDE(sarimax_pred + autogluon_pred, 2), NULL)) AS petroleo_brent,
    MAX(IF(commodity = 'gas_natural',    SAFE_DIVIDE(sarimax_pred + autogluon_pred, 2), NULL)) AS gas_natural,
    'ensamblado' AS modelo
  FROM base_pairs
  GROUP BY fecha_prediccion;


  -- =========================================================
  -- 8) BORRAR COMPLETA LA PARTICIÓN DEL DÍA EN HISTÓRICO
  -- =========================================================
  DELETE
  FROM `proyectos-cmoran-489000.data_procesada_commodities.predicciones_commodities_historico`
  WHERE data_date_part = v_load_date;


  -- =========================================================
  -- 9) INSERTAR TODA LA DIARIA EN LA HISTÓRICA
  -- =========================================================
  INSERT INTO `proyectos-cmoran-489000.data_procesada_commodities.predicciones_commodities_historico` (
    fecha_prediccion,
    oro,
    plata,
    cobre,
    petroleo_brent,
    gas_natural,
    modelo,
    data_date_part
  )
  SELECT
    fecha_prediccion,
    oro,
    plata,
    cobre,
    petroleo_brent,
    gas_natural,
    modelo,
    v_load_date AS data_date_part
  FROM `proyectos-cmoran-489000.data_procesada_commodities.predicciones_commodities`;

END;