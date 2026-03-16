import numpy as np
import pandas as pd
import scipy.special as sps
import scipy.stats as stats
from pandas.tseries.offsets import BDay
from statsmodels.tsa.statespace.sarimax import SARIMAX


TARGET_COLS = ["oro", "plata", "cobre", "petroleo_brent", "gas_natural"]

SARIMAX_DAILY_CFG = {
    "oro": {"order": (2, 1, 0), "seasonal_order": (2, 0, 1, 5), "transform": "yeojohnson"},
    "plata": {"order": (1, 1, 2), "seasonal_order": (1, 0, 1, 5), "transform": "yeojohnson"},
    "cobre": {"order": (3, 1, 2), "seasonal_order": (0, 0, 0, 0), "transform": "yeojohnson"},
    "gas_natural": {"order": (1, 1, 0), "seasonal_order": (0, 0, 0, 0), "transform": "yeojohnson"},
    "petroleo_brent": {"order": (1, 1, 2), "seasonal_order": (0, 0, 1, 5), "transform": "yeojohnson"},
}


def fit_lambda_from_train(y_train, transform_type):
    transform_type = (transform_type or "none").lower()
    y = np.asarray(pd.Series(y_train).dropna().values, dtype=float)

    if transform_type in ("none", None):
        return None, 0.0

    if transform_type == "yeojohnson":
        _, lmbda = stats.yeojohnson(y)
        return float(lmbda), 0.0

    if transform_type == "boxcox":
        min_y = float(np.min(y)) if len(y) else 0.0
        shift = 0.0
        if min_y <= 0:
            shift = (-min_y) + 1e-6
        y_pos = np.maximum(y + shift, 1e-12)
        _, lmbda = stats.boxcox(y_pos)
        return float(lmbda), float(shift)

    if transform_type == "log":
        return None, 0.0

    raise ValueError(f"transform_type no soportado: {transform_type}")


def transform_with_fixed_lambda(y, transform_type, lmbda, shift=0.0):
    transform_type = (transform_type or "none").lower()
    y = np.asarray(y, dtype=float)

    if transform_type in ("none", None):
        return y

    if transform_type == "log":
        return np.log(np.maximum(y, 1e-12))

    if transform_type == "boxcox":
        y_pos = np.maximum(y + shift, 1e-12)
        return stats.boxcox(y_pos, lmbda=lmbda)

    if transform_type == "yeojohnson":
        return stats.yeojohnson(y, lmbda=lmbda)

    raise ValueError(f"transform_type no soportado: {transform_type}")


def yeojohnson_inv(y_t, lmbda):
    y_t = np.asarray(y_t, dtype=float)
    lmbda = float(lmbda)

    out = np.empty_like(y_t, dtype=float)
    pos = y_t >= 0

    if abs(lmbda) < 1e-12:
        out[pos] = np.expm1(y_t[pos])
    else:
        base = lmbda * y_t[pos] + 1.0
        base = np.maximum(base, 1e-12)
        out[pos] = np.power(base, 1.0 / lmbda) - 1.0

    neg = ~pos
    if abs(lmbda - 2.0) < 1e-12:
        out[neg] = 1.0 - np.exp(-y_t[neg])
    else:
        base = -(2.0 - lmbda) * y_t[neg] + 1.0
        base = np.maximum(base, 1e-12)
        out[neg] = 1.0 - np.power(base, 1.0 / (2.0 - lmbda))

    return out


def inv_transform_with_fixed_lambda(y_t, transform_type, lmbda, shift=0.0):
    transform_type = (transform_type or "none").lower()
    y_t = np.asarray(y_t, dtype=float)

    if transform_type in ("none", None):
        return y_t

    if transform_type == "log":
        return np.exp(y_t)

    if transform_type == "boxcox":
        if lmbda is None:
            raise ValueError("Se requiere lmbda para 'boxcox'.")
        y = sps.inv_boxcox(y_t, lmbda)
        return y - shift

    if transform_type == "yeojohnson":
        if lmbda is None:
            raise ValueError("Se requiere lmbda para 'yeojohnson'.")
        return yeojohnson_inv(y_t, lmbda)

    raise ValueError(f"transform_type no soportado: {transform_type}")


def prep_exog(df_hist: pd.DataFrame, exog_cols: list[str], df_train_base: pd.DataFrame):
    if len(exog_cols) == 0:
        return None

    x_hist = (
        df_hist.reindex(columns=exog_cols)
        .replace([np.inf, -np.inf], np.nan)
        .ffill()
    )
    med = (
        df_train_base.reindex(columns=exog_cols)
        .replace([np.inf, -np.inf], np.nan)
        .median(numeric_only=True)
        .fillna(0.0)
    )
    return x_hist.fillna(med)


def make_future_exog_from_train(
    df_train_hist: pd.DataFrame,
    exog_cols: list[str],
    future_index: pd.DatetimeIndex,
    method: str = "last",
):
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


def build_predictions(
    df_full: pd.DataFrame,
    exog_by_asset: dict,
    horizon: int,
    future_exog_method: str,
    model_label: str,
) -> pd.DataFrame:
    targets_num = df_full[TARGET_COLS].apply(pd.to_numeric, errors="coerce")
    valid_mask = targets_num.notna().any(axis=1)

    last_date = targets_num.loc[valid_mask].index.max()
    future_index = pd.bdate_range(last_date + BDay(1), periods=horizon)
    preds_wide = pd.DataFrame(index=future_index)

    for asset in TARGET_COLS:
        if asset not in df_full.columns:
            raise ValueError(f"El target '{asset}' no existe en la tabla fuente.")

        cfg = SARIMAX_DAILY_CFG[asset]
        exog_cols = [col for col in exog_by_asset.get(asset, []) if col in df_full.columns]

        y_train = pd.to_numeric(df_full[asset], errors="coerce").dropna()
        if len(y_train) == 0:
            raise ValueError(f"[{asset}] y_train vacío tras coerción/dropna.")

        lmbda, shift = fit_lambda_from_train(y_train.values, cfg.get("transform"))
        y_t = transform_with_fixed_lambda(y_train.values, cfg.get("transform"), lmbda, shift)

        train_base = df_full.loc[y_train.index].copy()
        x_train = prep_exog(train_base, exog_cols, train_base) if exog_cols else None
        x_future = (
            make_future_exog_from_train(
                train_base,
                exog_cols,
                future_index,
                method=future_exog_method,
            )
            if exog_cols
            else None
        )

        model = SARIMAX(
            endog=y_t,
            exog=None if x_train is None else x_train.values,
            order=tuple(cfg["order"]),
            seasonal_order=tuple(cfg["seasonal_order"]),
            enforce_stationarity=False,
            enforce_invertibility=False,
        )
        fitted = model.fit(disp=False)
        yhat_t = fitted.forecast(
            steps=len(future_index),
            exog=None if x_future is None else x_future.values,
        )
        yhat = inv_transform_with_fixed_lambda(yhat_t, cfg.get("transform"), lmbda, shift)
        preds_wide[asset] = np.asarray(yhat, dtype=float)

    preds_wide = preds_wide.reset_index().rename(columns={"index": "fecha_prediccion"})
    preds_wide["fecha_prediccion"] = pd.to_datetime(preds_wide["fecha_prediccion"]).dt.date
    preds_wide["modelo"] = model_label

    return preds_wide[
        ["fecha_prediccion", "oro", "plata", "cobre", "petroleo_brent", "gas_natural", "modelo"]
    ]
