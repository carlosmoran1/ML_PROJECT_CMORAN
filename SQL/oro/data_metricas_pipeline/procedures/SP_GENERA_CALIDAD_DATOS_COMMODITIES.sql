CREATE OR REPLACE PROCEDURE `proyectos-cmoran-489000.data_metricas_pipeline.sp_genera_calidad_datos_commodities`()
BEGIN
  DECLARE v_today DATE DEFAULT CURRENT_DATE("America/Santiago");
  DECLARE v_now TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
  DECLARE v_table STRING DEFAULT 'data_procesada_commodities.hechos_data_proc_commodities';
  DECLARE v_min_date DATE;
  DECLARE v_last_date DATE;
  DECLARE v_expected_date DATE;

  SET v_expected_date = CASE EXTRACT(DAYOFWEEK FROM v_today)
    WHEN 1 THEN DATE_SUB(v_today, INTERVAL 2 DAY)  -- domingo -> viernes
    WHEN 2 THEN DATE_SUB(v_today, INTERVAL 3 DAY)  -- lunes -> viernes
    WHEN 7 THEN DATE_SUB(v_today, INTERVAL 1 DAY)  -- sábado -> viernes
    ELSE DATE_SUB(v_today, INTERVAL 1 DAY)         -- resto -> día anterior
  END;

  DELETE
  FROM `proyectos-cmoran-489000.data_metricas_pipeline.hechos_calidad_datos_commodities`
  WHERE fecha_revision = v_today
    AND tabla_monitoreada = v_table;

  CREATE TEMP TABLE base AS
  SELECT
    SAFE_CAST(Date AS DATE) AS data_date,
    SAFE_CAST(petroleo_brent AS FLOAT64) AS petroleo_brent,
    SAFE_CAST(oro AS FLOAT64) AS oro,
    SAFE_CAST(gas_natural AS FLOAT64) AS gas_natural,
    SAFE_CAST(cobre AS FLOAT64) AS cobre,
    SAFE_CAST(plata AS FLOAT64) AS plata,
    SAFE_CAST(vix AS FLOAT64) AS vix,
    SAFE_CAST(sp500 AS FLOAT64) AS sp500,
    SAFE_CAST(shanghai AS FLOAT64) AS shanghai,
    SAFE_CAST(emergentes AS FLOAT64) AS emergentes,
    SAFE_CAST(`Nikkei` AS FLOAT64) AS `Nikkei`,
    SAFE_CAST(`DAX` AS FLOAT64) AS `DAX`,
    SAFE_CAST(`FTSE` AS FLOAT64) AS `FTSE`,
    SAFE_CAST(AAPL AS FLOAT64) AS AAPL,
    SAFE_CAST(NVDA AS FLOAT64) AS NVDA,
    SAFE_CAST(MSFT AS FLOAT64) AS MSFT,
    SAFE_CAST(AMZN AS FLOAT64) AS AMZN,
    SAFE_CAST(GOOGL AS FLOAT64) AS GOOGL,
    SAFE_CAST(BRK_B AS FLOAT64) AS BRK_B,
    SAFE_CAST(JPM AS FLOAT64) AS JPM,
    SAFE_CAST(UNH AS FLOAT64) AS UNH,
    SAFE_CAST(TSM AS FLOAT64) AS TSM,
    SAFE_CAST(AMD AS FLOAT64) AS AMD,
    SAFE_CAST(SPY AS FLOAT64) AS SPY,
    SAFE_CAST(QQQ AS FLOAT64) AS QQQ,
    SAFE_CAST(DIA AS FLOAT64) AS DIA,
    SAFE_CAST(NEM AS FLOAT64) AS NEM,
    SAFE_CAST(KGC AS FLOAT64) AS KGC,
    SAFE_CAST(AEM AS FLOAT64) AS AEM,
    SAFE_CAST(PAAS AS FLOAT64) AS PAAS,
    SAFE_CAST(WPM AS FLOAT64) AS WPM,
    SAFE_CAST(AG AS FLOAT64) AS AG,
    SAFE_CAST(FCX AS FLOAT64) AS FCX,
    SAFE_CAST(SCCO AS FLOAT64) AS SCCO,
    SAFE_CAST(BHP AS FLOAT64) AS BHP,
    SAFE_CAST(EQT AS FLOAT64) AS EQT,
    SAFE_CAST(CTRA AS FLOAT64) AS CTRA,
    SAFE_CAST(LNG AS FLOAT64) AS LNG,
    SAFE_CAST(XOM AS FLOAT64) AS XOM,
    SAFE_CAST(CVX AS FLOAT64) AS CVX,
    SAFE_CAST(SHEL AS FLOAT64) AS SHEL,
    SAFE_CAST(dolar_index AS FLOAT64) AS dolar_index,
    SAFE_CAST(tasa_10y AS FLOAT64) AS tasa_10y,
    SAFE_CAST(tasa_2y AS FLOAT64) AS tasa_2y,
    SAFE_CAST(tasa_5y AS FLOAT64) AS tasa_5y
  FROM `proyectos-cmoran-489000.data_procesada_commodities.hechos_data_proc_commodities`
  WHERE Date IS NOT NULL;

  SET v_min_date = (SELECT MIN(data_date) FROM base);
  SET v_last_date = (SELECT MAX(data_date) FROM base);

  IF v_last_date IS NULL THEN

    INSERT INTO `proyectos-cmoran-489000.data_metricas_pipeline.hechos_calidad_datos_commodities`
    SELECT
      v_today,
      v_now,
      v_table,
      'freshness',
      'no_data_available',
      CAST(NULL AS STRING),
      CAST(NULL AS DATE),
      CAST(NULL AS FLOAT64),
      0.0,
      'error',
      'La tabla monitoreada no tiene registros con Date válido';

  ELSE

    CREATE TEMP TABLE long_daily AS
    SELECT
      data_date,
      variable,
      SAFE_CAST(valor AS FLOAT64) AS valor
    FROM base
    UNPIVOT INCLUDE NULLS (
      valor FOR variable IN (
        petroleo_brent, oro, gas_natural, cobre, plata,
        vix, sp500, shanghai, emergentes, `Nikkei`, `DAX`, `FTSE`,
        AAPL, NVDA, MSFT, AMZN, GOOGL, BRK_B, JPM, UNH, TSM, AMD,
        SPY, QQQ, DIA,
        NEM, KGC, AEM, PAAS, WPM, AG, FCX, SCCO, BHP, EQT, CTRA, LNG, XOM, CVX, SHEL,
        dolar_index, tasa_10y, tasa_2y, tasa_5y
      )
    );

    -- Frescura
    INSERT INTO `proyectos-cmoran-489000.data_metricas_pipeline.hechos_calidad_datos_commodities`
    SELECT
      v_today,
      v_now,
      v_table,
      'freshness',
      'days_lag_vs_expected',
      CAST(NULL AS STRING),
      v_last_date,
      CAST(GREATEST(DATE_DIFF(v_expected_date, v_last_date, DAY), 0) AS FLOAT64),
      0.0,
      CASE WHEN v_last_date >= v_expected_date THEN 'ok' ELSE 'error' END,
      FORMAT(
        'ultima_fecha=%s | fecha_esperada=%s',
        CAST(v_last_date AS STRING),
        CAST(v_expected_date AS STRING)
      );

    -- Duplicados por fecha
    INSERT INTO `proyectos-cmoran-489000.data_metricas_pipeline.hechos_calidad_datos_commodities`
    SELECT
      v_today,
      v_now,
      v_table,
      'duplicates',
      'duplicate_dates',
      CAST(NULL AS STRING),
      CAST(NULL AS DATE),
      CAST(COUNT(*) - COUNT(DISTINCT data_date) AS FLOAT64),
      0.0,
      CASE WHEN COUNT(*) - COUNT(DISTINCT data_date) = 0 THEN 'ok' ELSE 'error' END,
      FORMAT('filas=%d | fechas_unicas=%d', COUNT(*), COUNT(DISTINCT data_date))
    FROM base;

    -- Gaps de días hábiles
    INSERT INTO `proyectos-cmoran-489000.data_metricas_pipeline.hechos_calidad_datos_commodities`
    WITH calendar AS (
      SELECT d AS data_date
      FROM UNNEST(GENERATE_DATE_ARRAY(v_min_date, v_last_date)) AS d
      WHERE EXTRACT(DAYOFWEEK FROM d) NOT IN (1, 7)
    ),
    existing_dates AS (
      SELECT DISTINCT data_date
      FROM base
    ),
    missing_days AS (
      SELECT c.data_date
      FROM calendar c
      LEFT JOIN existing_dates e
        ON c.data_date = e.data_date
      WHERE e.data_date IS NULL
    )
    SELECT
      v_today,
      v_now,
      v_table,
      'gaps',
      'missing_business_days',
      CAST(NULL AS STRING),
      CAST(NULL AS DATE),
      CAST(COUNT(*) AS FLOAT64),
      0.0,
      CASE WHEN COUNT(*) = 0 THEN 'ok' ELSE 'error' END,
      COALESCE(
        STRING_AGG(CAST(data_date AS STRING), ', ' ORDER BY data_date LIMIT 10),
        'sin gaps'
      )
    FROM missing_days;

    -- % nulos últimos 20 días hábiles
    INSERT INTO `proyectos-cmoran-489000.data_metricas_pipeline.hechos_calidad_datos_commodities`
    WITH last_20_days AS (
      SELECT data_date
      FROM (
        SELECT DISTINCT data_date
        FROM base
        ORDER BY data_date DESC
        LIMIT 20
      )
    ),
    null_stats AS (
      SELECT
        variable,
        COUNT(*) AS obs_20d,
        COUNTIF(valor IS NULL) AS nulls_20d,
        100 * SAFE_DIVIDE(COUNTIF(valor IS NULL), COUNT(*)) AS pct_nulls_20d
      FROM long_daily
      WHERE data_date IN (SELECT data_date FROM last_20_days)
      GROUP BY variable
    )
    SELECT
      v_today,
      v_now,
      v_table,
      'nulls',
      'pct_nulls_20d',
      variable,
      v_last_date,
      pct_nulls_20d,
      10.0,
      CASE
        WHEN pct_nulls_20d >= 20 THEN 'error'
        WHEN pct_nulls_20d >= 10 THEN 'warn'
        ELSE 'ok'
      END,
      FORMAT('nulls=%d | obs=%d', nulls_20d, obs_20d)
    FROM null_stats;

    -- Null en última fecha
    INSERT INTO `proyectos-cmoran-489000.data_metricas_pipeline.hechos_calidad_datos_commodities`
    SELECT
      v_today,
      v_now,
      v_table,
      'nulls',
      'is_null_latest_date',
      variable,
      data_date,
      CAST(IF(valor IS NULL, 1, 0) AS FLOAT64),
      0.0,
      CASE WHEN valor IS NULL THEN 'error' ELSE 'ok' END,
      FORMAT('valor=%s', CAST(valor AS STRING))
    FROM long_daily
    WHERE data_date = v_last_date;

    -- Outlier z-score última fecha vs 30 obs previas
    INSERT INTO `proyectos-cmoran-489000.data_metricas_pipeline.hechos_calidad_datos_commodities`
    WITH non_nulls AS (
      SELECT *
      FROM long_daily
      WHERE valor IS NOT NULL
    ),
    stats_30 AS (
      SELECT
        data_date,
        variable,
        valor,
        AVG(valor) OVER (
          PARTITION BY variable
          ORDER BY data_date
          ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS avg_30,
        STDDEV_SAMP(valor) OVER (
          PARTITION BY variable
          ORDER BY data_date
          ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS std_30
      FROM non_nulls
    ),
    latest_stats AS (
      SELECT
        data_date,
        variable,
        valor,
        avg_30,
        std_30,
        SAFE_DIVIDE(ABS(valor - avg_30), NULLIF(std_30, 0)) AS zscore_30
      FROM stats_30
      WHERE data_date = v_last_date
    )
    SELECT
      v_today,
      v_now,
      v_table,
      'outliers',
      'zscore_latest_30',
      variable,
      data_date,
      zscore_30,
      3.0,
      CASE
        WHEN zscore_30 IS NULL THEN 'na'
        WHEN zscore_30 >= 3 THEN 'error'
        WHEN zscore_30 >= 2 THEN 'warn'
        ELSE 'ok'
      END,
      FORMAT('valor=%f | avg_30=%f | std_30=%f', valor, avg_30, std_30)
    FROM latest_stats;

    -- Flatline últimos 5 días
    INSERT INTO `proyectos-cmoran-489000.data_metricas_pipeline.hechos_calidad_datos_commodities`
    WITH ranked AS (
      SELECT
        variable,
        data_date,
        valor,
        ROW_NUMBER() OVER (PARTITION BY variable ORDER BY data_date DESC) AS rn
      FROM long_daily
      WHERE valor IS NOT NULL
    ),
    flat_stats AS (
      SELECT
        variable,
        COUNT(*) AS obs_5d,
        COUNT(DISTINCT valor) AS distinct_vals_5d
      FROM ranked
      WHERE rn <= 5
      GROUP BY variable
    )
    SELECT
      v_today,
      v_now,
      v_table,
      'flatline',
      'distinct_values_last_5d',
      variable,
      v_last_date,
      CAST(distinct_vals_5d AS FLOAT64),
      1.0,
      CASE
        WHEN obs_5d < 5 THEN 'na'
        WHEN distinct_vals_5d = 1 THEN 'warn'
        ELSE 'ok'
      END,
      FORMAT('obs_5d=%d | distinct_vals_5d=%d', obs_5d, distinct_vals_5d)
    FROM flat_stats;

  END IF;
END