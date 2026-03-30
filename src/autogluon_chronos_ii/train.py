import os
import shutil

import numpy as np
import pandas as pd
from pandas.tseries.offsets import BDay
from autogluon.timeseries import TimeSeriesDataFrame, TimeSeriesPredictor


TARGET_COLS = ["oro", "plata", "cobre", "petroleo_brent", "gas_natural"]


def prep_hist_exog(df_hist: pd.DataFrame, exog_cols: list[str]) -> pd.DataFrame:
    if len(exog_cols) == 0:
        return df_hist

    out = df_hist.copy()

    for col in exog_cols:
        out[col] = pd.to_numeric(out[col], errors="coerce")

    x_hist = (
        out.reindex(columns=exog_cols)
        .replace([np.inf, -np.inf], np.nan)
        .ffill()
    )

    med = x_hist.median(numeric_only=True).fillna(0.0)
    x_hist = x_hist.fillna(med)

    for col in exog_cols:
        out[col] = x_hist[col]

    return out


def make_future_exog_from_train(
    df_train_hist: pd.DataFrame,
    exog_cols: list[str],
    future_index: pd.DatetimeIndex,
    method: str = "last",
) -> pd.DataFrame | None:
    if len(exog_cols) == 0:
        return None

    x_hist = df_train_hist.reindex(columns=exog_cols).copy()

    for col in exog_cols:
        x_hist[col] = pd.to_numeric(x_hist[col], errors="coerce")

    x_hist = x_hist.replace([np.inf, -np.inf], np.nan).ffill()

    med = x_hist.median(numeric_only=True).fillna(0.0)
    x_hist = x_hist.fillna(med)

    method = (method or "last").lower()
    if x_hist.shape[0] == 0:
        fill_row = med
    elif method == "median":
        fill_row = med
    elif method == "mode":
        modes = x_hist.mode(dropna=True)
        fill_row = (modes.iloc[0] if len(modes) else med).fillna(med)
    else:
        fill_row = x_hist.iloc[-1].fillna(med)

    return pd.DataFrame(
        np.repeat(np.asarray(fill_row, dtype=float)[None, :], repeats=len(future_index), axis=0),
        index=future_index,
        columns=exog_cols,
    )


def naive_forecast_from_history(
    asset: str,
    df_full: pd.DataFrame,
    future_index: pd.DatetimeIndex,
) -> pd.Series:
    hist = pd.to_numeric(df_full[asset], errors="coerce").dropna()

    if hist.empty:
        raise ValueError(f"[{asset}] no tiene historia válida para fallback naive.")

    last_val = float(hist.iloc[-1])
    return pd.Series([last_val] * len(future_index), index=future_index, name=asset)


def _fit_predict_autogluon(
    train_reset: pd.DataFrame,
    horizon: int,
    eval_metric: str,
    preset: str,
    model_path: str,
    exog_cols: list[str] | None = None,
    known_covariates: TimeSeriesDataFrame | None = None,
) -> pd.DataFrame:
    exog_cols = exog_cols or []

    keep_cols = ["item_id", "timestamp", "target"] + exog_cols
    train_data = TimeSeriesDataFrame.from_data_frame(
        train_reset[keep_cols],
        id_column="item_id",
        timestamp_column="timestamp",
    )

    predictor = TimeSeriesPredictor(
        target="target",
        prediction_length=horizon,
        eval_metric=eval_metric,
        known_covariates_names=exog_cols if exog_cols else None,
        path=model_path,
        verbosity=2,
    ).fit(
        train_data=train_data,
        presets=preset,
    )

    pred = (
        predictor.predict(train_data, known_covariates=known_covariates)
        if known_covariates is not None
        else predictor.predict(train_data)
    )

    return pred.reset_index()


def forecast_one_asset(
    asset: str,
    df_full: pd.DataFrame,
    exog_by_asset: dict,
    future_index: pd.DatetimeIndex,
    horizon: int,
    eval_metric: str,
    preset: str,
    future_exog_method: str,
    model_root_path: str,
) -> pd.Series:
    if asset not in df_full.columns:
        raise ValueError(f"El target '{asset}' no existe en la tabla fuente.")

    # MISMAS exógenas del CSV / misma lógica que SARIMAX
    exog_cols = [col for col in exog_by_asset.get(asset, []) if col in df_full.columns]

    train_cols = [asset] + exog_cols
    df_train = df_full[train_cols].copy()
    df_train = df_train.sort_index()

    if df_train.index.has_duplicates:
        df_train = df_train[~df_train.index.duplicated(keep="last")].copy()

    # Limpieza robusta del target
    df_train[asset] = pd.to_numeric(df_train[asset], errors="coerce")
    df_train = df_train[df_train[asset].notna()].copy()

    if df_train.empty:
        raise ValueError(f"[{asset}] serie vacía después de limpiar target.")

    # Muy poca historia => fallback naive
    min_hist = max(20, horizon * 3)
    if len(df_train) < min_hist:
        print(f"[WARN] {asset}: historia insuficiente para AutoGluon ({len(df_train)} filas).")
        return naive_forecast_from_history(asset, df_full, future_index)

    # Limpieza de exógenas
    df_train = prep_hist_exog(df_train, exog_cols)

    train_reset = df_train.reset_index().rename(columns={"date": "timestamp", asset: "target"})
    train_reset["item_id"] = asset
    train_reset["target"] = pd.to_numeric(train_reset["target"], errors="coerce")
    train_reset = train_reset[train_reset["target"].notna()].copy()

    if train_reset.empty:
        raise ValueError(f"[{asset}] target vacío en train_reset.")

    pred_df = None

    # Intento 1: con las MISMAS exógenas del CSV
    if exog_cols:
        try:
            model_path = os.path.join(model_root_path, asset)
            if os.path.exists(model_path):
                shutil.rmtree(model_path, ignore_errors=True)

            x_future = make_future_exog_from_train(
                df_train_hist=df_train,
                exog_cols=exog_cols,
                future_index=future_index,
                method=future_exog_method,
            )

            x_future = x_future.reset_index().rename(columns={"index": "timestamp"})
            x_future["item_id"] = asset

            known_covariates = TimeSeriesDataFrame.from_data_frame(
                x_future[["item_id", "timestamp"] + exog_cols],
                id_column="item_id",
                timestamp_column="timestamp",
            )

            pred_df = _fit_predict_autogluon(
                train_reset=train_reset,
                horizon=horizon,
                eval_metric=eval_metric,
                preset=preset,
                model_path=model_path,
                exog_cols=exog_cols,
                known_covariates=known_covariates,
            )
        except Exception as e:
            print(f"[WARN] {asset}: falló con exógenas -> {e}")

    # Intento 2: sin exógenas
    if pred_df is None:
        try:
            model_path_uni = os.path.join(model_root_path, f"{asset}_uni")
            if os.path.exists(model_path_uni):
                shutil.rmtree(model_path_uni, ignore_errors=True)

            pred_df = _fit_predict_autogluon(
                train_reset=train_reset[["item_id", "timestamp", "target"]].copy(),
                horizon=horizon,
                eval_metric=eval_metric,
                preset=preset,
                model_path=model_path_uni,
                exog_cols=[],
                known_covariates=None,
            )
        except Exception as e:
            print(f"[WARN] {asset}: falló sin exógenas -> {e}")
            return naive_forecast_from_history(asset, df_full, future_index)

    if "mean" in pred_df.columns:
        series = pred_df["mean"].astype(float).reset_index(drop=True)
    else:
        numeric_cols = pred_df.select_dtypes(include=[np.number]).columns.tolist()
        if not numeric_cols:
            print(f"[WARN] {asset}: predicción sin columnas numéricas. Usando fallback naive.")
            return naive_forecast_from_history(asset, df_full, future_index)
        series = pred_df[numeric_cols[0]].astype(float).reset_index(drop=True)

    if len(series) != len(future_index):
        print(f"[WARN] {asset}: largo de predicción inesperado. Usando fallback naive.")
        return naive_forecast_from_history(asset, df_full, future_index)

    return pd.Series(series.values, index=future_index, name=asset)


def build_predictions(
    df_full: pd.DataFrame,
    exog_by_asset: dict,
    horizon: int,
    model_label: str,
    eval_metric: str,
    preset: str,
    future_exog_method: str,
    model_root_path: str,
) -> pd.DataFrame:
    df_full = df_full.copy()
    df_full = df_full.sort_index()

    if df_full.index.has_duplicates:
        df_full = df_full[~df_full.index.duplicated(keep="last")].copy()

    missing_targets = [c for c in TARGET_COLS if c not in df_full.columns]
    if missing_targets:
        raise ValueError(f"Faltan targets en la tabla fuente: {missing_targets}")

    targets_num = df_full[TARGET_COLS].apply(pd.to_numeric, errors="coerce")
    valid_mask = targets_num.notna().any(axis=1)

    if not valid_mask.any():
        raise ValueError("No hay observaciones válidas en TARGET_COLS para construir predicciones.")

    last_date = targets_num.loc[valid_mask].index.max()
    future_index = pd.bdate_range(last_date + BDay(1), periods=horizon)

    preds_wide = pd.DataFrame(index=future_index)

    for asset in TARGET_COLS:
        try:
            preds_wide[asset] = forecast_one_asset(
                asset=asset,
                df_full=df_full,
                exog_by_asset=exog_by_asset,
                future_index=future_index,
                horizon=horizon,
                eval_metric=eval_metric,
                preset=preset,
                future_exog_method=future_exog_method,
                model_root_path=model_root_path,
            )
        except Exception as e:
            print(f"[WARN] {asset}: error no controlado -> {e}. Usando fallback naive.")
            preds_wide[asset] = naive_forecast_from_history(asset, df_full, future_index)

    preds_wide = preds_wide.reset_index().rename(columns={"index": "fecha_prediccion"})
    preds_wide["fecha_prediccion"] = pd.to_datetime(preds_wide["fecha_prediccion"]).dt.date
    preds_wide["modelo"] = model_label

    return preds_wide[
        ["fecha_prediccion", "oro", "plata", "cobre", "petroleo_brent", "gas_natural", "modelo"]
    ]