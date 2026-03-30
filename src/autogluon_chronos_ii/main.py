import json
import os
import shutil
import traceback
import warnings

import functions_framework

from src.common.ml_gcp_utils import (
    download_feature_config,
    load_source_df,
    overwrite_model_only,
)
from src.autogluon_chronos_ii.train import build_predictions

warnings.filterwarnings("ignore")

PROJECT_ID = os.getenv("PROJECT_ID", "proyectos-cmoran-489000")
DATASET = os.getenv("DATASET", "data_procesada_commodities")
SOURCE_TABLE = os.getenv(
    "SOURCE_TABLE",
    f"{PROJECT_ID}.{DATASET}.hechos_data_proc_commodities",
)
TARGET_TABLE = os.getenv(
    "TARGET_TABLE",
    f"{PROJECT_ID}.{DATASET}.predicciones_commodities",
)

FEATURES_BUCKET = os.getenv("FEATURES_BUCKET", "proyecto_commodities")
FEATURES_BLOB = os.getenv("FEATURES_BLOB", "data/features/dim_features_commodities.csv")

HORIZON = int(os.getenv("HORIZON", "10"))
MODEL_LABEL = os.getenv("MODEL_LABEL", "autogluon")
FUTURE_EXOG_METHOD = os.getenv("FUTURE_EXOG_METHOD", "last")
AG_PRESET = os.getenv("AG_PRESET", "chronos2")
AG_EVAL_METRIC = os.getenv("AG_EVAL_METRIC", "MAPE")
AG_ROOT_PATH = os.getenv("AG_ROOT_PATH", "/tmp/ag_chronos2_prod")


def run_model() -> dict:
    if os.path.exists(AG_ROOT_PATH):
        shutil.rmtree(AG_ROOT_PATH, ignore_errors=True)
    os.makedirs(AG_ROOT_PATH, exist_ok=True)

    df_full = load_source_df(project_id=PROJECT_ID, source_table=SOURCE_TABLE)
    if df_full.empty:
        raise ValueError(f"La tabla fuente está vacía: {SOURCE_TABLE}")

    exog_by_asset = download_feature_config(
        project_id=PROJECT_ID,
        features_bucket=FEATURES_BUCKET,
        features_blob=FEATURES_BLOB,
    )

    preds_df = build_predictions(
        df_full=df_full,
        exog_by_asset=exog_by_asset,
        horizon=HORIZON,
        model_label=MODEL_LABEL,
        eval_metric=AG_EVAL_METRIC,
        preset=AG_PRESET,
        future_exog_method=FUTURE_EXOG_METHOD,
        model_root_path=AG_ROOT_PATH,
    )

    overwrite_model_only(
        project_id=PROJECT_ID,
        target_table=TARGET_TABLE,
        model_label=MODEL_LABEL,
        preds_df=preds_df,
    )

    return {
        "status": "ok",
        "modelo": MODEL_LABEL,
        "preset": AG_PRESET,
        "source_table": SOURCE_TABLE,
        "target_table": TARGET_TABLE,
        "features_gcs": f"gs://{FEATURES_BUCKET}/{FEATURES_BLOB}",
        "rows_inserted": int(len(preds_df)),
        "min_fecha_prediccion": str(preds_df["fecha_prediccion"].min()),
        "max_fecha_prediccion": str(preds_df["fecha_prediccion"].max()),
    }


@functions_framework.http
def autogluon_predict(request):
    if request.method != "POST":
        return (
            json.dumps(
                {"status": "error", "message": "Método no permitido. Usa POST."},
                ensure_ascii=False,
            ),
            405,
            {"Content-Type": "application/json"},
        )

    try:
        response = run_model()
        return (
            json.dumps(response, ensure_ascii=False),
            200,
            {"Content-Type": "application/json"},
        )
    except Exception as e:
        print("ERROR FATAL EN AUTOGLUON:")
        print(traceback.format_exc())
        return (
            json.dumps(
                {"status": "error", "message": str(e)},
                ensure_ascii=False,
            ),
            500,
            {"Content-Type": "application/json"},
        )