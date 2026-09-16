-- =============================================================================
-- Remote Development for the Snowflake VS Code Extension – Cleanup
--
-- Drops everything setup.sql created, plus the ML feature table and any
-- registered model. Run this after you're done with the guide.
-- =============================================================================

USE ROLE ACCOUNTADMIN;

DROP DATABASE IF EXISTS tb_101;

-- Compute pool and external access integration.
DROP COMPUTE POOL IF EXISTS tb_remote_dev_pool;
DROP EXTERNAL ACCESS INTEGRATION IF EXISTS tb_remote_dev_eai;

-- Warehouse.
DROP WAREHOUSE IF EXISTS tb_de_wh;

-- Marketplace share acquired programmatically in setup.sql.
DROP DATABASE IF EXISTS frostbyte_weathersource;

SELECT 'Cleanup complete.' AS note;
