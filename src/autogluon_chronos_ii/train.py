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

    x_hist = (
        df_hist.reindex(columns=exog_cols)
        .replace([np.inf, -np.inf], np.nan)
        .ffill()
    )
    med = x_hist.median(numeric_only=True).fillna(0.0)
    x_hist = x_hist.fillna(med)

    out = df_hist.copy()
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

    x_hist = (
        df_train_hist.reindex(columns=exog_cols)
        .replace([np.inf, -np.inf], np.nan)
        .ffill()
    )
    med = (
        df_train_hist.reindex(columns=exog_cols)
        .replace([np.inf, -np.inf], np.nan)
        .median(numeric_only=True)
        .fillna(0.0)
    )
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

    exog_cols = [col for col in exog_by_asset.get(asset, []) if col in df_full.columns]

    train_cols = [asset] + exog_cols
    df_train = df_full[train_cols].copy()
    df_train = prep_hist_exog(df_train, exog_cols)

    train_reset = df_train.reset_index().rename(columns={"date": "timestamp", asset: "target"})
    train_reset["item_id"] = asset
    train_for_ag = train_reset[["item_id", "timestamp", "target"] + exog_cols]

    train_data = TimeSeriesDataFrame.from_data_frame(
        train_for_ag,
        id_column="item_id",
        timestamp_column="timestamp",
    )

    known_covariates = None
    if exog_cols:
        x_future = make_future_exog_from_train(
            df_train,
            exog_cols,
            future_index,
            method=future_exog_method,
        )
        x_future = x_future.reset_index().rename(columns={"index": "timestamp"})
        x_future["item_id"] = asset
        known_covariates = TimeSeriesDataFrame.from_data_frame(
            x_future[["item_id", "timestamp"] + exog_cols],
            id_column="item_id",
            timestamp_column="timestamp",
        )

    model_path = os.path.join(model_root_path, asset)
    if os.path.exists(model_path):
        shutil.rmtree(model_path, ignore_errors=True)

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

    pred_df = pred.reset_index()
    if "mean" in pred_df.columns:
        series = pred_df["mean"].astype(float).reset_index(drop=True)
    else:
        numeric_cols = pred_df.select_dtypes(include=[np.number]).columns.tolist()
        if not numeric_cols:
            raise ValueError(f"No se encontró columna numérica en la predicción de {asset}.")
        series = pred_df[numeric_cols[0]].astype(float).reset_index(drop=True)

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
    targets_num = df_full[TARGET_COLS].apply(pd.to_numeric, errors="coerce")
    valid_mask = targets_num.notna().any(axis=1)
    last_date = targets_num.loc[valid_mask].index.max()
    future_index = pd.bdate_range(last_date + BDay(1), periods=horizon)

    preds_wide = pd.DataFrame(index=future_index)
    for asset in TARGET_COLS:
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

    preds_wide = preds_wide.reset_index().rename(columns={"index": "fecha_prediccion"})
    preds_wide["fecha_prediccion"] = pd.to_datetime(preds_wide["fecha_prediccion"]).dt.date
    preds_wide["modelo"] = model_label

    return preds_wide[
        ["fecha_prediccion", "oro", "plata", "cobre", "petroleo_brent", "gas_natural", "modelo"]
    ]
