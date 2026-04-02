from __future__ import annotations

from datetime import timedelta
import json
import urllib.request
from urllib.error import HTTPError, URLError

import pendulum
import google.auth.transport.requests
import google.oauth2.id_token

from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.providers.google.cloud.operators.bigquery import BigQueryInsertJobOperator


PROJECT_ID = "proyectos-cmoran-489000"
BQ_LOCATION = "US"

ETL_URL = "https://etl-market-data-kqhzp5nm5q-uc.a.run.app"
SARIMAX_URL = "https://sarimax-model-kqhzp5nm5q-uc.a.run.app"
AUTOGLUON_URL = "https://autogluon-chronos-ii-kqhzp5nm5q-uc.a.run.app"


def invoke_private_cloud_run(url: str, service_name: str) -> None:
    auth_req = google.auth.transport.requests.Request()
    token = google.oauth2.id_token.fetch_id_token(auth_req, url)

    payload = json.dumps({}).encode("utf-8")

    req = urllib.request.Request(url=url, data=payload, method="POST")
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/json")

    try:
        with urllib.request.urlopen(req, timeout=3600) as resp:
            body = resp.read().decode("utf-8", errors="ignore")
            print(f"[{service_name}] status={resp.status}")
            print(body)

            if resp.status >= 300:
                raise RuntimeError(f"{service_name} respondió {resp.status}: {body}")

    except HTTPError as e:
        body = e.read().decode("utf-8", errors="ignore")
        raise RuntimeError(f"{service_name} HTTP {e.code}: {body}") from e
    except URLError as e:
        raise RuntimeError(f"{service_name} error de red: {e}") from e


default_args = {
    "owner": "carlos",
    "retries": 2,
    "retry_delay": timedelta(minutes=30),
}

with DAG(
    dag_id="commodities_daily_pipeline",
    description="ETL + historico + SARIMAX + AutoGluon + modelo mixto",
    start_date=pendulum.datetime(2026, 4, 1, tz="America/Santiago"),
    schedule="0 21 * * *",
    catchup=False,
    max_active_runs=1,
    dagrun_timeout=timedelta(hours=5),
    default_args=default_args,
    tags=["commodities", "mlops", "gcp"],
) as dag:

    run_etl = PythonOperator(
        task_id="run_etl",
        python_callable=invoke_private_cloud_run,
        op_kwargs={
            "url": ETL_URL,
            "service_name": "etl-market-data",
        },
    )

    sp_inserta_datos_historico = BigQueryInsertJobOperator(
        task_id="sp_inserta_datos_historico",
        configuration={
            "query": {
                "query": f"CALL `{PROJECT_ID}.data_procesada_commodities.SP_INSERTA_DATOS_HISTORICO`();",
                "useLegacySql": False,
            }
        },
        location=BQ_LOCATION,
    )

    run_sarimax = PythonOperator(
        task_id="run_sarimax",
        python_callable=invoke_private_cloud_run,
        op_kwargs={
            "url": SARIMAX_URL,
            "service_name": "sarimax-model",
        },
    )

    run_autogluon = PythonOperator(
        task_id="run_autogluon",
        python_callable=invoke_private_cloud_run,
        op_kwargs={
            "url": AUTOGLUON_URL,
            "service_name": "autogluon-chronos-ii",
        },
    )

    sp_modelo_mixto = BigQueryInsertJobOperator(
        task_id="sp_modelo_mixto",
        configuration={
            "query": {
                "query": f"CALL `{PROJECT_ID}.data_procesada_commodities.SP_GENERA_MODELO_MIXTO_E_HISTORICO`();",
                "useLegacySql": False,
            }
        },
        location=BQ_LOCATION,
    ) 
    sp_registros_pipeline = BigQueryInsertJobOperator(
    task_id="sp_registros_pipeline",
    configuration={
        "query": {
            "query": f"CALL `{PROJECT_ID}.data_metricas_pipeline.SP_GENERA_REGISTROS_PIPELINE`();",
            "useLegacySql": False,
        }
    },
    location=BQ_LOCATION,
)

    sp_calidad_datos_commodities = BigQueryInsertJobOperator(
    task_id="sp_calidad_datos_commodities",
    configuration={
        "query": {
            "query": f"CALL `{PROJECT_ID}.data_metricas_pipeline.SP_GENERA_CALIDAD_DATOS_COMMODITIES`();",
            "useLegacySql": False,
        }
    },
    location=BQ_LOCATION,
)

    sp_metricas_modelos_diarias = BigQueryInsertJobOperator(
    task_id="sp_metricas_modelos_diarias",
    configuration={
        "query": {
            "query": f"CALL `{PROJECT_ID}.data_metricas_pipeline.SP_GENERA_METRICAS_MODELOS_DIARIAS`();",
            "useLegacySql": False,
        }
    },
    location=BQ_LOCATION,
)

    run_etl >> sp_inserta_datos_historico >> [run_sarimax, run_autogluon] >> sp_modelo_mixto >> sp_registros_pipeline >> sp_calidad_datos_commodities >> sp_metricas_modelos_diarias
    