# ML_PROJECT_CMORAN

<p align="center">
  <b>Pipeline MLOps productivo para pronóstico diario de commodities en Google Cloud Platform</b><br>
  Extracción automatizada, procesamiento en BigQuery, modelos desplegados en Cloud Run, orquestación con Composer/Airflow, monitoreo operacional y reporting en Power BI.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Python-3.x-blue?logo=python" alt="Python">
  <img src="https://img.shields.io/badge/GCP-Cloud%20Platform-4285F4?logo=googlecloud" alt="GCP">
  <img src="https://img.shields.io/badge/BigQuery-Data%20Warehouse-669DF6?logo=googlebigquery" alt="BigQuery">
  <img src="https://img.shields.io/badge/Cloud%20Run-Serverless-4285F4?logo=googlecloud" alt="Cloud Run">
  <img src="https://img.shields.io/badge/Composer-Airflow-017CEE?logo=apacheairflow" alt="Composer">
  <img src="https://img.shields.io/badge/Terraform-IaC-7B42BC?logo=terraform" alt="Terraform">
  <img src="https://img.shields.io/badge/Cloud%20Build-CI%2FCD-4285F4?logo=googlecloud" alt="Cloud Build">
  <img src="https://img.shields.io/badge/Power%20BI-Reporting-F2C811?logo=powerbi" alt="Power BI">
</p>

---

## Tabla de contenidos

- [Resumen del proyecto](#resumen-del-proyecto)
- [Objetivo](#objetivo)
- [Arquitectura general](#arquitectura-general)
- [Flujo del pipeline](#flujo-del-pipeline)
- [Modelos utilizados](#modelos-utilizados)
- [Monitoreo y observabilidad](#monitoreo-y-observabilidad)
- [Power BI y capa informativa](#power-bi-y-capa-informativa)
- [Estructura del repositorio](#estructura-del-repositorio)
- [Estructura SQL](#estructura-sql)
- [Dimensiones auxiliares](#dimensiones-auxiliares)
- [Stack tecnológico](#stack-tecnológico)
- [Estado del proyecto](#estado-del-proyecto)

---

## Resumen del proyecto

Este repositorio contiene una arquitectura MLOps orientada a producción para generar predicciones diarias de commodities a partir de precios de mercado y variables macroeconómicas externas. El pipeline integra extracción, almacenamiento intermedio, procesamiento analítico, inferencia, consolidación de resultados, monitoreo técnico y visualización de negocio.

La solución fue diseñada para que el flujo no termine en la predicción, sino que también incorpore control operacional y consumo analítico. Por eso el proyecto incluye:

- carga histórica y productiva;
- métricas de desempeño por modelo;
- control de calidad del dato;
- registro de ejecuciones del pipeline;
- vistas analíticas para reporting;
- y dimensiones auxiliares para enriquecer el modelo informativo.

---

## Objetivo

Construir un flujo productivo reutilizable en GCP que permita:

1. extraer datos desde fuentes externas;
2. consolidarlos en una capa raw;
3. procesarlos en BigQuery;
4. ejecutar modelos predictivos en producción;
5. almacenar predicciones diarias e histórico;
6. monitorear calidad, desempeño y trazabilidad;
7. y disponibilizar toda la información en Power BI.

---

## Arquitectura general

```text
Fuentes externas
(Yahoo Finance / FRED / EIA / World Bank)
                     │
                     ▼
        ┌──────────────────────────────┐
        │ ETL - Cloud Run              │
        │ src/pipelines/etl_market_data│
        └──────────────────────────────┘
                     │
                     ▼
        ┌──────────────────────────────┐
        │ Google Cloud Storage         │
        │ parquet raw consolidado      │
        └──────────────────────────────┘
                     │
                     ▼
        ┌──────────────────────────────┐
        │ BigQuery - capa bronce       │
        │ data_raw_indicadores         │
        └──────────────────────────────┘
                     │
                     ▼
        ┌──────────────────────────────┐
        │ BigQuery - capa plata        │
        │ data_procesada_commodities   │
        └──────────────────────────────┘
              │                    │
              ▼                    ▼
    ┌────────────────┐   ┌────────────────────────┐
    │ SARIMAX        │   │ AutoGluon Chronos II   │
    │ Cloud Run      │   │ Cloud Run              │
    └────────────────┘   └────────────────────────┘
              │                    │
              └──────────┬─────────┘
                         ▼
        ┌──────────────────────────────┐
        │ BigQuery - consolidación  -  │
        │           capa plata         │
        │ modelo mixto e histórico     │
        └──────────────────────────────┘
                         │
                         ▼
        ┌──────────────────────────────┐
        │ BigQuery - capa oro          │
        │ calidad / métricas /         │
        │ registros pipeline           │
        └──────────────────────────────┘
                         │
                         ├──────────────► Dimensiones auxiliares
                         │                para modelo informativo
                         ▼
        ┌──────────────────────────────┐
        │ Power BI                     │
        │ monitoreo y análisis         │
        └──────────────────────────────┘
```

---

## Flujo del pipeline

### 1. ETL de datos externos
La ETL obtiene información desde fuentes como Yahoo Finance, FRED, EIA y World Bank. Luego consolida la extracción en archivos parquet almacenados en Google Cloud Storage.

### 2. Capa bronce en BigQuery
Los datos raw son expuestos analíticamente para ser utilizados como base del procesamiento posterior.

### 3. Capa plata en BigQuery
La información es normalizada, transformada e insertada en tablas procesadas de negocio mediante procedimientos almacenados.

### 4. Predicción diaria
Los servicios de inferencia ejecutan el modelo SARIMAX y el modelo AutoGluon Chronos II, generando predicciones productivas por commodity.

### 5. Consolidación de resultados
Los resultados son integrados en BigQuery para mantener predicción diaria, histórico y lógica de combinación entre modelos.

### 6. Monitoreo y control operacional
Se generan tablas específicas para calidad del dato, métricas de desempeño y registros del pipeline.

### 7. Consumo analítico
Power BI consume tablas y vistas para exponer resultados operativos, métricas técnicas y análisis histórico de commodities.

---

## Modelos utilizados

### SARIMAX
Modelo de series de tiempo orientado a capturar estructura temporal, tendencia, estacionalidad y efecto de variables exógenas configurables por commodity.

### AutoGluon Chronos II
Modelo fundacional para series de tiempo, útil para capturar patrones complejos y complementar el enfoque estadístico tradicional.

### Modelo mixto
El proyecto también contempla una lógica de consolidación para combinar fortalezas de distintos enfoques dentro del flujo productivo. 

### Modelo Ensamblado
Modelo basado en el promedio simple de las predicciones de Choronos II y SARIMAX .

---

## Monitoreo y observabilidad

La arquitectura no solo predice, también deja trazabilidad completa del proceso. La capa de monitoreo permite seguir qué pasó en cada ejecución y evaluar si el pipeline se comportó correctamente.

### Principales componentes monitoreados
- calidad del dato cargado;
- registros de ejecución del pipeline;
- inserciones diarias;
- datos procesados por fecha;
- métricas de desempeño por modelo;
- y disponibilidad de resultados para consumo analítico.

### Stored procedures principales de monitoreo
- `SP_GENERA_CALIDAD_DATOS_COMMODITIES`
- `SP_GENERA_METRICAS_MODELOS_DIARIAS`
- `SP_GENERA_REGISTROS_PIPELINE`

---

## Power BI y capa informativa

El proyecto incorpora un modelo informativo en Power BI orientado tanto a seguimiento técnico como a análisis de negocio.

### El dashboard contempla

#### 1. Calidad del dato
Seguimiento de validaciones, consistencia de carga, registros faltantes, nulos y estado general de la información usada por el pipeline.

#### 2. Registro de procesos
Monitoreo operacional del flujo, incluyendo inserciones ejecutadas, timestamps, datos del día, trazabilidad de pasos y control del pipeline diario.

#### 3. Modelo productivo diario
Visualización de las predicciones generadas en producción para cada commodity y su disponibilidad operativa.

#### 4. Métricas de desempeño
Seguimiento histórico del rendimiento de los modelos a través de indicadores de error y capacidad predictiva.

#### 5. Análisis descriptivo histórico de commodities
Vista analítica del comportamiento histórico de los commodities para exploración, contexto y seguimiento de tendencias.

---

## Estructura del repositorio

```text
ML_PROJECT_CMORAN/
├── ci/                                         # YAML de Cloud Build por servicio
├── config/
│   └── model_features/                        # Configuración de variables exógenas por commodity
├── dags/                                      # DAGs de Cloud Composer / Airflow
├── infra/
│   └── terraform/
│       └── cloudbuild/                        # Infraestructura CI/CD como código
├── notebooks/                                 # Exploración, validación y experimentación
├── reports/                                   # Reporting y modelo Power BI
│   ├── MODELO_ENTIDAD_RELACION_PBI.png
│   └── MODELO_INFORMATIVO_COMMODITIES.pbix
├── SQL/
│   ├── bronce/                                # Objetos BigQuery de capa raw
│   ├── plata/                                 # Objetos BigQuery de capa procesada y predicción
│   ├── oro/                                   # Objetos BigQuery de métricas, calidad y monitoreo
│   └── dimensiones/                           # Dimensiones auxiliares para el modelo informativo
├── src/
│   ├── autogluon_chronos_ii/                  # Servicio productivo AutoGluon
│   ├── common/                                # Utilidades compartidas del proyecto
│   ├── pipelines/
│   │   └── etl_market_data/                   # Servicio ETL
│   └── sarimax/                               # Servicio productivo SARIMAX
├── .dockerignore
├── .gitattributes
├── .gitignore
└── README.md
```

---

## Estructura SQL

La carpeta `SQL/` organiza los objetos analíticos del proyecto por dominios funcionales y capas de consumo.

### `SQL/bronce`
Contiene objetos asociados a la capa raw o de ingesta inicial.

### `SQL/plata`
Contiene objetos de datos procesados, predicción operativa, histórico y vistas analíticas intermedias.

### `SQL/oro`
Contiene objetos de observabilidad y control, incluyendo calidad del dato, registros de procesos y métricas de desempeño.

### `SQL/dimensiones`
Contiene dimensiones auxiliares que enriquecen el modelo informativo y el consumo analítico en Power BI. Esta carpeta está al mismo nivel que `bronce`, `plata` y `oro`, porque su foco no es una capa transaccional del pipeline, sino el soporte semántico y descriptivo del modelo analítico.

---

## Dimensiones auxiliares

Actualmente la carpeta de dimensiones considera tablas y archivos de entrada para enriquecer el modelo informativo.

### Estructura observada

```text
SQL/
└── dimensiones/
    └── tables/
        ├── data_input/
        │   ├── input_apertura_bolsa.csv
        │   └── input_descripción_e_importancia_variables.csv
        ├── dim_descripcion_variables_model.sql
        └── dim_open_bolsa.sql
```

### Propósito de las dimensiones

#### `dim_open_bolsa.sql`
Dimensiona la apertura de bolsa para apoyar análisis temporal, contexto de mercado y cruces explicativos dentro del modelo informativo.

#### `dim_descripcion_variables_model.sql`
Aporta descripción semántica de variables del modelo, útil para interpretación, documentación y consumo en reporting.

#### `input_apertura_bolsa.csv`
Archivo fuente para alimentar la dimensión asociada a apertura de mercado.

#### `input_descripción_e_importancia_variables.csv`
Archivo fuente para alimentar la dimensión de descripción e importancia de variables utilizadas en el modelo.

Estas dimensiones permiten que el dashboard no se limite a mostrar resultados numéricos, sino que también entregue contexto sobre variables, aperturas de mercado y componentes del modelo.

---

## Stack tecnológico

### Lenguaje principal
- Python
- SQL
- DAX

### Servicios cloud
- Google Cloud Storage
- BigQuery
- Cloud Run
- Cloud Composer
- Secret Manager
- Cloud Build

### Orquestación e infraestructura
- Apache Airflow
- Terraform
- Docker
- GitHub

### Analítica y visualización
- Power BI

---

## Estado del proyecto

Proyecto orientado a operación productiva diaria, con foco en:

- automatización;
- mantenibilidad;
- trazabilidad;
- monitoreo técnico;
- y consumo analítico de resultados.

Además de la capa predictiva, el repositorio ya incorpora una capa SQL más completa para explotación analítica, reporting y documentación del modelo, incluyendo métricas, procesos, calidad del dato y dimensiones auxiliares.

---

## Autor

**Carlos Morán**

Repositorio: [ML_PROJECT_CMORAN](https://github.com/carlosmoran1/ML_PROJECT_CMORAN)
LinkedIn: [Carlos Morán](https://www.linkedin.com/in/carlos-mor%C3%A1n-data-science-engineer-ia/)
