-- =====================================================================
--  CORTEX ANALYST LIVE DEMO  |  STEP 5: CLEANUP (run after the demo)
-- =====================================================================
USE ROLE ACCOUNTADMIN;
DROP DATABASE IF EXISTS CORTEX_DEMO_DB;      -- tables, semantic view, Streamlit app
DROP WAREHOUSE IF EXISTS CORTEX_DEMO_WH;
DROP ROLE IF EXISTS CORTEX_DEMO_ROLE;
