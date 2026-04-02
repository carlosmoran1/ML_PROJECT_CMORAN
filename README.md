# ML_PROJECT_CMORAN

Pipeline MLOps para pronóstico diario de commodities en GCP, con extracción automatizada de datos de mercado y macroeconomía, procesamiento en BigQuery, modelos SARIMAX y AutoGluon Chronos II desplegados en Cloud Run, y orquestación con Composer/Airflow.

## Objetivo

Construir un flujo productivo para generar predicciones diarias de commodities a partir de datos externos, exógenas configurables y modelos de series de tiempo, dejando los resultados disponibles en BigQuery para análisis, monitoreo y consumo posterior.

## Arquitectura general

El pipeline sigue este flujo:

1. **ETL en Cloud Run**
   - Descarga datos desde Yahoo Finance, FRED, EIA y World Bank.
   - Genera un parquet consolidado en GCS.

2. **Carga y procesamiento en BigQuery**
   - Se recrea una tabla externa sobre el parquet raw.
   - Un stored procedure inserta y normaliza los datos en la tabla procesada.

3. **Predicción por modelos**
   - **SARIMAX**: usa configuraciones por commodity y variables exógenas.
   - **AutoGluon Chronos II**: usa la misma configuración de exógenas desde GCS.

4. **Modelo mixto**
   - Un stored procedure combina la dirección de SARIMAX con la magnitud de AutoGluon.
   - Inserta resultados diarios y mantiene histórico.

5. **Orquestación**
   - Composer/Airflow ejecuta el pipeline completo de forma programada.

## Componentes principales en GCP

- **Cloud Run**
  - `etl-market-data`
  - `sarimax-model`
  - `autogluon-chronos-ii`

- **Cloud Composer / Airflow**
  - DAG principal: `commodities_daily_pipeline`

- **Cloud Storage**
  - Bucket raw/features del proyecto
  - Parquet raw consolidado
  - CSV de variables exógenas por commodity

- **BigQuery**
  - Dataset raw (10 días)
  - Dataset procesado (Histórico)
  - Tablas de predicciones e histórico
  - Stored procedures de carga y ensamblado

- **Secret Manager**
  - Claves para FRED, EIA y Hugging Face

- **Cloud Build + GitHub**
  - CI/CD por servicio, con triggers separados para ETL, SARIMAX, AutoGluon y sincronización de features

## Estructura del repositorio

```text
ML_PROJECT_CMORAN/
├── .github/                           # Configuración de GitHub
├── ci/                                # Cloud Build YAML por servicio
├── config/
│   └── model_features/                # CSV de variables exógenas por commodity
├── dags/                              # DAG de Composer / Airflow
├── infra/
│   └── terraform/
│       └── cloudbuild/                # Triggers e IAM para CI/CD
├── notebooks/                         # Exploración y pruebas
├── src/
│   ├── autogluon_chronos_ii/          # Servicio AutoGluon
│   ├── common/                        # Helpers compartidos (GCS, BQ, Secret Manager)
│   ├── pipelines/
│   │   └── etl_market_data/           # Servicio ETL
│   └── sarimax/                       # Servicio SARIMAX
├── .dockerignore
├── .gitattributes
├── .gitignore
└── README.md
