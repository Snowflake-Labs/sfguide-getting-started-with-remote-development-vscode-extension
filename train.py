"""Train an XGBoost sales forecaster and log it to the Snowflake Model Registry.

Uses the notebook's active Snowflake session when run in-kernel, or builds one
from the container's credentials when run standalone (terminal, Run Python File,
or `!python`). Reads the feature table produced by the notebook, does a
time-based train/test split, fits the model, evaluates on the held-out week, and
registers the model.

Usage inside the remote SSH window:
    python train.py --source-table tb_101.ml.feature_table \\
                    --database tb_101 --schema ml \\
                    --model-name tb_sales_forecaster --version v1
"""

from __future__ import annotations

import argparse

import pandas as pd
from sklearn.metrics import mean_absolute_percentage_error, mean_squared_error
from xgboost import XGBRegressor

from snowflake.ml.registry import Registry


def get_session(warehouse=None, database=None, schema=None):
    """Return a Snowpark session.

    Inside the notebook kernel, reuse the active session. When run as a
    standalone process (from the terminal, the Run Python File button, or
    `!python`), there is no active session, so build one from the SPCS
    container's OAuth token (see the Snowpark Container Services docs).
    """
    try:
        from snowflake.snowpark.context import get_active_session

        session = get_active_session()
    except Exception:
        import os

        from snowflake.snowpark import Session

        with open("/snowflake/session/token") as f:
            token = f.read()
        session = Session.builder.configs(
            {
                "account": os.environ["SNOWFLAKE_ACCOUNT"],
                "host": os.environ["SNOWFLAKE_HOST"],
                "authenticator": "oauth",
                "token": token,
            }
        ).create()

    # Standalone sessions have no context set; the kernel session is
    # unaffected by re-applying the same values.
    if warehouse:
        session.use_warehouse(warehouse)
    if database:
        session.use_database(database)
    if schema:
        session.use_schema(schema)
    return session


FEATURE_COLS = [
    "day_of_week",
    "month",
    "is_weekend",
    "temp_c",
    "precip_mm",
    "wind_kph",
    "precip_mm_roll_7",
    "daily_sales_lag_1",
    "daily_sales_lag_7",
]
TARGET_COL = "daily_sales"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train Tasty Bytes sales forecaster.")
    parser.add_argument("--source-table", required=True, help="Fully qualified feature table")
    parser.add_argument("--database", required=True, help="Database for the model registry")
    parser.add_argument("--schema", required=True, help="Schema for the model registry")
    parser.add_argument("--model-name", default="tb_sales_forecaster", help="Model name")
    parser.add_argument("--version", default="v1", help="Model version")
    parser.add_argument("--warehouse", default="tb_de_wh", help="Warehouse for standalone runs")
    parser.add_argument("--holdout-days", type=int, default=7, help="Days to hold out for test")
    return parser.parse_args()


def load_feature_frame(session, source_table: str) -> pd.DataFrame:
    """Load the feature table into a pandas DataFrame on the remote container."""
    df = session.table(source_table).to_pandas()
    df.columns = [c.lower() for c in df.columns]
    df["date"] = pd.to_datetime(df["date"])
    return df.sort_values(["location_id", "date"]).reset_index(drop=True)


def time_split(df: pd.DataFrame, holdout_days: int) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Hold out the last `holdout_days` days globally."""
    cutoff = df["date"].max() - pd.Timedelta(days=holdout_days)
    train = df[df["date"] <= cutoff]
    test = df[df["date"] > cutoff]
    return train, test


def main() -> None:
    args = parse_args()
    session = get_session(args.warehouse, args.database, args.schema)

    print(f"Loading features from {args.source_table} ...")
    df = load_feature_frame(session, args.source_table)
    print(f"  {len(df):,} rows across {df['location_id'].nunique()} locations")

    train_df, test_df = time_split(df, args.holdout_days)
    print(f"  Train: {len(train_df):,} rows | Test: {len(test_df):,} rows")

    X_train, y_train = train_df[FEATURE_COLS], train_df[TARGET_COL]
    X_test, y_test = test_df[FEATURE_COLS], test_df[TARGET_COL]

    model = XGBRegressor(
        n_estimators=400,
        max_depth=6,
        learning_rate=0.05,
        subsample=0.8,
        colsample_bytree=0.8,
        random_state=42,
    )
    model.fit(X_train, y_train)

    preds = model.predict(X_test)
    mape = mean_absolute_percentage_error(y_test, preds)
    rmse = mean_squared_error(y_test, preds) ** 0.5
    print(f"Holdout MAPE: {mape:.3f}  |  RMSE: {rmse:,.2f}")

    print(f"Logging model to registry: {args.database}.{args.schema}.{args.model_name} ({args.version}) ...")
    registry = Registry(
        session=session,
        database_name=args.database,
        schema_name=args.schema,
    )
    registry.log_model(
        model,
        model_name=args.model_name,
        version_name=args.version,
        sample_input_data=X_train.head(),
        comment=f"Tasty Bytes daily sales forecaster. Holdout MAPE={mape:.3f}, RMSE={rmse:.2f}.",
        # Log for both platforms so the model can run via warehouse inference
        # (model_ref.run on a pandas frame) as well as in SPCS. Container Runtime
        # otherwise defaults to SNOWPARK_CONTAINER_SERVICES only.
        target_platforms=["WAREHOUSE", "SNOWPARK_CONTAINER_SERVICES"],
    )
    print("Done. The model is now discoverable from the Model Registry.")


if __name__ == "__main__":
    main()
