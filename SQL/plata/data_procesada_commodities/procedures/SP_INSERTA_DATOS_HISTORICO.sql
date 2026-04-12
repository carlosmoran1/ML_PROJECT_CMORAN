CREATE OR REPLACE PROCEDURE `proyectos-cmoran-489000.data_procesada_commodities.SP_INSERTA_DATOS_HISTORICO`()
BEGIN
  DECLARE min_date DATE;
  DECLARE max_date DATE;

  DECLARE insert_cols_sql STRING;
  DECLARE proc_select_sql STRING;
  DECLARE raw_select_sql STRING;
  DECLARE ffill_sql STRING;
  DECLARE final_select_sql STRING;
  DECLARE stmt STRING;

  -- 1) Recrear tabla externa
  CREATE OR REPLACE EXTERNAL TABLE `data_raw_indicadores.hechos_data_raw_commodities`
  OPTIONS (
    format = 'PARQUET',
    uris = ['gs://proyecto_commodities/data/raw/data_historica_full.parquet']
  );

  -- 2) Schema esperado del SP actual
  CREATE TEMP TABLE column_specs (
    ord INT64,
    dest_col STRING,
    raw_col STRING,
    alt_raw_col STRING,
    data_type STRING
  );

  INSERT INTO column_specs (ord, dest_col, raw_col, alt_raw_col, data_type)
  VALUES
    (1 , 'petroleo_brent', 'petroleo_brent', NULL, 'FLOAT64'),
    (2 , 'oro', 'oro', NULL, 'FLOAT64'),
    (3 , 'gas_natural', 'gas_natural', NULL, 'FLOAT64'),
    (4 , 'cobre', 'cobre', NULL, 'FLOAT64'),
    (5 , 'plata', 'plata', NULL, 'FLOAT64'),
    (6 , 'vix', 'vix', NULL, 'FLOAT64'),
    (7 , 'sp500', 'sp500', NULL, 'FLOAT64'),
    (8 , 'shanghai', 'shanghai', NULL, 'FLOAT64'),
    (9 , 'emergentes', 'emergentes', NULL, 'FLOAT64'),
    (10, 'Nikkei', 'Nikkei', NULL, 'FLOAT64'),
    (11, 'DAX', 'DAX', NULL, 'FLOAT64'),
    (12, 'FTSE', 'FTSE', NULL, 'FLOAT64'),

    (13, 'AAPL', 'AAPL', NULL, 'FLOAT64'),
    (14, 'NVDA', 'NVDA', NULL, 'FLOAT64'),
    (15, 'MSFT', 'MSFT', NULL, 'FLOAT64'),
    (16, 'AMZN', 'AMZN', NULL, 'FLOAT64'),
    (17, 'GOOGL', 'GOOGL', NULL, 'FLOAT64'),
    (18, 'BRK_B', 'BRK_B', 'BRK-B', 'FLOAT64'),
    (19, 'JPM', 'JPM', NULL, 'FLOAT64'),
    (20, 'UNH', 'UNH', NULL, 'FLOAT64'),
    (21, 'TSM', 'TSM', NULL, 'FLOAT64'),
    (22, 'AMD', 'AMD', NULL, 'FLOAT64'),

    (23, 'SPY', 'SPY', NULL, 'FLOAT64'),
    (24, 'QQQ', 'QQQ', NULL, 'FLOAT64'),
    (25, 'DIA', 'DIA', NULL, 'FLOAT64'),
    (26, 'NEM', 'NEM', NULL, 'FLOAT64'),
    (27, 'KGC', 'KGC', NULL, 'FLOAT64'),
    (28, 'AEM', 'AEM', NULL, 'FLOAT64'),
    (29, 'PAAS', 'PAAS', NULL, 'FLOAT64'),
    (30, 'WPM', 'WPM', NULL, 'FLOAT64'),
    (31, 'AG', 'AG', NULL, 'FLOAT64'),
    (32, 'FCX', 'FCX', NULL, 'FLOAT64'),
    (33, 'SCCO', 'SCCO', NULL, 'FLOAT64'),
    (34, 'BHP', 'BHP', NULL, 'FLOAT64'),
    (35, 'EQT', 'EQT', NULL, 'FLOAT64'),
    (36, 'CTRA', 'CTRA', NULL, 'FLOAT64'),
    (37, 'LNG', 'LNG', NULL, 'FLOAT64'),
    (38, 'XOM', 'XOM', NULL, 'FLOAT64'),
    (39, 'CVX', 'CVX', NULL, 'FLOAT64'),
    (40, 'SHEL', 'SHEL', NULL, 'FLOAT64'),

    (41, 'dolar_index', 'dolar_index', NULL, 'FLOAT64'),
    (42, 'tasa_10y', 'tasa_10y', NULL, 'FLOAT64'),
    (43, 'tasa_2y', 'tasa_2y', NULL, 'FLOAT64'),
    (44, 'tasa_5y', 'tasa_5y', NULL, 'FLOAT64'),

    (45, 'PIB_USA', 'PIB_USA', NULL, 'FLOAT64'),
    (46, 'PIB_JPN', 'PIB_JPN', NULL, 'FLOAT64'),
    (47, 'PIB_DEU', 'PIB_DEU', NULL, 'FLOAT64'),
    (48, 'PIB_GBR', 'PIB_GBR', NULL, 'FLOAT64'),
    (49, 'PIB_FRA', 'PIB_FRA', NULL, 'FLOAT64'),
    (50, 'PIB_ITA', 'PIB_ITA', NULL, 'FLOAT64'),
    (51, 'PIB_CAN', 'PIB_CAN', NULL, 'FLOAT64'),

    (52, 'DESEMPLEO_USA', 'DESEMPLEO_USA', NULL, 'FLOAT64'),
    (53, 'DESEMPLEO_ALE', 'DESEMPLEO_ALE', NULL, 'FLOAT64'),
    (54, 'DESEMPLEO_FRA', 'DESEMPLEO_FRA', NULL, 'FLOAT64'),
    (55, 'DESEMPLEO_INGL', 'DESEMPLEO_INGL', NULL, 'FLOAT64'),
    (56, 'DESEMPLEO_JPN', 'DESEMPLEO_JPN', NULL, 'FLOAT64'),
    (57, 'DESEMPLEO_CAN', 'DESEMPLEO_CAN', NULL, 'FLOAT64'),
    (58, 'DESEMPLEO_ITA', 'DESEMPLEO_ITA', NULL, 'FLOAT64'),
    (59, 'DESEMPLEO_MEX', 'DESEMPLEO_MEX', NULL, 'FLOAT64'),

    (60, 'produccion_petroleo_usa', 'produccion_petroleo_usa', NULL, 'FLOAT64'),
    (61, 'produccion_gas_usa', 'produccion_gas_usa', NULL, 'FLOAT64'),

    (62, 'DINERO_CIRCULANTE_EEUU_M2_APROX_LCU', 'DINERO_CIRCULANTE_EEUU_M2_APROX_LCU', NULL, 'FLOAT64'),
    (63, 'DINERO_CIRCULANTE_CHINA_M2_APROX_LCU', 'DINERO_CIRCULANTE_CHINA_M2_APROX_LCU', NULL, 'FLOAT64'),
    (64, 'DINERO_CIRCULANTE_JAPON_M2_APROX_LCU', 'DINERO_CIRCULANTE_JAPON_M2_APROX_LCU', NULL, 'FLOAT64'),
    (65, 'DINERO_CIRCULANTE_REINO_UNIDO_M2_APROX_LCU', 'DINERO_CIRCULANTE_REINO_UNIDO_M2_APROX_LCU', NULL, 'FLOAT64'),
    (66, 'DINERO_CIRCULANTE_CANADA_M2_APROX_LCU', 'DINERO_CIRCULANTE_CANADA_M2_APROX_LCU', NULL, 'FLOAT64'),
    (67, 'DINERO_CIRCULANTE_INDIA_M2_APROX_LCU', 'DINERO_CIRCULANTE_INDIA_M2_APROX_LCU', NULL, 'FLOAT64'),
    (68, 'DINERO_CIRCULANTE_BRASIL_M2_APROX_LCU', 'DINERO_CIRCULANTE_BRASIL_M2_APROX_LCU', NULL, 'FLOAT64'),
    (69, 'DINERO_CIRCULANTE_MEXICO_M2_APROX_LCU', 'DINERO_CIRCULANTE_MEXICO_M2_APROX_LCU', NULL, 'FLOAT64'),

    (70, 'Date', 'Date', NULL, 'DATE');

  -- 3) Rango de fechas nuevo
  SET min_date = (
    SELECT MIN(CAST(`Date` AS DATE))
    FROM `data_raw_indicadores.hechos_data_raw_commodities`
    WHERE petroleo_brent IS NOT NULL
  );

  SET max_date = (
    SELECT MAX(CAST(`Date` AS DATE))
    FROM `data_raw_indicadores.hechos_data_raw_commodities`
    WHERE petroleo_brent IS NOT NULL
  );

  IF min_date IS NULL OR max_date IS NULL THEN
    SELECT 'No se encontraron fechas válidas en el raw.' AS mensaje;
  ELSE

    -- 4) Borrar tramo a recargar
    DELETE FROM `data_procesada_commodities.hechos_data_proc_commodities`
    WHERE CAST(`Date` AS DATE) BETWEEN min_date AND max_date;

    -- 5) Columnas insert
    SET insert_cols_sql = (
      SELECT STRING_AGG(FORMAT('`%s`', dest_col), ', ' ORDER BY ord)
      FROM column_specs
    );

    -- 6) Select desde la tabla procesada histórica
    SET proc_select_sql = (
      SELECT STRING_AGG(
        CASE
          WHEN data_type = 'DATE' THEN FORMAT('CAST(`%s` AS DATE) AS `%s`', dest_col, dest_col)
          ELSE FORMAT('CAST(`%s` AS FLOAT64) AS `%s`', dest_col, dest_col)
        END,
        ',\n      ' ORDER BY ord
      )
      FROM column_specs
    );

    -- 7) Select dinámico desde el parquet raw
    --    Si la columna no existe en la tabla externa, la reemplaza por NULL.
    SET raw_select_sql = (
      WITH raw_cols AS (
        SELECT LOWER(column_name) AS column_name
        FROM `proyectos-cmoran-489000.data_raw_indicadores.INFORMATION_SCHEMA.COLUMNS`
        WHERE table_name = 'hechos_data_raw_commodities'
      )
      SELECT STRING_AGG(
        CASE
          WHEN data_type = 'DATE' THEN
            CASE
              WHEN EXISTS (SELECT 1 FROM raw_cols WHERE column_name = LOWER(raw_col))
                THEN FORMAT('CAST(`%s` AS DATE) AS `%s`', raw_col, dest_col)
              WHEN alt_raw_col IS NOT NULL
                   AND EXISTS (SELECT 1 FROM raw_cols WHERE column_name = LOWER(alt_raw_col))
                THEN FORMAT('CAST(`%s` AS DATE) AS `%s`', alt_raw_col, dest_col)
              ELSE FORMAT('CAST(NULL AS DATE) AS `%s`', dest_col)
            END
          ELSE
            CASE
              WHEN EXISTS (SELECT 1 FROM raw_cols WHERE column_name = LOWER(raw_col))
                THEN FORMAT('CAST(`%s` AS FLOAT64) AS `%s`', raw_col, dest_col)
              WHEN alt_raw_col IS NOT NULL
                   AND EXISTS (SELECT 1 FROM raw_cols WHERE column_name = LOWER(alt_raw_col))
                THEN FORMAT('CAST(`%s` AS FLOAT64) AS `%s`', alt_raw_col, dest_col)
              ELSE FORMAT('CAST(NULL AS FLOAT64) AS `%s`', dest_col)
            END
        END,
        ',\n      ' ORDER BY ord
      )
      FROM column_specs
    );

    -- 8) Lógica FFILL
    SET ffill_sql = (
      SELECT STRING_AGG(expr, ',\n      ' ORDER BY seq)
      FROM (
        SELECT 0 AS seq, '`Date`' AS expr
        UNION ALL
        SELECT
          ord AS seq,
          FORMAT(
            'LAST_VALUE(`%s` IGNORE NULLS) OVER (ORDER BY `Date` ASC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS `%s`',
            dest_col,
            dest_col
          ) AS expr
        FROM column_specs
        WHERE dest_col <> 'Date'
      )
    );

    -- 9) Select final
    SET final_select_sql = (
      SELECT STRING_AGG(expr, ',\n    ' ORDER BY ord)
      FROM (
        SELECT
          ord,
          CASE
            WHEN dest_col = 'Date' THEN '`Date`'
            ELSE FORMAT('CAST(`%s` AS FLOAT64) AS `%s`', dest_col, dest_col)
          END AS expr
        FROM column_specs
      )
    );

    -- 10) Armar e insertar
    SET stmt = '''
      INSERT INTO `data_procesada_commodities.hechos_data_proc_commodities` (
        ''' || insert_cols_sql || '''
      )
      WITH UnionData AS (
        -- Última fila histórica antes del tramo a recargar
        SELECT
          ''' || proc_select_sql || '''
        FROM `data_procesada_commodities.hechos_data_proc_commodities`
        WHERE CAST(`Date` AS DATE) < @min_date
        QUALIFY ROW_NUMBER() OVER (ORDER BY `Date` DESC) = 1

        UNION ALL

        -- Tramo nuevo desde parquet, tolerante a columnas faltantes
        SELECT
          ''' || raw_select_sql || '''
        FROM `data_raw_indicadores.hechos_data_raw_commodities`
        WHERE CAST(`Date` AS DATE) BETWEEN @min_date AND @max_date
          AND EXTRACT(DAYOFWEEK FROM CAST(`Date` AS DATE)) NOT IN (1, 7)
      ),
      FfillLogic AS (
        SELECT
          ''' || ffill_sql || '''
        FROM UnionData
      )
      SELECT
        ''' || final_select_sql || '''
      FROM FfillLogic
      WHERE CAST(`Date` AS DATE) BETWEEN @min_date AND @max_date
    ''';

    EXECUTE IMMEDIATE stmt
    USING min_date AS min_date, max_date AS max_date;

    SELECT FORMAT(
      'Carga completada para el rango %s a %s',
      CAST(min_date AS STRING),
      CAST(max_date AS STRING)
    ) AS mensaje;

  END IF;
END;