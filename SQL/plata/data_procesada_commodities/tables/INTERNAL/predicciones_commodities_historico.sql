CREATE TABLE `proyectos-cmoran-489000.data_procesada_commodities.predicciones_commodities_historico`
(
  fecha_prediccion DATE,
  oro FLOAT64,
  plata FLOAT64,
  cobre FLOAT64,
  petroleo_brent FLOAT64,
  gas_natural FLOAT64,
  modelo STRING,
  data_date_part DATE
)
PARTITION BY data_date_part;