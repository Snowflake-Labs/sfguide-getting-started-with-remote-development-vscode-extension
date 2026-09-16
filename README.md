# sfguide-getting-started-with-remote-development-vscode-extension

Companion repo for the Snowflake Quickstart **Getting Started with Remote Development in the Snowflake VS Code Extension**.

Companion to the Quickstart at:
https://quickstarts.snowflake.com/guide/get-started-with-remote-development-snowflake-vscode-extension/

## What's here

- **setup.sql** – Stands up the `tb_101` Tasty Bytes database, external stage, all raw tables, `COPY INTO` for every table (~1B rows total on a Large warehouse), the compute pool for the remote notebook service, the external access integration for GitHub + PyPI, the **Pelmorex Weather Source: Frostbyte** Marketplace share (acquired programmatically), and a Snowflake Workspace.
- **cleanup.sql** – Drops everything `setup.sql` created.
- **forecast.ipynb** – The Jupyter notebook you run inside the remote SSH session. Confirms the load, aggregates orders to daily-per-location grain, joins Marketplace weather, engineers features inline (calendar / lag / rolling-precip transforms), trains an XGBoost model, and logs it to the Snowflake Model Registry.
- **train.py** – Standalone Python script that reads the feature table, trains XGBoost, evaluates on a holdout week, and logs the model to the registry. Runs both from a terminal and from a notebook cell.

## Prerequisites

See the Quickstart for the full list. In short:

- A Snowflake account with a role that can create notebook services (compute pool USAGE, EAI + secret privileges).
- The `ENABLE_NOTEBOOK_SERVICE_REMOTE_VS_CODE_ACCESS` account parameter enabled (default is on).
- VS Code or Cursor + the Microsoft **Remote - SSH** extension + the **Snowflake Extension for VS Code v1.39+**.
- Access to the Snowflake Marketplace (setup.sql acquires the free **Pelmorex Weather Source: Frostbyte** share programmatically).
- Snowflake CLI (`snow`) with a configured connection, to run setup.sql / cleanup.sql.

## Quickstart flow

1. Run `setup.sql` with the Snowflake CLI (`snow sql -f setup.sql`) or in a Snowsight worksheet. It also acquires the **Pelmorex Weather Source: Frostbyte** Marketplace share programmatically.
2. Create a remote development environment from the Snowflake VS Code extension.
3. Setup SSH, then clone this repo into `/mnt/pd0` in the remote window.
4. Open `forecast.ipynb`, run the cells in order.
5. When done, delete the remote service in the extension, then run `cleanup.sql` (`snow sql -f cleanup.sql`).

Full walk-through: see the Quickstart.
