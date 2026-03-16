import io
import pandas as pd
from google.cloud import bigquery, storage
from google.cloud.bigquery import QueryJobConfig, ScalarQueryParameter, LoadJobConfig


def download_feature_config(project_id: str, features_bucket: str, features_blob: str) -> dict:
    storage_client = storage.Client(project=project_id)
    blob = storage_client.bucket(features_bucket).blob(features_blob)
    csv_bytes = blob.download_as_bytes()
    cfg_df = pd.read_csv(io.BytesIO(csv_bytes))
    cfg_df.columns = [c.strip().lower() for c in cfg_df.columns]

    required = {"commodity", "variable"}
    if not required.issubset(cfg_df.columns):
        raise ValueError(
            f"El CSV debe contener columnas {required}. Encontrado: {cfg_df.columns.tolist()}"
        )

    if "usada" in cfg_df.columns:
        cfg_df = cfg_df[cfg_df["usada"].fillna(0).astype(int) == 1].copy()

    cfg_df["commodity"] = cfg_df["commodity"].astype(str).str.lower().str.strip()
    cfg_df["variable"] = cfg_df["variable"].astype(str).str.lower().str.strip()

    return (
        cfg_df.dropna(subset=["commodity", "variable"])
        .groupby("commodity")["variable"]
        .apply(list)
        .to_dict()
    )


def load_source_df(project_id: str, source_table: str) -> pd.DataFrame:
    client = bigquery.Client(project=project_id)
    query = f"SELECT * FROM `{source_table}` WHERE Date IS NOT NULL ORDER BY Date"
    df = client.query(query).to_dataframe()
    df.columns = [c.lower() for c in df.columns]

    if "date" not in df.columns:
        raise ValueError("La tabla fuente debe contener la columna Date/date.")

    df["date"] = pd.to_datetime(df["date"], errors="coerce")
    df = df.dropna(subset=["date"]).sort_values("date")
    df = df.drop_duplicates(subset=["date"], keep="last")
    df = df.set_index("date")
    df = df[df.index.dayofweek < 5].copy()
    return df


def overwrite_model_only(
    project_id: str,
    target_table: str,
    model_label: str,
    preds_df: pd.DataFrame,
) -> None:
    client = bigquery.Client(project=project_id)

    delete_sql = f"DELETE FROM `{target_table}` WHERE modelo = @modelo"
    job_config = QueryJobConfig(
        query_parameters=[ScalarQueryParameter("modelo", "STRING", model_label)]
    )
    client.query(delete_sql, job_config=job_config).result()

    load_config = LoadJobConfig(write_disposition="WRITE_APPEND")
    client.load_table_from_dataframe(preds_df, target_table, job_config=load_config).result()
