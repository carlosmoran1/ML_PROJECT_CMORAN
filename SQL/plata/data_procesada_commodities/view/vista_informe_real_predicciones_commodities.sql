create or replace view `proyectos-cmoran-489000.data_procesada_commodities.vista_informe_real_predicciones_commodities` as
WITH ultima_fecha_real AS (
  SELECT MAX(Date) AS max_date
  FROM `proyectos-cmoran-489000.data_procesada_commodities.hechos_data_proc_commodities`
),

real_filtrado AS (
  SELECT
    Date AS date,
    oro,
    plata,
    cobre,
    petroleo_brent,
    gas_natural
  FROM `proyectos-cmoran-489000.data_procesada_commodities.hechos_data_proc_commodities`
  WHERE Date >= DATE_SUB((SELECT max_date FROM ultima_fecha_real), INTERVAL 10 YEAR)
),

real_unpivot AS (
  SELECT
    date,
    commodity,
    CAST(valor AS FLOAT64) AS valor,
    'real' AS tipo_dato,
    1 AS orden_tipo_dato
  FROM real_filtrado
  UNPIVOT (
    valor FOR commodity IN (
      oro,
      plata,
      cobre,
      petroleo_brent,
      gas_natural
    )
  )
),

ultima_corrida_por_modelo AS (
  SELECT
    modelo,
    MAX(data_date_part) AS max_data_date_part
  FROM `proyectos-cmoran-489000.data_procesada_commodities.predicciones_commodities_historico`
  WHERE modelo IN ('sarimax', 'autogluon', 'ensamblado', 'model_mixto')
  GROUP BY modelo
),

preds_filtradas AS (
  SELECT
    p.fecha_prediccion AS date,
    p.oro,
    p.plata,
    p.cobre,
    p.petroleo_brent,
    p.gas_natural,
    p.modelo,
    p.data_date_part
  FROM `proyectos-cmoran-489000.data_procesada_commodities.predicciones_commodities_historico` p
  INNER JOIN ultima_corrida_por_modelo u
    ON p.modelo = u.modelo
   AND p.data_date_part = u.max_data_date_part
),

preds_unpivot AS (
  SELECT
    date,
    commodity,
    CAST(valor AS FLOAT64) AS valor,
    modelo AS tipo_dato,
    CASE modelo
      WHEN 'sarimax' THEN 2
      WHEN 'autogluon' THEN 3
      WHEN 'ensamblado' THEN 4
      WHEN 'model_mixto' THEN 5
      ELSE 99
    END AS orden_tipo_dato
  FROM preds_filtradas
  UNPIVOT (
    valor FOR commodity IN (
      oro,
      plata,
      cobre,
      petroleo_brent,
      gas_natural
    )
  )
)
SELECT * FROM real_unpivot
UNION ALL
SELECT * FROM preds_unpivot