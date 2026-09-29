-- =====================================================================
--  CORTEX ANALYST LIVE DEMO  |  STEP 1: ENVIRONMENT + SAMPLE DATA
--  Fictional company: "Snowbird Outfitters" (outdoor-gear retailer)
--
--  Run this whole script once in a Snowsight SQL worksheet.
--  Needs ACCOUNTADMIN (or a role that can create roles & warehouses).
--  Runtime: well under a minute on an XS warehouse.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Admin bits: demo role, warehouse, Cortex access
-- ---------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS CORTEX_DEMO_ROLE;

-- Lets this role call Cortex Analyst (CORTEX_ANALYST_USER also works
-- if you want to allow ONLY Cortex Analyst and nothing else in Cortex)
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE CORTEX_DEMO_ROLE;

GRANT CREATE DATABASE ON ACCOUNT TO ROLE CORTEX_DEMO_ROLE;

CREATE WAREHOUSE IF NOT EXISTS CORTEX_DEMO_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Warehouse for the Cortex Analyst demo';
GRANT USAGE, OPERATE ON WAREHOUSE CORTEX_DEMO_WH TO ROLE CORTEX_DEMO_ROLE;

SET my_user = CURRENT_USER();
GRANT ROLE CORTEX_DEMO_ROLE TO USER IDENTIFIER($my_user);

-- ONLY if your account is in a region where Cortex Analyst is not
-- natively available (see docs), uncomment this line:
-- ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'AWS_US';

-- ---------------------------------------------------------------------
-- 2. Everything below is owned by the demo role
-- ---------------------------------------------------------------------
USE ROLE CORTEX_DEMO_ROLE;
USE WAREHOUSE CORTEX_DEMO_WH;

CREATE DATABASE IF NOT EXISTS CORTEX_DEMO_DB;
CREATE SCHEMA IF NOT EXISTS CORTEX_DEMO_DB.RETAIL;
USE SCHEMA CORTEX_DEMO_DB.RETAIL;

-- ---------------------------------------------------------------------
-- 3. PRODUCTS (20 fixed rows)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE PRODUCTS (
  PRODUCT_ID    NUMBER        NOT NULL PRIMARY KEY,
  PRODUCT_NAME  VARCHAR       NOT NULL,
  CATEGORY      VARCHAR       NOT NULL,
  UNIT_COST     NUMBER(10,2)  NOT NULL,
  LIST_PRICE    NUMBER(10,2)  NOT NULL
) COMMENT = 'Product catalog for Snowbird Outfitters';

INSERT INTO PRODUCTS VALUES
  ( 1, 'Summit Pro Tent',            'Camping',     210, 449),
  ( 2, 'Trailhead 2P Tent',          'Camping',      95, 219),
  ( 3, 'Glacier Sleeping Bag',       'Camping',      60, 149),
  ( 4, 'Ember Camp Stove',           'Camping',      28,  69),
  ( 5, 'Basecamp Lantern',           'Camping',      12,  34),
  ( 6, 'Ridgeline Hiking Boots',     'Footwear',     70, 179),
  ( 7, 'Canyon Trail Runners',       'Footwear',     48, 129),
  ( 8, 'Riverbed Water Sandals',     'Footwear',     18,  59),
  ( 9, 'Alpine Wool Socks 3-Pack',   'Footwear',      6,  24),
  (10, 'Stormshell Rain Jacket',     'Apparel',      65, 199),
  (11, 'Polar Fleece Pullover',      'Apparel',      22,  79),
  (12, 'Trekker Convertible Pants',  'Apparel',      20,  69),
  (13, 'Merino Base Layer',          'Apparel',      25,  89),
  (14, 'Sun Guard Hat',              'Apparel',       7,  29),
  (15, 'Voyager 45L Backpack',       'Packs',        55, 169),
  (16, 'Daytripper 22L Pack',        'Packs',        24,  79),
  (17, 'Hydra 2L Reservoir',         'Packs',         9,  32),
  (18, 'Carbon Trekking Poles',      'Accessories',  30,  99),
  (19, 'Nightfall Headlamp',         'Accessories',  11,  39),
  (20, 'Compass and Map Kit',        'Accessories',   8,  27);

-- ---------------------------------------------------------------------
-- 4. CUSTOMERS (500 rows, unique names, every 5th one is a Business)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE CUSTOMERS (
  CUSTOMER_ID    NUMBER   NOT NULL PRIMARY KEY,
  CUSTOMER_NAME  VARCHAR  NOT NULL,
  SEGMENT        VARCHAR  NOT NULL,
  REGION         VARCHAR  NOT NULL,
  SIGNUP_DATE    DATE     NOT NULL
) COMMENT = 'Customers of Snowbird Outfitters';

INSERT INTO CUSTOMERS
WITH base AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS id,
         UNIFORM(1, 100, RANDOM())           AS r_region,
         UNIFORM(0, 1000, RANDOM())          AS r_days
  FROM TABLE(GENERATOR(ROWCOUNT => 500))
),
names AS (
  SELECT
    ARRAY_CONSTRUCT('Ava','Liam','Maya','Noah','Zoe','Ethan','Chloe','Lucas','Priya','Mateo',
                    'Grace','Owen','Sofia','Arjun','Leah','Diego','Hannah','Ryan','Mei','Caleb') AS firsts,
    ARRAY_CONSTRUCT('Carter','Nguyen','Patel','Brooks','Rivera','Kim','Walsh','Foster','Hayes','Ortiz',
                    'Bennett','Shah','Coleman','Reyes','Morgan','Ellis','Chen','Porter','Diaz','Hughes',
                    'Grant','Singh','Lawson','Ward','Fisher') AS lasts,
    ARRAY_CONSTRUCT('Outdoor Club','Scout Troop','Adventure Co.','Guide Service') AS orgs
)
SELECT
  b.id,
  IFF(MOD(b.id, 5) = 0,
      -- Business customers: unique "<Surname> <Org>" names
      n.lasts[MOD(FLOOR(b.id / 5), 25)::INT]::VARCHAR || ' ' || n.orgs[MOD(FLOOR(b.id / 125), 4)::INT]::VARCHAR,
      -- Consumers: unique "<First> <Last>" names
      n.firsts[MOD(b.id, 20)::INT]::VARCHAR || ' ' || n.lasts[MOD(FLOOR(b.id / 20), 25)::INT]::VARCHAR),
  IFF(MOD(b.id, 5) = 0, 'Business', 'Consumer'),
  CASE WHEN b.r_region <= 30 THEN 'West'
       WHEN b.r_region <= 55 THEN 'Northeast'
       WHEN b.r_region <= 78 THEN 'South'
       ELSE 'Midwest' END,
  DATEADD(day, -b.r_days, CURRENT_DATE())
FROM base b CROSS JOIN names n;

-- ---------------------------------------------------------------------
-- 5. SALES (one row per order line, ~50k rows, last ~30 months)
--
--  Stories baked into the data (great "aha" moments in the demo):
--    * Revenue peaks every Nov/Dec (holiday season)
--    * November has heavy Black-Friday discounts -> margin dips
--    * "Summit Pro Tent" is returned ~18% of the time (others ~4%)
--    * Online share of orders grows steadily over time
--    * Business customers buy in much larger quantities
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE SALES (
  SALE_LINE_ID  NUMBER        NOT NULL PRIMARY KEY,
  ORDER_ID      NUMBER        NOT NULL,
  LINE_NO       NUMBER        NOT NULL,
  ORDER_DATE    DATE          NOT NULL,
  CUSTOMER_ID   NUMBER        NOT NULL REFERENCES CUSTOMERS (CUSTOMER_ID),
  PRODUCT_ID    NUMBER        NOT NULL REFERENCES PRODUCTS (PRODUCT_ID),
  CHANNEL       VARCHAR       NOT NULL,
  QUANTITY      NUMBER        NOT NULL,
  UNIT_PRICE    NUMBER(10,2)  NOT NULL,
  DISCOUNT_PCT  NUMBER(4,2)   NOT NULL,
  UNIT_COST     NUMBER(10,2)  NOT NULL,
  IS_RETURNED   BOOLEAN       NOT NULL
) COMMENT = 'Sales order lines for Snowbird Outfitters';

INSERT INTO SALES
WITH orders AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS order_id,
         UNIFORM(1, 500, RANDOM())           AS customer_id,
         UNIFORM(0, 899, RANDOM())           AS days_ago,
         UNIFORM(1, 100, RANDOM())           AS r_channel,
         UNIFORM(1, 3, RANDOM())             AS n_lines
  FROM TABLE(GENERATOR(ROWCOUNT => 25000))
),
line_numbers AS (
  SELECT 1 AS line_no UNION ALL SELECT 2 UNION ALL SELECT 3
),
exploded AS (
  SELECT o.order_id, o.customer_id, o.days_ago, o.r_channel, l.line_no,
         DATEADD(day, -(o.days_ago + 1), CURRENT_DATE()) AS order_date,
         UNIFORM(1, 20, RANDOM())   AS product_id,
         UNIFORM(1, 100, RANDOM())  AS r_qty,
         UNIFORM(1, 100, RANDOM())  AS r_disc,
         UNIFORM(1, 1000, RANDOM()) AS r_ret
  FROM orders o
  JOIN line_numbers l ON l.line_no <= o.n_lines
)
SELECT
  ROW_NUMBER() OVER (ORDER BY e.order_id, e.line_no)              AS sale_line_id,
  e.order_id,
  e.line_no,
  e.order_date,
  e.customer_id,
  e.product_id,
  -- online share climbs from ~45% (oldest) to ~75% (most recent)
  IFF(e.r_channel <= 45 + (900 - e.days_ago) / 30, 'Online', 'In-Store') AS channel,
  (CASE WHEN e.r_qty <= 60 THEN 1 WHEN e.r_qty <= 85 THEN 2
        WHEN e.r_qty <= 95 THEN 3 ELSE 5 END)
    * IFF(c.segment = 'Business', 4, 1)
    * IFF(MONTH(e.order_date) IN (11, 12), 2, 1)                  AS quantity,
  p.list_price                                                     AS unit_price,
  CASE WHEN MONTH(e.order_date) = 11 AND e.r_disc <= 60 THEN 0.20
       WHEN e.r_disc <= 15 THEN 0.10
       WHEN e.r_disc <= 30 THEN 0.05
       ELSE 0 END                                                  AS discount_pct,
  p.unit_cost,
  IFF(e.product_id = 1, e.r_ret <= 180, e.r_ret <= 40)             AS is_returned
FROM exploded e
JOIN PRODUCTS  p ON p.product_id  = e.product_id
JOIN CUSTOMERS c ON c.customer_id = e.customer_id;

-- ---------------------------------------------------------------------
-- 6. Column comments (these also help Snowsight's Semantic View Autopilot)
-- ---------------------------------------------------------------------
COMMENT ON COLUMN SALES.DISCOUNT_PCT IS 'Discount applied to the line as a fraction, e.g. 0.20 = 20% off';
COMMENT ON COLUMN SALES.IS_RETURNED  IS 'TRUE if the customer returned this line; returned lines earn no revenue';
COMMENT ON COLUMN SALES.CHANNEL      IS 'Where the order was placed: Online or In-Store';
COMMENT ON COLUMN SALES.UNIT_COST    IS 'Our cost per unit at the time of sale';
COMMENT ON COLUMN CUSTOMERS.SEGMENT  IS 'Consumer (individual shopper) or Business (clubs, troops, guide services)';

-- ---------------------------------------------------------------------
-- 7. Quick check: you should see 20 / 500 / roughly 50,000
-- ---------------------------------------------------------------------
SELECT 'PRODUCTS' AS table_name, COUNT(*) AS row_count FROM PRODUCTS
UNION ALL SELECT 'CUSTOMERS', COUNT(*) FROM CUSTOMERS
UNION ALL SELECT 'SALES', COUNT(*) FROM SALES;
