CREATE TABLE `proyectos-cmoran-489000.data_metricas_pipeline.registros_pipeline`
(
  fecha_ejecucion DATE NOT NULL,
  ts_evento TIMESTAMP NOT NULL,
  etapa STRING NOT NULL,
  estado STRING NOT NULL,
  tabla_objetivo STRING,
  registros INT64,
  data_min DATE,
  data_max DATE,
  umbral_esperado INT64,
  detalle STRING
)
PARTITION BY fecha_ejecucion
CLUSTER BY etapa, estado;