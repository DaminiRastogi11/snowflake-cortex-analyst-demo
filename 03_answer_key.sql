-- =====================================================================
--  CORTEX ANALYST LIVE DEMO  |  STEP 3: ANSWER KEY
--
--  Hand-written SQL for the demo questions. Run these during rehearsal,
--  write the numbers on a sticky note, and you'll know instantly on
--  stage whether Cortex Analyst got it right.
--  (Data is random per setup run, so re-check if you re-run step 1.)
-- =====================================================================
USE ROLE CORTEX_DEMO_ROLE;
USE WAREHOUSE CORTEX_DEMO_WH;
USE SCHEMA CORTEX_DEMO_DB.RETAIL;

-- Q1. "What was our total revenue last year?"
SELECT ROUND(SUM(IFF(is_returned, 0, quantity * unit_price * (1 - discount_pct))), 2) AS total_revenue
FROM SALES
WHERE YEAR(order_date) = YEAR(CURRENT_DATE()) - 1;

-- *** THE "WHY A SEMANTIC LAYER" MOMENT ***
-- A naive query (what a generic chatbot would write from raw columns)
-- ignores discounts and returns, and overstates revenue:
SELECT ROUND(SUM(quantity * unit_price), 2) AS naive_revenue_WRONG
FROM SALES
WHERE YEAR(order_date) = YEAR(CURRENT_DATE()) - 1;

-- Q2. "Show me monthly revenue for the last 12 months"  (expect Nov/Dec peak)
SELECT DATE_TRUNC('MONTH', order_date) AS order_month,
       ROUND(SUM(IFF(is_returned, 0, quantity * unit_price * (1 - discount_pct))), 2) AS total_revenue
FROM SALES
WHERE order_date >= DATEADD(month, -12, DATE_TRUNC('MONTH', CURRENT_DATE()))
GROUP BY 1 ORDER BY 1;

-- Q3. "Which region generated the most revenue this year?"
SELECT c.region,
       ROUND(SUM(IFF(s.is_returned, 0, s.quantity * s.unit_price * (1 - s.discount_pct))), 2) AS total_revenue
FROM SALES s JOIN CUSTOMERS c ON c.customer_id = s.customer_id
WHERE YEAR(s.order_date) = YEAR(CURRENT_DATE())
GROUP BY 1 ORDER BY 2 DESC;

-- Q4. "Which products have the highest return rate?"  (expect Summit Pro Tent ~18%)
SELECT p.product_name,
       ROUND(AVG(IFF(s.is_returned, 1, 0)) * 100, 1) AS return_rate_pct
FROM SALES s JOIN PRODUCTS p ON p.product_id = s.product_id
GROUP BY 1 ORDER BY 2 DESC LIMIT 5;

-- Q5. "What is gross margin by month?"  (expect a dip every November)
SELECT DATE_TRUNC('MONTH', order_date) AS order_month,
       ROUND(DIV0(SUM(IFF(is_returned, 0, quantity * unit_price * (1 - discount_pct) - quantity * unit_cost)),
                  SUM(IFF(is_returned, 0, quantity * unit_price * (1 - discount_pct)))) * 100, 1) AS gross_margin_pct
FROM SALES GROUP BY 1 ORDER BY 1;

-- Q6. "How has the share of online orders changed by quarter?"  (expect steady growth)
SELECT DATE_TRUNC('QUARTER', order_date) AS order_quarter,
       ROUND(COUNT(DISTINCT IFF(channel = 'Online', order_id, NULL)) / COUNT(DISTINCT order_id) * 100, 1) AS online_share_pct
FROM SALES GROUP BY 1 ORDER BY 1;

-- Q7. "Who are our top 10 customers by revenue?"  (expect Business accounts to dominate)
SELECT c.customer_name, c.segment,
       ROUND(SUM(IFF(s.is_returned, 0, s.quantity * s.unit_price * (1 - s.discount_pct))), 2) AS total_revenue
FROM SALES s JOIN CUSTOMERS c ON c.customer_id = s.customer_id
GROUP BY 1, 2 ORDER BY 3 DESC LIMIT 10;

-- Q8. "What's the average order value by segment?"
SELECT c.segment,
       ROUND(DIV0(SUM(IFF(s.is_returned, 0, s.quantity * s.unit_price * (1 - s.discount_pct))),
                  COUNT(DISTINCT s.order_id)), 2) AS average_order_value
FROM SALES s JOIN CUSTOMERS c ON c.customer_id = s.customer_id
GROUP BY 1 ORDER BY 2 DESC;

-- ---------------------------------------------------------------------
-- After the demo: see how many Cortex Analyst requests you made
-- (ACCOUNT_USAGE views can lag by a few hours; needs a role with access)
-- ---------------------------------------------------------------------
-- SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_ANALYST_USAGE_HISTORY
-- ORDER BY start_time DESC LIMIT 50;
