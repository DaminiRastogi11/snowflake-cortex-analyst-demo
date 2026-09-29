"""
CORTEX ANALYST LIVE DEMO | STEP 4: "Ask Snowbird" chat app
Runs in Streamlit in Snowflake (warehouse runtime).

Flow:  question -> Cortex Analyst REST API (with our semantic view)
                -> AI returns an explanation + SQL
                -> we run that SQL on our own warehouse
                -> show table + chart
"""
import json
import numbers

import pandas as pd
import streamlit as st
import _snowflake  # available in Streamlit in Snowflake (warehouse runtime)
from snowflake.snowpark.context import get_active_session

SEMANTIC_VIEW = "CORTEX_DEMO_DB.RETAIL.SNOWBIRD_SALES_SV"
MESSAGE_ENDPOINT = "/api/v2/cortex/analyst/message"
FEEDBACK_ENDPOINT = "/api/v2/cortex/analyst/feedback"
TIMEOUT_MS = 50_000

SAMPLE_QUESTIONS = [
    "What questions can I ask?",
    "What was our total revenue last year?",
    "Show me monthly revenue for the last 12 months",
    "Which products have the highest return rate?",
    "How has the share of online orders changed by quarter?",
    "Who are our top 10 customers by revenue?",
]

session = get_active_session()


# ---------------------------------------------------------------- API calls
def call_analyst(messages):
    """Send the full conversation to Cortex Analyst (enables follow-ups)."""
    body = {"messages": messages, "semantic_view": SEMANTIC_VIEW}
    resp = _snowflake.send_snow_api_request(
        "POST", MESSAGE_ENDPOINT, {}, {}, body, None, TIMEOUT_MS
    )
    parsed = json.loads(resp["content"])
    if resp["status"] < 400:
        return parsed, None
    return None, (
        f"Error {resp['status']}: {parsed.get('message', parsed)} "
        f"(request_id: {parsed.get('request_id', 'n/a')})"
    )


def send_feedback(request_id, positive):
    body = {"request_id": request_id, "positive": positive}
    resp = _snowflake.send_snow_api_request(
        "POST", FEEDBACK_ENDPOINT, {}, {}, body, None, TIMEOUT_MS
    )
    return resp["status"] < 400


# ---------------------------------------------------------------- helpers
def run_sql(sql):
    try:
        df = session.sql(sql).to_pandas()
        for col in df.columns:  # Snowflake NUMBERs can arrive as Decimal objects
            if df[col].dtype == object:
                converted = pd.to_numeric(df[col], errors="coerce")
                if converted.notna().sum() == df[col].notna().sum():
                    df[col] = converted
        return df, None
    except Exception as exc:  # show the error instead of crashing the demo
        return None, str(exc)


def show_result(df):
    if df.empty:
        st.info("The query ran but returned no rows.")
        return
    if df.shape == (1, 1):  # single number -> big metric card
        value = df.iloc[0, 0]
        shown = f"{value:,}" if isinstance(value, numbers.Number) else str(value)
        st.metric(df.columns[0].replace("_", " ").title(), shown)
        return
    table_tab, chart_tab = st.tabs(["Table", "Chart"])
    table_tab.dataframe(df, use_container_width=True)
    with chart_tab:
        x = df.columns[0]
        numeric = [c for c in df.columns[1:] if pd.api.types.is_numeric_dtype(df[c])]
        if not numeric or len(df) < 2:
            st.caption("No chartable numeric columns in this result.")
            return
        chart_df = df.copy()
        is_time = any(k in x.upper() for k in ("DATE", "MONTH", "QUARTER", "YEAR", "WEEK", "DAY"))
        if is_time:
            try:
                chart_df[x] = pd.to_datetime(chart_df[x].astype(str))
            except Exception:
                is_time = False
        chart_df = chart_df.set_index(x)[numeric[:1]]
        if is_time:
            st.line_chart(chart_df)
        else:
            st.bar_chart(chart_df)


def ask(question):
    st.session_state.messages.append(
        {"role": "user", "content": [{"type": "text", "text": question}]}
    )
    with st.spinner("Cortex Analyst is thinking..."):
        response, error = call_analyst(st.session_state.messages)
    if error:
        st.session_state.messages.pop()  # keep history valid for follow-ups
        st.session_state.error = error
        return
    st.session_state.messages.append(
        {"role": "analyst", "content": response["message"]["content"]}
    )
    idx = len(st.session_state.messages) - 1
    st.session_state.meta[idx] = {
        "request_id": response.get("request_id"),
        "warnings": response.get("warnings", []),
    }


def render_analyst(idx, content):
    meta = st.session_state.meta.get(idx, {})
    for block_no, block in enumerate(content):
        kind = block.get("type")
        if kind == "text":
            st.markdown(block["text"])
        elif kind == "suggestions":
            st.markdown("**Try one of these:**")
            for s_no, suggestion in enumerate(block["suggestions"]):
                if st.button(suggestion, key=f"sugg_{idx}_{block_no}_{s_no}"):
                    st.session_state.pending = suggestion
                    st.rerun()
        elif kind == "sql":
            sql = block["statement"]
            verified = (block.get("confidence") or {}).get("verified_query_used")
            if verified:
                st.success(f"✅ Answer based on a verified query: *{verified.get('question')}*")
            with st.expander("Show the SQL Cortex Analyst wrote", expanded=False):
                st.code(sql, language="sql")
            if idx not in st.session_state.results:
                st.session_state.results[idx] = run_sql(sql)
            df, err = st.session_state.results[idx]
            if err:
                st.error(f"SQL failed: {err}")
            else:
                show_result(df)
    for w in meta.get("warnings", []):
        st.caption(f"⚠️ {w.get('message')}")
    if meta.get("request_id"):
        up, down, _ = st.columns([1, 1, 10])
        if up.button("👍", key=f"up_{idx}"):
            send_feedback(meta["request_id"], True) and st.toast("Thanks for the feedback!")
        if down.button("👎", key=f"down_{idx}"):
            send_feedback(meta["request_id"], False) and st.toast("Feedback sent to the data team.")


# ---------------------------------------------------------------- UI
for key, default in {"messages": [], "results": {}, "meta": {}, "error": None, "pending": None}.items():
    st.session_state.setdefault(key, default)

st.title("🏔️ Ask Snowbird")
st.caption("Ask questions about Snowbird Outfitters sales in plain English — powered by Snowflake Cortex Analyst.")

with st.sidebar:
    st.subheader("Try asking")
    for q in SAMPLE_QUESTIONS:
        if st.button(q, key=f"sample_{q}", use_container_width=True):
            st.session_state.pending = q
    st.divider()
    st.caption(f"Semantic view:\n`{SEMANTIC_VIEW}`")
    if st.button("🔄 New conversation", use_container_width=True):
        for key in ("messages", "results", "meta"):
            st.session_state[key] = [] if key == "messages" else {}
        st.session_state.error = None
        st.rerun()

# Ask any pending question (from chat box, sidebar, or a suggestion button)
typed = st.chat_input("e.g. What was revenue by region last quarter?")
question = typed or st.session_state.pending
st.session_state.pending = None
if question:
    st.session_state.error = None
    ask(question)

for idx, msg in enumerate(st.session_state.messages):
    if msg["role"] == "user":
        with st.chat_message("user"):
            st.markdown(msg["content"][0]["text"])
    else:
        with st.chat_message("assistant", avatar="❄️"):
            render_analyst(idx, msg["content"])

if st.session_state.error:
    st.error(st.session_state.error)
