CREATE TABLE `proyectos-cmoran-489000.data_metricas_pipeline.hechos_calidad_datos_commodities`
(
  fecha_revision DATE NOT NULL,
  ts_revision TIMESTAMP NOT NULL,
  tabla_monitoreada STRING NOT NULL,
  metric_group STRING NOT NULL,
  metric_name STRING NOT NULL,
  variable STRING,
  data_date DATE,
  valor FLOAT64,
  umbral FLOAT64,
  estado STRING NOT NULL,
  detalle STRING
)
PARTITION BY fecha_revision
CLUSTER BY tabla_monitoreada, metric_group, variable;