CREATE TABLE `proyectos-cmoran-489000.data_metricas_pipeline.metricas_modelos_diarias`
(
  data_date_part DATE NOT NULL,
  fecha_prediccion DATE NOT NULL,
  modelo STRING NOT NULL,
  commodity STRING NOT NULL,
  actual_previo FLOAT64,
  actual_real FLOAT64,
  predicted_value FLOAT64,
  abs_error FLOAT64,
  ape FLOAT64,
  direccion_predicha INT64,
  direccion_real INT64,
  direccion_ok INT64
)
PARTITION BY data_date_part
CLUSTER BY modelo, commodity, fecha_prediccion;