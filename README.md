# Ask Snowbird — Snowflake Cortex Analyst Demo

Ask questions about sales data in plain English and get answers you can check.

This repo builds a small, self-contained demo of **Snowflake Cortex Analyst**: a fictional outdoor-gear retailer called **Snowbird Outfitters**, a **semantic view** that defines what words like "revenue" mean, and a Streamlit chat app that sends your questions to Cortex Analyst and shows the answer, the SQL it wrote, and a chart.

Setup takes about **10 minutes** in a free Snowflake trial account. Everything is removed afterwards with one script.

> Snowbird Outfitters is made up. The data is randomly generated, but the Snowflake features are real.

---

## What's in the repo

| File | What it does |
|---|---|
| `01_setup_environment.sql` | Creates a role, a small warehouse, a database, and three tables (products, customers, ~50k sales lines) filled with generated data |
| `02_create_semantic_view.sql` | Creates the semantic view `SNOWBIRD_SALES_SV` — the "rulebook" Cortex Analyst reads |
| `03_answer_key.sql` | Hand-written SQL for the demo questions, so you can check every AI answer yourself |
| `04_streamlit_app.py` | The "Ask Snowbird" chat app (runs inside Snowflake) |
| `05_cleanup.sql` | Deletes everything the demo created |
| `docs/DEMO_GUIDE.md` | Presenter guide: run-of-show, talking points, Q&A, troubleshooting |

---

## Before you start

You need:

- A Snowflake account. A free 30-day trial works: **https://signup.snowflake.com**
  - Edition: **Enterprise**
  - Cloud/region: **AWS US West (Oregon)** or **AWS US East (N. Virginia)** are safe choices, since Cortex Analyst is available there
- The **ACCOUNTADMIN** role (you have it automatically in a new trial account)

You do **not** need to install anything on your computer. Everything runs in the Snowflake web UI (Snowsight) at **https://app.snowflake.com**.

---

## Setup (about 10 minutes)

### Step 1 — Create the data

1. Log in to Snowsight.
2. Go to **Projects → Workspaces** (or **Worksheets**) and create a new **SQL** file.
3. Paste in the contents of `01_setup_environment.sql`.
4. Click the dropdown next to **Run** and choose **Run All**.

When it finishes you'll have:

- Role `CORTEX_DEMO_ROLE`
- Warehouse `CORTEX_DEMO_WH` (extra-small, auto-suspends after 60 seconds)
- Database `CORTEX_DEMO_DB`, schema `RETAIL`, with tables `PRODUCTS`, `CUSTOMERS`, `SALES`

> **Region note:** if your account is in a region where Cortex Analyst isn't available, uncomment the `CORTEX_ENABLED_CROSS_REGION` line near the top of the script and run it again.

### Step 2 — Create the semantic view

1. Open a new SQL file.
2. Paste in `02_create_semantic_view.sql` and **Run All**.
3. Check it worked:

   ```sql
   SHOW SEMANTIC VIEWS IN SCHEMA CORTEX_DEMO_DB.RETAIL;
   ```

   You should see `SNOWBIRD_SALES_SV`.

> If you get an error mentioning `AI_SQL_GENERATION` or `AI_QUESTION_CATEGORIZATION`, delete those two clauses at the bottom of the script and run it again. They're optional extras.

### Step 3 — Run the answer key

1. Open a new SQL file, paste in `03_answer_key.sql`, and **Run All** (or run each query one at a time).
2. **Write down the numbers.** These are the correct answers. You'll compare the AI's answers against them.

The data is random each time you run Step 1, so your numbers will be different from anyone else's. Re-run this step if you ever re-run Step 1.

### Step 4 — Create the chat app

> ⚠️ **Important:** the app must run on the **warehouse (legacy) runtime**. The default "+ Streamlit" button creates a container-runtime app, which fails with `ModuleNotFoundError: No module named '_snowflake'`.

1. In Snowsight, go to **Projects → Streamlit**.
2. Click the **dropdown arrow** next to **+ Streamlit** and choose **Create on warehouse (legacy)**.
3. Fill in:
   - **App title:** `Ask Snowbird`
   - **Database:** `CORTEX_DEMO_DB`
   - **Schema:** `RETAIL` (not `PUBLIC`)
   - **Warehouse:** `CORTEX_DEMO_WH`
4. Make sure your role (top-left) is **`CORTEX_DEMO_ROLE`**.
5. Click **Create**. When the editor opens, delete all the sample code in `streamlit_app.py`.
6. Paste in the contents of `04_streamlit_app.py` and click **Run**.

You should see the "Ask Snowbird" chat screen.

### Step 5 — Ask questions

Try these, in order:

1. What was our total revenue last year?
2. Show me monthly revenue for the last 12 months
3. Which region generated the most revenue this year?
4. Which products have the highest return rate?
5. What is gross margin by month?
6. How has the share of online orders changed by quarter?
7. Who are our top 10 customers by revenue?

You can also ask follow-ups like *"now just the West"*. The app sends the whole conversation, so Cortex Analyst understands what "just" refers to.

**No-code option:** Snowsight also has a built-in playground at **AI & ML → Cortex Analyst**. Pick `CORTEX_DEMO_DB.RETAIL.SNOWBIRD_SALES_SV` and ask the same questions there.

---

## How to check an answer is right

1. Under the answer in the app, open the **SQL** expander. That's the query Cortex Analyst wrote.
2. Find the same question in `03_answer_key.sql`.
3. Compare the number from the app with the number from your answer key.

If they match, the AI got it right. You wrote the correct answer down in advance, so you're marking its homework.

---

## What to look for in the data

The generated data has five patterns built in, so there's always something to find:

| Pattern | Question that shows it |
|---|---|
| Revenue spikes every November and December | Monthly revenue |
| Margin dips every November (holiday discounts) | Gross margin by month |
| The **Summit Pro Tent** has a ~18% return rate (others ~4%) | Highest return rate |
| Online share of orders grows from ~45% to ~75% | Online share by quarter |
| Business customers buy about 4× more per order | Top customers / order value by segment |

**Dataset at a glance:** 20 products in 5 categories (Camping, Footwear, Apparel, Packs, Accessories) · 500 customers (Consumer and Business) · 4 regions (West, Northeast, South, Midwest) · 2 channels (Online, In-Store) · about 30 months of sales.

---

## The key idea: why a semantic view?

Ask a generic chatbot "what was our revenue?" and it will probably add up the sales amount column. But in this demo, **revenue means net of discounts, excluding returned orders**.

`03_answer_key.sql` includes a deliberately naive query labelled `naive_revenue_WRONG`. Run it next to the correct one and you'll see the gap. Both queries run fine. Only one of them follows the business rules.

The semantic view in `02_create_semantic_view.sql` writes those rules down once, so every answer Cortex Analyst gives uses the same definitions.

---

## Cost

- Cortex Analyst is billed **per successful message**, plus normal **warehouse** credits for running the SQL.
- On this data size, a full demo costs very little. The warehouse is extra-small and suspends itself after 60 seconds.
- Trial accounts **without a payment method** are limited to roughly **10 Cortex AI credits per day**. That's plenty for trying this out.
- To see your usage (can lag a few hours):

  ```sql
  SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_ANALYST_USAGE_HISTORY
  ORDER BY start_time DESC LIMIT 50;
  ```

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `ModuleNotFoundError: No module named '_snowflake'` | The app was created on the container runtime. Delete it and recreate it using **Create on warehouse (legacy)** (Step 4). |
| App can't find the semantic view | Check the app is in database `CORTEX_DEMO_DB`, schema `RETAIL`, and your role is `CORTEX_DEMO_ROLE`. |
| Error about `AI_SQL_GENERATION` / `AI_QUESTION_CATEGORIZATION` | Delete those two clauses from `02_create_semantic_view.sql` and re-run it. |
| "Cortex Analyst is not available" / region error | Uncomment the `CORTEX_ENABLED_CROSS_REGION` line in `01_setup_environment.sql` and run it as ACCOUNTADMIN. |
| Permission errors | Run Steps 1–2 as `ACCOUNTADMIN`. The setup grants `SNOWFLAKE.CORTEX_USER` to the demo role. |
| Answers differ from someone else's | Expected. The data is random per setup run. Compare against *your* answer key. |
| Answer looks wrong | Click 👎 in the app, check the SQL, and compare with the answer key. |

---

## Clean up

When you're done, open a new SQL file, paste in `05_cleanup.sql`, and **Run All**. It drops the database (including the tables, semantic view and app), the warehouse, and the role.

---

## Limitations worth knowing

- It only answers questions SQL can answer. It can tell you *what* happened, not *why*.
- Very long conversations can drift. Start a new chat if answers get strange.
- You can't choose which AI model it uses. Snowflake manages that.
- It can't refer back to the rows from a previous answer, only to the earlier questions.
- Snowflake recommends **Cortex Agents** as the next step if you want to combine structured data with documents.

---

## Learn more

- Cortex Analyst: https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst
- Semantic views: https://docs.snowflake.com/en/user-guide/views-semantic/overview
- Presenter guide for running this live: [`docs/DEMO_GUIDE.md`](docs/DEMO_GUIDE.md)

---

## License

MIT. See [`LICENSE`](LICENSE). This is a demo, not production code. Review everything before using it in a real account.
