-- =====================================================================
--  CORTEX ANALYST LIVE DEMO  |  STEP 2: THE SEMANTIC VIEW
--
--  This is the "dictionary" Cortex Analyst reads. It tells the AI:
--    * which tables exist and how they join       (TABLES, RELATIONSHIPS)
--    * what the business words mean                (FACTS, DIMENSIONS, METRICS)
--    * other words people use for the same thing   (SYNONYMS)
--    * house rules for writing SQL                 (AI_SQL_GENERATION)
--
--  Key business rule we encode (good demo talking point):
--    "Revenue" = after discounts AND excluding returned items.
-- =====================================================================
USE ROLE CORTEX_DEMO_ROLE;
USE WAREHOUSE CORTEX_DEMO_WH;
USE SCHEMA CORTEX_DEMO_DB.RETAIL;

CREATE OR REPLACE SEMANTIC VIEW SNOWBIRD_SALES_SV

  TABLES (
    sales AS CORTEX_DEMO_DB.RETAIL.SALES
      PRIMARY KEY (sale_line_id)
      WITH SYNONYMS ('orders', 'transactions', 'order lines', 'purchases')
      COMMENT = 'One row per product line on a customer order. An order can have up to 3 lines.',
    customers AS CORTEX_DEMO_DB.RETAIL.CUSTOMERS
      PRIMARY KEY (customer_id)
      WITH SYNONYMS ('clients', 'buyers', 'accounts', 'shoppers')
      COMMENT = 'Snowbird Outfitters customers, both individual consumers and businesses.',
    products AS CORTEX_DEMO_DB.RETAIL.PRODUCTS
      PRIMARY KEY (product_id)
      WITH SYNONYMS ('items', 'SKUs', 'merchandise', 'gear')
      COMMENT = 'Product catalog with cost and list price.'
  )

  RELATIONSHIPS (
    sales_to_customers AS sales (customer_id) REFERENCES customers,
    sales_to_products  AS sales (product_id)  REFERENCES products
  )

  FACTS (
    sales.gross_amount AS quantity * unit_price
      COMMENT = 'List-price value of the line BEFORE discounts and returns. Not the same as revenue.',
    sales.net_revenue AS IFF(is_returned, 0, quantity * unit_price * (1 - discount_pct))
      COMMENT = 'Line revenue after discount; zero if the line was returned.',
    sales.line_cost AS IFF(is_returned, 0, quantity * unit_cost)
      COMMENT = 'Cost of goods for the line; zero if the line was returned.',
    sales.units AS quantity
      COMMENT = 'Number of units on the line.'
  )

  DIMENSIONS (
    sales.order_date AS order_date
      WITH SYNONYMS = ('purchase date', 'sale date', 'transaction date')
      COMMENT = 'Date the order was placed.',
    sales.order_month AS DATE_TRUNC('MONTH', order_date)
      COMMENT = 'First day of the month the order was placed. Use for monthly trends.',
    sales.order_quarter AS DATE_TRUNC('QUARTER', order_date)
      COMMENT = 'First day of the quarter the order was placed.',
    sales.order_year AS YEAR(order_date)
      COMMENT = 'Calendar year the order was placed.',
    sales.order_number AS order_id
      COMMENT = 'Order identifier. Several sales lines can share one order.',
    sales.sales_channel AS channel
      WITH SYNONYMS = ('channel', 'online or store', 'web vs store')
      COMMENT = 'Where the order was placed.'
      SAMPLE_VALUES ('Online', 'In-Store')
      IS_ENUM,
    sales.was_returned AS is_returned
      WITH SYNONYMS = ('returned', 'refunded')
      COMMENT = 'TRUE if the line was returned by the customer.',
    customers.customer_name AS customer_name
      WITH SYNONYMS = ('client name', 'buyer name', 'account name')
      COMMENT = 'Name of the customer (person or organisation).',
    customers.segment AS segment
      WITH SYNONYMS = ('customer type', 'B2B or B2C')
      COMMENT = 'Consumer = individual shopper; Business = clubs, scout troops, guide services.'
      SAMPLE_VALUES ('Consumer', 'Business')
      IS_ENUM,
    customers.region AS region
      WITH SYNONYMS = ('territory', 'area', 'geography')
      COMMENT = 'US sales region of the customer.'
      SAMPLE_VALUES ('West', 'Northeast', 'South', 'Midwest')
      IS_ENUM,
    customers.signup_date AS signup_date
      COMMENT = 'Date the customer created their account.',
    products.product_name AS product_name
      WITH SYNONYMS = ('item name', 'product', 'SKU name')
      COMMENT = 'Name of the product.',
    products.category AS category
      WITH SYNONYMS = ('product category', 'department', 'product line')
      COMMENT = 'Product category.'
      SAMPLE_VALUES ('Camping', 'Footwear', 'Apparel', 'Packs', 'Accessories')
      IS_ENUM
  )

  METRICS (
    sales.total_revenue AS SUM(sales.net_revenue)
      WITH SYNONYMS = ('revenue', 'sales', 'net sales', 'turnover', 'income')
      COMMENT = 'OFFICIAL revenue definition: after discounts, excluding returned lines.',
    sales.gross_profit AS SUM(sales.net_revenue - sales.line_cost)
      WITH SYNONYMS = ('profit', 'margin dollars')
      COMMENT = 'Revenue minus cost of goods, excluding returned lines.',
    sales.order_count AS COUNT(DISTINCT order_id)
      WITH SYNONYMS = ('number of orders', 'orders placed')
      COMMENT = 'Number of distinct orders.',
    sales.units_sold AS SUM(sales.units)
      WITH SYNONYMS = ('quantity sold', 'volume')
      COMMENT = 'Total units sold (including units later returned).',
    sales.return_rate AS AVG(IFF(is_returned, 1, 0))
      WITH SYNONYMS = ('returns rate', 'percent returned')
      COMMENT = 'Share of order lines that were returned, as a fraction between 0 and 1.',
    sales.average_discount AS AVG(discount_pct)
      COMMENT = 'Average discount per line, as a fraction between 0 and 1.',
    sales.buying_customers AS COUNT(DISTINCT customer_id)
      WITH SYNONYMS = ('active customers', 'purchasing customers')
      COMMENT = 'Number of distinct customers who placed at least one order in the period.',
    customers.customer_count AS COUNT(customer_id)
      WITH SYNONYMS = ('total customers', 'customer base')
      COMMENT = 'Number of customer accounts, whether or not they bought anything.',
    average_order_value AS DIV0(sales.total_revenue, sales.order_count)
      WITH SYNONYMS = ('AOV', 'average basket size', 'average order size')
      COMMENT = 'Revenue divided by number of orders.',
    gross_margin_pct AS DIV0(sales.gross_profit, sales.total_revenue)
      WITH SYNONYMS = ('margin', 'gross margin', 'profit margin')
      COMMENT = 'Gross profit as a fraction of revenue.'
  )

  COMMENT = 'Snowbird Outfitters sales analytics: orders, customers and products.'

  -- House rules for how Cortex Analyst writes SQL.
  -- (If your account rejects these two clauses, delete them; everything
  --  else still works and you can add instructions in the Snowsight UI.)
  AI_SQL_GENERATION 'When the user says revenue or sales, always use total_revenue (net of discounts, excluding returns), never gross_amount unless they explicitly ask for gross or list-price value. Round money to 2 decimals. Show rates and percentages multiplied by 100 and rounded to 1 decimal, with a column name ending in _PCT. "Last year" means the previous full calendar year; "this year" means year to date. For top-N questions sort descending and default to the top 10.'
  AI_QUESTION_CATEGORIZATION 'This data only covers sales, customers and products. If the user asks about employees, payroll, inventory or stock levels, marketing spend, or website traffic, explain politely that this data set does not contain that information and suggest a sales-related question instead.'
;

-- ---------------------------------------------------------------------
-- Verify it was created and inspect what the AI will "see"
-- ---------------------------------------------------------------------
SHOW SEMANTIC VIEWS;
SHOW SEMANTIC METRICS    IN SNOWBIRD_SALES_SV;
SHOW SEMANTIC DIMENSIONS IN SNOWBIRD_SALES_SV;

-- Query the semantic view directly with SQL (no AI involved).
-- Handy to show that the SAME governed definitions power BI tools too.
SELECT * FROM SEMANTIC_VIEW(
    SNOWBIRD_SALES_SV
    DIMENSIONS customers.region
    METRICS sales.total_revenue, sales.order_count, average_order_value
  )
ORDER BY total_revenue DESC;
