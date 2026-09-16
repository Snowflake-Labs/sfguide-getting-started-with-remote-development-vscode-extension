-- =============================================================================
-- Remote Development for the Snowflake VS Code Extension – Setup
--
-- Provisions everything the Quickstart needs:
--   1. A Large virtual warehouse for the bulk load
--   2. The tb_101 Tasty Bytes database and schemas
--   3. A public S3 stage against s3://sfquickstarts/frostbyte_tastybytes/
--   4. Raw tables + harmonized/analytics views
--   5. COPY INTO for every raw Tasty Bytes table (~1B rows total across facts)
--   6. A compute pool for the remote development notebook service
--   7. An External Access Integration allowing outbound to github.com + pypi.org
--   8. The Pelmorex Weather Source: Frostbyte Marketplace share, acquired programmatically
--   9. A Snowflake Workspace for the remote environment to mount
--
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- -----------------------------------------------------------------------------
-- Warehouse – Large. The Large size lets COPY INTO complete in ~1-2 minutes
-- against ~1B rows. We size it down at the end of setup.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE WAREHOUSE tb_de_wh
  WAREHOUSE_SIZE = 'LARGE'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Warehouse for the remote-dev quickstart (bulk load).';

USE WAREHOUSE tb_de_wh;

-- -----------------------------------------------------------------------------
-- Database + schemas
-- -----------------------------------------------------------------------------
CREATE OR REPLACE DATABASE tb_101 COMMENT = 'Tasty Bytes database';

CREATE OR REPLACE SCHEMA tb_101.raw_pos       COMMENT = 'Raw point-of-sale tables';
CREATE OR REPLACE SCHEMA tb_101.raw_customer  COMMENT = 'Raw customer tables';
CREATE OR REPLACE SCHEMA tb_101.harmonized    COMMENT = 'Harmonized views';
CREATE OR REPLACE SCHEMA tb_101.analytics     COMMENT = 'Analytics views';
CREATE OR REPLACE SCHEMA tb_101.ml            COMMENT = 'ML feature tables + model registry namespace';
CREATE OR REPLACE SCHEMA tb_101.public;

-- -----------------------------------------------------------------------------
-- File format + external stage against the public Tasty Bytes S3 bucket
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FILE FORMAT tb_101.public.csv_ff
  TYPE = 'CSV';

CREATE OR REPLACE STAGE tb_101.public.s3load
  URL = 's3://sfquickstarts/frostbyte_tastybytes/'
  FILE_FORMAT = tb_101.public.csv_ff
  COMMENT = 'Public S3 stage – Tasty Bytes source data';

-- -----------------------------------------------------------------------------
-- Raw tables
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE tb_101.raw_pos.country
(
    country_id NUMBER(18,0),
    country VARCHAR,
    iso_currency VARCHAR(3),
    iso_country VARCHAR(2),
    city_id NUMBER(19,0),
    city VARCHAR,
    city_population VARCHAR
);

CREATE OR REPLACE TABLE tb_101.raw_pos.franchise
(
    franchise_id NUMBER(38,0),
    first_name VARCHAR,
    last_name VARCHAR,
    city VARCHAR,
    country VARCHAR,
    e_mail VARCHAR,
    phone_number VARCHAR
);

CREATE OR REPLACE TABLE tb_101.raw_pos.location
(
    location_id NUMBER(19,0),
    placekey VARCHAR,
    location VARCHAR,
    city VARCHAR,
    region VARCHAR,
    iso_country_code VARCHAR,
    country VARCHAR
);

CREATE OR REPLACE TABLE tb_101.raw_pos.menu
(
    menu_id NUMBER(19,0),
    menu_type_id NUMBER(38,0),
    menu_type VARCHAR,
    truck_brand_name VARCHAR,
    menu_item_id NUMBER(38,0),
    menu_item_name VARCHAR,
    item_category VARCHAR,
    item_subcategory VARCHAR,
    cost_of_goods_usd NUMBER(38,4),
    sale_price_usd NUMBER(38,4),
    menu_item_health_metrics_obj VARIANT
);

CREATE OR REPLACE TABLE tb_101.raw_pos.truck
(
    truck_id NUMBER(38,0),
    menu_type_id NUMBER(38,0),
    primary_city VARCHAR,
    region VARCHAR,
    iso_region VARCHAR,
    country VARCHAR,
    iso_country_code VARCHAR,
    franchise_flag NUMBER(38,0),
    year NUMBER(38,0),
    make VARCHAR,
    model VARCHAR,
    ev_flag NUMBER(38,0),
    franchise_id NUMBER(38,0),
    truck_opening_date DATE
);

CREATE OR REPLACE TABLE tb_101.raw_pos.order_header
(
    order_id NUMBER(38,0),
    truck_id NUMBER(38,0),
    location_id FLOAT,
    customer_id NUMBER(38,0),
    discount_id VARCHAR,
    shift_id NUMBER(38,0),
    shift_start_time TIME(9),
    shift_end_time TIME(9),
    order_channel VARCHAR,
    order_ts TIMESTAMP_NTZ(9),
    served_ts VARCHAR,
    order_currency VARCHAR(3),
    order_amount NUMBER(38,4),
    order_tax_amount VARCHAR,
    order_discount_amount VARCHAR,
    order_total NUMBER(38,4)
);

CREATE OR REPLACE TABLE tb_101.raw_pos.order_detail
(
    order_detail_id NUMBER(38,0),
    order_id NUMBER(38,0),
    menu_item_id NUMBER(38,0),
    discount_id VARCHAR,
    line_number NUMBER(38,0),
    quantity NUMBER(5,0),
    unit_price NUMBER(38,4),
    price NUMBER(38,4),
    order_item_discount_amount VARCHAR
);

CREATE OR REPLACE TABLE tb_101.raw_customer.customer_loyalty
(
    customer_id NUMBER(38,0),
    first_name VARCHAR,
    last_name VARCHAR,
    city VARCHAR,
    country VARCHAR,
    postal_code VARCHAR,
    preferred_language VARCHAR,
    gender VARCHAR,
    favourite_brand VARCHAR,
    marital_status VARCHAR,
    children_count VARCHAR,
    sign_up_date DATE,
    birthday_date DATE,
    e_mail VARCHAR,
    phone_number VARCHAR
);

-- -----------------------------------------------------------------------------
-- Harmonized + analytics views
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW tb_101.harmonized.orders_v AS
SELECT
    oh.order_id,
    oh.truck_id,
    oh.order_ts,
    od.order_detail_id,
    od.line_number,
    m.truck_brand_name,
    m.menu_type,
    t.primary_city,
    t.region,
    t.country,
    t.franchise_flag,
    t.franchise_id,
    f.first_name AS franchisee_first_name,
    f.last_name AS franchisee_last_name,
    l.location_id,
    l.city AS location_city,
    l.region AS location_region,
    cl.customer_id,
    cl.first_name,
    cl.last_name,
    od.menu_item_id,
    m.menu_item_name,
    od.quantity,
    od.unit_price,
    od.price,
    oh.order_amount,
    oh.order_total
FROM tb_101.raw_pos.order_detail od
JOIN tb_101.raw_pos.order_header oh ON od.order_id = oh.order_id
JOIN tb_101.raw_pos.truck t         ON oh.truck_id = t.truck_id
JOIN tb_101.raw_pos.menu m          ON od.menu_item_id = m.menu_item_id
JOIN tb_101.raw_pos.franchise f     ON t.franchise_id = f.franchise_id
JOIN tb_101.raw_pos.location l      ON oh.location_id = l.location_id
LEFT JOIN tb_101.raw_customer.customer_loyalty cl
    ON oh.customer_id = cl.customer_id;

CREATE OR REPLACE VIEW tb_101.analytics.orders_v AS
SELECT DATE(order_ts) AS date, * FROM tb_101.harmonized.orders_v;

-- -----------------------------------------------------------------------------
-- COPY INTO – all raw tables
-- Order matters only for readability; each table is independent.
-- On a LARGE warehouse this completes in ~1-2 minutes total.
-- -----------------------------------------------------------------------------
COPY INTO tb_101.raw_pos.country       FROM @tb_101.public.s3load/raw_pos/country/;
COPY INTO tb_101.raw_pos.franchise     FROM @tb_101.public.s3load/raw_pos/franchise/;
COPY INTO tb_101.raw_pos.location      FROM @tb_101.public.s3load/raw_pos/location/;
COPY INTO tb_101.raw_pos.menu          FROM @tb_101.public.s3load/raw_pos/menu/;
COPY INTO tb_101.raw_pos.truck         FROM @tb_101.public.s3load/raw_pos/truck/;
COPY INTO tb_101.raw_customer.customer_loyalty
                                       FROM @tb_101.public.s3load/raw_customer/customer_loyalty/;
COPY INTO tb_101.raw_pos.order_header  FROM @tb_101.public.s3load/raw_pos/order_header/;
COPY INTO tb_101.raw_pos.order_detail  FROM @tb_101.public.s3load/raw_pos/order_detail/;

-- -----------------------------------------------------------------------------
-- Compute pool for the remote development notebook service.
-- CPU_X64_S is enough for the training workload used in this guide.
-- -----------------------------------------------------------------------------
CREATE COMPUTE POOL IF NOT EXISTS tb_remote_dev_pool
  MIN_NODES = 1
  MAX_NODES = 1
  INSTANCE_FAMILY = CPU_X64_S
  AUTO_RESUME = TRUE
  AUTO_SUSPEND_SECS = 3600
  COMMENT = 'Compute pool for the remote-dev quickstart notebook service.';

-- Note: NOTEBOOK is allowed by default. ALLOWED_SPCS_WORKLOAD_TYPES is an
-- account-level parameter (default 'ALL', which includes NOTEBOOK), not a
-- compute-pool property. No pool-level configuration is required here.

-- -----------------------------------------------------------------------------
-- External Access Integration – outbound to GitHub + PyPI from the remote env.
-- The Tasty Bytes S3 bucket does NOT need to be in this EAI; the stage is
-- accessed by Snowflake compute (COPY INTO), not by the notebook container.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE NETWORK RULE tb_101.public.egress_github_pypi
  MODE = EGRESS
  TYPE = HOST_PORT
  VALUE_LIST = (
    'github.com:443',
    'api.github.com:443',
    'codeload.github.com:443',
    'pypi.org:443',
    'files.pythonhosted.org:443'
  );

CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION tb_remote_dev_eai
  ALLOWED_NETWORK_RULES = (tb_101.public.egress_github_pypi)
  ENABLED = TRUE
  COMMENT = 'Outbound access for the remote-dev notebook service.';

-- -----------------------------------------------------------------------------
-- Marketplace: acquire the Pelmorex Weather Source: Frostbyte share
-- programmatically. Pinning a stable DB name (frostbyte_weathersource) keeps
-- the joins in the notebook portable across accounts.
-- Requires the caller to be able to import shares (ACCOUNTADMIN or delegated
-- IMPORT SHARE privilege).
-- -----------------------------------------------------------------------------
CALL SYSTEM$REQUEST_LISTING_AND_WAIT('GZSOZ1LLEL');
CALL SYSTEM$ACCEPT_LEGAL_TERMS('DATA_EXCHANGE_LISTING', 'GZSOZ1LLEL');
CREATE DATABASE IF NOT EXISTS frostbyte_weathersource FROM LISTING 'GZSOZ1LLEL';

-- -----------------------------------------------------------------------------
-- Snowflake Workspace – the remote environment mounts this so you can edit
-- files that also appear in Snowsight Workspaces.
-- -----------------------------------------------------------------------------
CREATE WORKSPACE IF NOT EXISTS tb_101.public.tb_forecast_ws
  COMMENT = 'Workspace mounted into the remote-dev environment.';

-- -----------------------------------------------------------------------------
-- Confirm the account parameter is enabled (default is TRUE).
-- If your account admin has disabled it, ask them to run:
--   ALTER ACCOUNT SET ENABLE_NOTEBOOK_SERVICE_REMOTE_VS_CODE_ACCESS = TRUE;
-- -----------------------------------------------------------------------------
SHOW PARAMETERS LIKE 'ENABLE_NOTEBOOK_SERVICE_REMOTE_VS_CODE_ACCESS' IN ACCOUNT;

-- -----------------------------------------------------------------------------
-- Size the warehouse back down now that the bulk load is done.
-- -----------------------------------------------------------------------------
ALTER WAREHOUSE tb_de_wh SET WAREHOUSE_SIZE = 'XSMALL';

SELECT 'Setup complete.' AS status;
