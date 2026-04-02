# ML_PROJECT_CMORAN

> Pipeline MLOps para pronóstico diario de commodities en GCP — extracción automatizada de datos de mercado y macroeconomía, procesamiento en BigQuery, modelos SARIMAX y AutoGluon Chronos II desplegados en Cloud Run, orquestación con Composer/Airflow y monitoreo integrado.

---

## Objetivo

Construir un flujo productivo para generar predicciones diarias de commodities a partir de datos de mercado y variables macroeconómicas externas. El pipeline combina dos modelos de series de tiempo complementarios y valida automáticamente su performance comparando predicciones contra precios reales históricos, dejando todos los resultados disponibles en BigQuery para análisis y consumo posterior.

---

## Arquitectura general

```
Yahoo Finance / FRED / EIA / World Bank
              │
              ▼
     ┌─────────────────┐
     │  ETL – Cloud Run│   → GCS (parquet raw)
     └─────────────────┘
              │
              ▼
     ┌──────────────────────┐
     │  BigQuery            │
     │  data_raw_indicadores│   ← tabla externa sobre parquet
     └──────────────────────┘
              │
              ▼
     ┌───────────────────────────────┐
     │  BigQuery                     │
     │  data_procesada_commodities   │   ← SP_INSERTA_DATOS_HISTORICO
     └───────────────────────────────┘
         │                   │
         ▼                   ▼
  ┌────────────┐     ┌──────────────────────┐
  │  SARIMAX   │     │ AutoGluon Chronos II │   (Cloud Run)
  │  Cloud Run │     │ Cloud Run            │
  └────────────┘     └──────────────────────┘
         │                   │
         └────────┬──────────┘
                  ▼
     ┌─────────────────────────────────┐
     │  Modelo Mixto                   │
     │  SP_GENERA_MODELO_MIXTO_E_HIST  │   Modelo Mixto: dirección (SARIMAX) + magnitud (AutoGluon) y Modelo Ensamblado: Promedio Simple
     └─────────────────────────────────┘
                  │
                  ▼
     ┌──────────────────────────────────┐
     │  data_metricas_pipeline          │
     │  Calidad · Métricas · Registros  │   monitoreo automático
     └──────────────────────────────────┘
```

El DAG `commodities_daily_pipeline` orquesta el flujo completo vía **Cloud Composer / Airflow**, con ejecución programada a las **21:00 hora Chile**, **2 reintentos** y **30 minutos** de espera entre intentos.

---

## Etapas del pipeline

### 1. ETL en Cloud Run
- Descarga datos desde Yahoo Finance, FRED, EIA y World Bank.
- Genera un parquet consolidado en GCS.

### 2. Carga y procesamiento en BigQuery
- Se recrea una tabla externa sobre el parquet raw (`data_raw_indicadores`).
- `SP_INSERTA_DATOS_HISTORICO` normaliza e inserta los datos en `data_procesada_commodities`.

### 3. Predicción por modelos
- **SARIMAX**: captura tendencia y estacionalidad con variables exógenas configurables por commodity. Aporta la **dirección** de la predicción.
- **AutoGluon Chronos II**: modelo fundacional de series de tiempo (Hugging Face). Aporta la **magnitud** del cambio predicho.

### 4. Modelo mixto
- `SP_GENERA_MODELO_MIXTO_E_HISTORICO` combina dirección (SARIMAX) + magnitud (AutoGluon).
- Inserta resultados diarios en `predicciones_commodities` y mantiene histórico en `predicciones_commodities_historico`.

### 5. Monitoreo y calidad integrados
- `SP_GENERA_CALIDAD_DATOS_COMMODITIES`: detecta registros faltantes, nulos o fuera de rango en cada ingestión → `hechos_calidad_datos_commodities`.
- `SP_GENERA_METRICAS_MODELOS_DIARIAS`: calcula MAE, RMSE, MAPE y accuracy direccional comparando predicciones vs. precios reales históricos → `metricas_modelos_diarias`.
- `SP_GENERA_REGISTROS_PIPELINE`: registra estado y timestamps de cada ejecución para trazabilidad → `registros_pipeline`.

---

## Datasets en BigQuery

| Dataset | Tablas | Stored Procedures |
|---|---|---|
| `data_raw_indicadores` | `hechos_data_raw_commodities` | — |
| `data_procesada_commodities` | `hechos_data_proc_commodities` · `predicciones_commodities` · `predicciones_commodities_historico` | `SP_INSERTA_DATOS_HISTORICO` · `SP_GENERA_MODELO_MIXTO_E_HISTORICO` |
| `data_metricas_pipeline` | `hechos_calidad_datos_commodities` · `metricas_modelos_diarias` · `registros_pipeline` | `SP_GENERA_CALIDAD_DATOS_COMMODITIES` · `SP_GENERA_METRICAS_MODELOS_DIARIAS` · `SP_GENERA_REGISTROS_PIPELINE` |

---

## Componentes principales en GCP

| Servicio | Componentes |
|---|---|
| **Cloud Run** | `etl-market-data` · `sarimax-model` · `autogluon-chronos-ii` |
| **Cloud Composer / Airflow** | DAG: `commodities_daily_pipeline` |
| **Cloud Storage** | Bucket raw/features · Parquet raw consolidado · CSV de exógenas por commodity |
| **BigQuery** | 3 datasets · 6 tablas · 5 stored procedures |
| **Secret Manager** | Claves FRED · EIA · Hugging Face |
| **Cloud Build + GitHub** | CI/CD con triggers separados por servicio |
| **Terraform** | Infraestructura de CI/CD como código (triggers e IAM) |

---

## Fuentes de datos

| Fuente | Datos | Uso |
|---|---|---|
| Yahoo Finance | Precios OHLCV de commodities | Serie temporal objetivo |
| FRED | Indicadores macro (USD, tasas, inflación) | Variables exógenas |
| EIA | Inventarios y producción energética | Variables exógenas energía |
| World Bank | Datos económicos globales | Variables exógenas macro |

---

## Estructura del repositorio

```text
ML_PROJECT_CMORAN/
├── ci/                                # Cloud Build YAML por servicio
├── config/
│   └── model_features/                # CSV de variables exógenas por commodity
├── dags/                              # DAG de Composer / Airflow
├── infra/
│   └── terraform/
│       └── cloudbuild/                # Triggers e IAM para CI/CD
├── notebooks/                         # Exploración y pruebas
├── src/
│   ├── autogluon_chronos_ii/          # Servicio AutoGluon Chronos II
│   ├── common/                        # Helpers compartidos (GCS, BQ, Secret Manager)
│   ├── pipelines/
│   │   └── etl_market_data/           # Servicio ETL
│   └── sarimax/                       # Servicio SARIMAX
├── .dockerignore
├── .gitignore
└── README.md
```

---

## Variables exógenas configurables

Los archivos CSV en `config/model_features/` definen qué indicadores macroeconómicos usa cada commodity. Esto permite ajustar el comportamiento de ambos modelos sin modificar código, facilitando experimentos y mantenimiento operativo.

---

## CI/CD

- **Cloud Build** con triggers separados para ETL, SARIMAX, AutoGluon y sincronización de features. Cada servicio tiene su propio Dockerfile y YAML en `ci/`.
- **Terraform** en `infra/terraform/cloudbuild/` gestiona los triggers y permisos IAM, garantizando infraestructura reproducible.
- **Secret Manager** centraliza las credenciales de las APIs externas.
