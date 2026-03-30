import json
import os
import warnings

try:
    from src.common.ml_gcp_utils import (
        download_feature_config,
        load_source_df,
        overwrite_model_only,
    )
    from src.sarimax.train import build_predictions
except ImportError:
    from ml_gcp_utils import (
        download_feature_config,
        load_source_df,
        overwrite_model_only,
    )
    from train import build_predictions

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
MODEL_LABEL = os.getenv("MODEL_LABEL", "sarimax")
FUTURE_EXOG_METHOD = os.getenv("FUTURE_EXOG_METHOD", "last")


def main(request):
    df_full = load_source_df(project_id=PROJECT_ID, source_table=SOURCE_TABLE)
    exog_by_asset = download_feature_config(
        project_id=PROJECT_ID,
        features_bucket=FEATURES_BUCKET,
        features_blob=FEATURES_BLOB,
    )

    preds_df = build_predictions(
        df_full=df_full,
        exog_by_asset=exog_by_asset,
        horizon=HORIZON,
        future_exog_method=FUTURE_EXOG_METHOD,
        model_label=MODEL_LABEL,
    )

    overwrite_model_only(
        project_id=PROJECT_ID,
        target_table=TARGET_TABLE,
        model_label=MODEL_LABEL,
        preds_df=preds_df,
    )

    response = {
        "status": "ok",
        "modelo": MODEL_LABEL,
        "source_table": SOURCE_TABLE,
        "target_table": TARGET_TABLE,
        "features_gcs": f"gs://{FEATURES_BUCKET}/{FEATURES_BLOB}",
        "rows_inserted": int(len(preds_df)),
        "min_fecha_prediccion": str(preds_df["fecha_prediccion"].min()),
        "max_fecha_prediccion": str(preds_df["fecha_prediccion"].max()),
    }
    return (json.dumps(response, ensure_ascii=False), 200, {"Content-Type": "application/json"})