import os

import pandas as pd
from google.cloud import secretmanager
from google.cloud import storage



def get_secret(project_id: str, secret_id: str):
    """Obtiene un secreto desde Secret Manager."""
    try:
        client = secretmanager.SecretManagerServiceClient()
        name = f"projects/{project_id}/secrets/{secret_id}/versions/latest"
        response = client.access_secret_version(request={"name": name})
        return response.payload.data.decode("UTF-8")
    except Exception as e:
        print(f"Error obteniendo secreto {secret_id}: {e}")
        return None



def save_to_gcs(df: pd.DataFrame, project_id: str, bucket_name: str, destination_blob: str):
    """
    Guarda el DataFrame en GCS en formato Parquet.
    La fecha se guarda como columna explícita 'Date' para que BigQuery no la lea
    como un entero proveniente del índice del parquet.
    """
    print(f"--- Guardando data en gs://{bucket_name}/{destination_blob} ---")
    temp_file = "/tmp/temp_data.parquet"

    df_to_save = df.copy()
    df_to_save.index = pd.to_datetime(df_to_save.index, errors="coerce")
    df_to_save = df_to_save[~df_to_save.index.isna()].copy()
    df_to_save.index = df_to_save.index.normalize()
    df_to_save.index.name = "Date"

    df_to_save = df_to_save.reset_index()
    df_to_save["Date"] = pd.to_datetime(df_to_save["Date"], errors="coerce").dt.date

    df_to_save.to_parquet(temp_file, index=False)

    client = storage.Client(project=project_id)
    bucket = client.bucket(bucket_name)
    blob = bucket.blob(destination_blob)
    blob.upload_from_filename(temp_file)

    print("Data cargada exitosamente.")
    os.remove(temp_file)
