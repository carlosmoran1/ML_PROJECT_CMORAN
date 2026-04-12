CREATE EXTERNAL TABLE `proyectos-cmoran-489000.data_raw_indicadores.hechos_data_raw_commodities`
OPTIONS(
  format="PARQUET",
  uris=["gs://proyecto_commodities/data/raw/data_historica_full.parquet"]
);