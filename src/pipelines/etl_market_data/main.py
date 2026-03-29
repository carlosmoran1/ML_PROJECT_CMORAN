import os
import warnings

import functions_framework

try:
    from src.common.gcp_utils import get_secret
    from src.pipelines.etl_market_data.extract import run_etl
except ImportError:
    from gcp_utils import get_secret
    from extract import run_etl

warnings.filterwarnings("ignore")

PROJECT_ID = os.getenv("PROJECT_ID", "proyectos-cmoran-489000")
BUCKET_NAME = os.getenv("BUCKET_RAW", "proyecto_commodities")
DESTINATION_BLOB = os.getenv("DESTINATION_BLOB", "data/raw/data_historica_full.parquet")
FRED_SECRET_ID = os.getenv("FRED_SECRET_ID", "fred-api-key")
EIA_SECRET_ID = os.getenv("EIA_SECRET_ID", "eia-api-key")


@functions_framework.http
def etl_commodities(request):
    try:
        fred_api_key = get_secret(PROJECT_ID, FRED_SECRET_ID)
        eia_api_key = get_secret(PROJECT_ID, EIA_SECRET_ID)

        run_etl(
            project_id=PROJECT_ID,
            bucket_name=BUCKET_NAME,
            destination_blob=DESTINATION_BLOB,
            fred_api_key=fred_api_key,
            eia_api_key=eia_api_key,
        )
        return ("OK - ETL ejecutada exitosamente", 200)
    except Exception as e:
        print(f"ERROR FATAL en ETL: {e}")
        return (f"ERROR: {e}", 500)
