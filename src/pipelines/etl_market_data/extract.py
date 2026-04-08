import time
from datetime import datetime, timedelta

import pandas as pd
import requests
from fredapi import Fred

try:
    from src.common.gcp_utils import save_to_gcs
except ImportError:
    from gcp_utils import save_to_gcs


# ==========================================
# HELPERS DE LIMPIEZA PARA CONCAT
# ==========================================

def sanitize_df_for_concat(df: pd.DataFrame, index_name: str = "Date") -> pd.DataFrame:
    """
    Limpia un DataFrame para concatenarlo por columnas sin romper pandas:
    - fuerza índice datetime
    - elimina índices nulos
    - normaliza fechas
    - elimina índices duplicados
    - elimina columnas duplicadas
    - ordena por índice
    """
    if df is None:
        return pd.DataFrame()

    if isinstance(df, pd.Series):
        df = df.to_frame()

    if df.empty:
        df = df.copy()
        df.index.name = index_name
        return df

    df = df.copy()

    df.index = pd.to_datetime(df.index, errors="coerce")
    df = df[~df.index.isna()].copy()
    df.index = df.index.normalize()

    if df.index.has_duplicates:
        df = df[~df.index.duplicated(keep="last")].copy()

    if hasattr(df.columns, "duplicated") and df.columns.duplicated().any():
        df = df.loc[:, ~df.columns.duplicated()].copy()

    df = df.sort_index()
    df.index.name = index_name
    return df


# ==========================================
# DESCARGA DE YAHOO FINANCE SIN YFINANCE
# ==========================================

def get_yahoo_session():
    """Crea una sesión con headers de browser para evitar bloqueos."""
    session = requests.Session()
    session.headers.update(
        {
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/120.0.0.0 Safari/537.36"
            ),
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.5",
            "Accept-Encoding": "gzip, deflate, br",
            "Connection": "keep-alive",
        }
    )
    return session


def get_yahoo_crumb(session: requests.Session):
    """Obtiene el crumb necesario para autenticar requests a Yahoo Finance."""
    session.get("https://finance.yahoo.com", timeout=15)
    r = session.get("https://query1.finance.yahoo.com/v1/test/getcrumb", timeout=15)
    return r.text.strip()


def download_yahoo_symbol(symbol: str, session: requests.Session, crumb: str):
    """
    Descarga datos históricos de cierre de un símbolo desde Yahoo Finance.

    Regla de corte:
    - incluye hasta el último día cerrado
    - excluye el día actual para evitar aperturas o datos parciales intradía
    """
    utc_today = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
    end_ts = int(utc_today.timestamp())
    start_ts = int((utc_today - timedelta(days=10)).timestamp())

    url = (
        f"https://query1.finance.yahoo.com/v8/finance/chart/{symbol}"
        f"?period1={start_ts}&period2={end_ts}&interval=1d&crumb={crumb}"
    )

    try:
        r = session.get(url, timeout=20)
        data = r.json()
        result = data.get("chart", {}).get("result", [])
        if not result:
            print(f"    Sin datos para {symbol}")
            return pd.Series(dtype=float, name=symbol)

        timestamps = result[0].get("timestamp", [])
        quote = result[0].get("indicators", {}).get("quote", [{}])[0]
        closes = quote.get("close", [])

        if not timestamps or not closes:
            print(f"    Sin timestamps/cierres para {symbol}")
            return pd.Series(dtype=float, name=symbol)

        dates = pd.to_datetime(timestamps, unit="s", errors="coerce").normalize()
        s = pd.Series(closes, index=dates, name=symbol)
        s = s[s.index.notna()].dropna()
        s.index = pd.to_datetime(s.index, errors="coerce").normalize()

        # Seguridad extra: si Yahoo devolviera el día actual por algún desfase
        # horario, se elimina para no guardar aperturas o datos parciales.
        s = s[s.index < pd.Timestamp(utc_today)]

        if s.index.has_duplicates:
            s = s[~s.index.duplicated(keep="last")]

        s = s.sort_index()
        return s

    except Exception as e:
        print(f"    Error descargando {symbol}: {e}")
        return pd.Series(dtype=float, name=symbol)


def download_symbols_yahoo(symbols_map: dict, retries: int = 3, delay: int = 8):
    """
    Descarga múltiples tickers de Yahoo Finance usando requests directos.
    Devuelve DataFrame con columnas renombradas e índice Date.
    """
    for attempt in range(1, retries + 1):
        try:
            print(f"  Abriendo sesión Yahoo Finance (intento {attempt}/{retries})...")
            session = get_yahoo_session()
            crumb = get_yahoo_crumb(session)
            print(f"  Crumb obtenido: {crumb[:10]}...")

            series_list = []
            for ticker, col_name in symbols_map.items():
                print(f"    {ticker} → {col_name} ...")
                s = download_yahoo_symbol(ticker, session, crumb)
                s.name = col_name
                if not s.empty:
                    series_list.append(s)
                time.sleep(0.4)

            if not series_list:
                print(f"  Sin series válidas en intento {attempt}.")
                time.sleep(delay)
                continue

            df = pd.concat(series_list, axis=1)
            df = sanitize_df_for_concat(df)

            if not df.empty:
                print(f"  OK — shape: {df.shape} | {df.index.min()} → {df.index.max()}")
                return df

            print(f"  DataFrame vacío en intento {attempt}.")
        except Exception as e:
            print(f"  Error en intento {attempt}: {e}")
        time.sleep(delay)

    raise ValueError(
        f"No se pudieron descargar datos de Yahoo Finance después de {retries} intentos. "
        "Yahoo puede estar bloqueando la IP de Cloud Run. "
        "Considera usar una VPC con IP estática o un proxy."
    )


# ==========================================
# ETL
# ==========================================

def run_etl(
    project_id: str,
    bucket_name: str,
    destination_blob: str,
    fred_api_key: str,
    eia_api_key: str,
):
    if not fred_api_key:
        raise ValueError("No se pudo obtener FRED_API_KEY desde Secret Manager.")
    if not eia_api_key:
        raise ValueError("No se pudo obtener EIA_API_KEY desde Secret Manager.")

    print("=" * 60)
    print("INICIANDO PROCESO DE EXTRACCIÓN")
    print("=" * 60)

    # ------------------------------------------
    # 1. COMMODITIES
    # ------------------------------------------
    print("\n[1/9] Descargando commodities...")
    commodities_map = {
        "BZ=F": "petroleo_brent",
        "GC=F": "oro",
        "NG=F": "gas_natural",
        "HG=F": "cobre",
        "SI=F": "plata",
    }
    df_commodities = sanitize_df_for_concat(download_symbols_yahoo(commodities_map))
    if df_commodities.empty:
        raise ValueError("El índice de df_commodities está completamente vacío.")

    fecha_desde = df_commodities.index.min().strftime("%Y-%m-%d")
    fecha_hasta = df_commodities.index.max().strftime("%Y-%m-%d")
    print(f"  Rango de fechas: {fecha_desde} → {fecha_hasta}")

    # ------------------------------------------
    # 2. MERCADOS GLOBALES
    # ------------------------------------------
    print("\n[2/9] Descargando mercados globales...")
    global_map = {
        "^VIX": "vix",
        "^GSPC": "sp500",
        "000001.SS": "shanghai",
        "EEM": "emergentes",
        "^N225": "Nikkei",
        "^GDAXI": "DAX",
        "^FTSE": "FTSE",
        "DX=F": "dxy_fut",
    }
    df_global = sanitize_df_for_concat(download_symbols_yahoo(global_map))

    # ------------------------------------------
    # 3. ACCIONES RELEVANTES
    # ------------------------------------------
    print("\n[3/9] Descargando acciones relevantes...")
    acciones_list = [
        "AAPL", "NVDA", "MSFT", "AMZN", "GOOGL",
        "BRK-B", "JPM", "UNH", "TSM", "AMD",
        "SPY", "QQQ", "DIA",
    ]
    acciones_map = {t: t for t in acciones_list}
    df_acciones_relevantes = sanitize_df_for_concat(download_symbols_yahoo(acciones_map))

    # ------------------------------------------
    # 4. ACCIONES EMPRESAS COMMODITIES
    # ------------------------------------------
    print("\n[4/9] Descargando acciones de empresas de commodities...")
    acc_comm_list = [
        "NEM", "KGC", "AEM",
        "PAAS", "WPM", "AG",
        "FCX", "SCCO", "BHP",
        "EQT", "CTRA", "LNG",
        "XOM", "CVX", "SHEL",
    ]
    acc_comm_map = {t: t for t in acc_comm_list}
    df_acciones_commodities = sanitize_df_for_concat(download_symbols_yahoo(acc_comm_map))

    # ------------------------------------------
    # 5. RESERVA FEDERAL (FRED) — TASAS
    # ------------------------------------------
    print("\n[5/9] Descargando datos FRED (tasas diarias)...")
    fred = Fred(api_key=fred_api_key)

    series_diarias = {
        "dolar_index": "DTWEXBGS",
        "tasa_10y": "DGS10",
        "tasa_2y": "DGS2",
        "tasa_5y": "DGS5",
    }
    df_reserva_federal = pd.DataFrame()
    for nombre, codigo in series_diarias.items():
        try:
            df_reserva_federal[nombre] = fred.get_series(codigo, observation_start=fecha_desde)
        except Exception as e:
            print(f"  Advertencia FRED {codigo}: {e}")
    df_reserva_federal = sanitize_df_for_concat(df_reserva_federal)

    # ------------------------------------------
    # 6. PIB (FRED)
    # ------------------------------------------
    print("\n[6/9] Descargando PIB (FRED)...")
    pib_completo = {
        "PIB_USA": "GDP",
        "PIB_JPN": "JPNRGDPEXP",
        "PIB_DEU": "CLVMNACSCAB1GQDE",
        "PIB_GBR": "CLVMNACSCAB1GQUK",
        "PIB_FRA": "CLVMNACSCAB1GQFR",
        "PIB_ITA": "CLVMNACSCAB1GQIT",
        "PIB_CAN": "NGDPRSAXDCCAQ",
    }
    df_pib = pd.DataFrame()
    for nombre, codigo in pib_completo.items():
        try:
            df_pib[nombre] = fred.get_series(codigo, observation_start=fecha_desde)
        except Exception as e:
            print(f"  Advertencia FRED PIB {codigo}: {e}")
    df_pib = sanitize_df_for_concat(df_pib)

    # ------------------------------------------
    # 7. DESEMPLEO (FRED)
    # ------------------------------------------
    print("\n[7/9] Descargando desempleo (FRED)...")
    codes_desempleo = {
        "DESEMPLEO_USA": "UNRATE",
        "DESEMPLEO_ALE": "LRHUTTTTDEM156S",
        "DESEMPLEO_FRA": "LRHUTTTTFRM156S",
        "DESEMPLEO_INGL": "LRHUTTTTGBM156S",
        "DESEMPLEO_JPN": "LRHUTTTTJPM156S",
        "DESEMPLEO_CAN": "LRHUTTTTCAM156S",
        "DESEMPLEO_ITA": "LRHUTTTTITM156S",
        "DESEMPLEO_MEX": "LRHUTTTTMXM156S",
    }
    df_desempleo = pd.DataFrame()
    for nombre, codigo in codes_desempleo.items():
        try:
            df_desempleo[nombre] = fred.get_series(codigo, observation_start=fecha_desde)
        except Exception as e:
            print(f"  Advertencia FRED desempleo {codigo}: {e}")
    df_desempleo = sanitize_df_for_concat(df_desempleo)

    # ------------------------------------------
    # 8. EIA — PRODUCCIÓN PETRÓLEO Y GAS
    # ------------------------------------------
    print("\n[8/9] Descargando datos EIA...")
    series_eia = {
        "PET.WCRFPUS2.W": ("weekly", "produccion_petroleo_usa"),
        "NG.N9070US2.M": ("monthly", "produccion_gas_usa"),
    }
    lista_dfs_eia = []
    for series_id, (freq, nombre) in series_eia.items():
        try:
            url = f"https://api.eia.gov/v2/seriesid/{series_id}"
            params = {"api_key": eia_api_key, "frequency": freq, "offset": 0, "length": 7000}
            r = requests.get(url, params=params, timeout=30)
            data = r.json()

            if "response" in data and "data" in data["response"]:
                df_temp = pd.DataFrame(data["response"]["data"])
                df_temp = df_temp.rename(columns={"period": "Date", "value": nombre})
                df_temp["Date"] = pd.to_datetime(df_temp["Date"], errors="coerce")
                df_temp = df_temp[df_temp["Date"].notna()].copy()
                df_temp["Date"] = df_temp["Date"].dt.normalize()
                df_temp = df_temp[["Date", nombre]].sort_values("Date").reset_index(drop=True)
                df_temp = df_temp.set_index("Date")
                df_temp = sanitize_df_for_concat(df_temp)

                if not df_temp.empty:
                    lista_dfs_eia.append(df_temp)

                print(f"  OK: {nombre} — {len(df_temp)} registros")
            else:
                print(f"  Advertencia: sin datos para {series_id}")
        except Exception as e:
            print(f"  Error EIA {series_id}: {e}")

    lista_dfs_eia = [sanitize_df_for_concat(d) for d in lista_dfs_eia if not d.empty]
    df_eia_mensual = pd.concat(lista_dfs_eia, axis=1, join="outer") if lista_dfs_eia else pd.DataFrame()
    df_eia_mensual = sanitize_df_for_concat(df_eia_mensual)

    # ------------------------------------------
    # 9. DINERO CIRCULANTE — WORLD BANK
    # ------------------------------------------
    print("\n[9/9] Descargando M2 desde World Bank...")
    paises = ["USA", "CHN", "JPN", "DEU", "FRA", "ITA", "GBR", "CAN", "IND", "BRA", "MEX", "WLD"]
    df_dinero_anual = pd.DataFrame()
    try:
        url = (
            "http://api.worldbank.org/v2/country/{}/indicator/FM.LBL.BMNY.CN"
            "?format=json&per_page=20000"
        ).format(";".join(paises))
        j = requests.get(url, timeout=30).json()
        data_wb = j[1] if isinstance(j, list) and len(j) > 1 else []

        if data_wb:
            df_wb = pd.DataFrame(data_wb)
            df_wb["Date"] = pd.to_datetime(df_wb["date"] + "-12-31", errors="coerce")
            df_wb["ISO3"] = df_wb["countryiso3code"].str.upper()
            df_wb["valor"] = pd.to_numeric(df_wb["value"], errors="coerce")
            df_wb = df_wb[df_wb["Date"].notna() & df_wb["ISO3"].notna()].copy()

            df_dinero_anual = (
                df_wb.pivot_table(index="Date", columns="ISO3", values="valor", aggfunc="first")
                .sort_index()
                .reset_index()
            )

            nombres_wb = {
                "USA": "DINERO_CIRCULANTE_EEUU_M2_APROX_LCU",
                "CHN": "DINERO_CIRCULANTE_CHINA_M2_APROX_LCU",
                "JPN": "DINERO_CIRCULANTE_JAPON_M2_APROX_LCU",
                "DEU": "DINERO_CIRCULANTE_ALEMANIA_M2_APROX_LCU",
                "FRA": "DINERO_CIRCULANTE_FRANCIA_M2_APROX_LCU",
                "ITA": "DINERO_CIRCULANTE_ITALIA_M2_APROX_LCU",
                "GBR": "DINERO_CIRCULANTE_REINO_UNIDO_M2_APROX_LCU",
                "CAN": "DINERO_CIRCULANTE_CANADA_M2_APROX_LCU",
                "IND": "DINERO_CIRCULANTE_INDIA_M2_APROX_LCU",
                "BRA": "DINERO_CIRCULANTE_BRASIL_M2_APROX_LCU",
                "MEX": "DINERO_CIRCULANTE_MEXICO_M2_APROX_LCU",
                "WLD": "DINERO_CIRCULANTE_MUNDO_M2_APROX_LCU",
            }

            presentes = {k: v for k, v in nombres_wb.items() if k in df_dinero_anual.columns}
            df_dinero_anual = df_dinero_anual.rename(columns=presentes)
            orden = ["Date"] + [nombres_wb[k] for k in paises if k in presentes]
            cols_existentes = [c for c in orden if c in df_dinero_anual.columns]
            df_dinero_anual = df_dinero_anual[cols_existentes].set_index("Date")
            df_dinero_anual = sanitize_df_for_concat(df_dinero_anual)
            print(f"  OK: World Bank M2 — {df_dinero_anual.shape}")
        else:
            print("  Advertencia: World Bank no devolvió datos.")
    except Exception as e:
        print(f"  Error World Bank: {e}")

    # ------------------------------------------
    # CONCATENAR TODO
    # ------------------------------------------
    print("\n--- Concatenando todos los DataFrames ---")
    nombres_dfs = [
        ("df_commodities", df_commodities),
        ("df_global", df_global),
        ("df_acciones_relevantes", df_acciones_relevantes),
        ("df_acciones_commodities", df_acciones_commodities),
        ("df_reserva_federal", df_reserva_federal),
        ("df_pib", df_pib),
        ("df_desempleo", df_desempleo),
        ("df_eia_mensual", df_eia_mensual),
        ("df_dinero_anual", df_dinero_anual),
    ]

    dfs_to_concat = []
    for nombre, df in nombres_dfs:
        if df is not None and not df.empty:
            df = sanitize_df_for_concat(df)
            dup_idx = int(df.index.duplicated().sum()) if df.index is not None else -1
            dup_cols = int(df.columns.duplicated().sum()) if hasattr(df.columns, "duplicated") else 0
            print(f"  {nombre}: shape={df.shape} | dup_idx={dup_idx} | dup_cols={dup_cols}")
            dfs_to_concat.append(df)

    if not dfs_to_concat:
        raise ValueError("No hay DataFrames válidos para concatenar.")

    df_final = pd.concat(dfs_to_concat, axis=1, join="outer")
    df_final = sanitize_df_for_concat(df_final)

    # FIX: reindexar sobre fechas de mercado (índice de commodities = fuente principal)
    # Esto elimina las filas con fechas semanales/mensuales/anuales que vienen de
    # EIA, FRED y World Bank y que no corresponden a días de mercado.
    # Las columnas de baja frecuencia (EIA, PIB, desempleo, M2) mantienen sus nulls
    # en días donde no tienen dato — eso es correcto y esperado.
    df_final = df_final.reindex(df_commodities.index)
    df_final.index.name = "Date"

    print(f"  DataFrame final shape: {df_final.shape}")
    print(f"  Columnas totales: {len(df_final.columns)}")
    print(f"  Rango final: {df_final.index.min()} → {df_final.index.max()}")

    save_to_gcs(
        df=df_final,
        project_id=project_id,
        bucket_name=bucket_name,
        destination_blob=destination_blob,
    )
    print("\nETL FINALIZADA EXITOSAMENTE.")