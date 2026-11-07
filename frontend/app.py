import os

import pandas as pd
import requests
import streamlit as st

API_BASE_URL = os.getenv("API_BASE_URL", "http://localhost:8000")

st.set_page_config(page_title="Retail Analytics Agent", page_icon="📊", layout="wide")
st.title("📊 Retail Analytics Agent")
st.caption("Ask a question in plain English. The app shows the generated, read-only SQL and results.")

with st.sidebar:
    st.subheader("Try one")
    st.markdown("- Top customers by completed-order revenue\n- Monthly revenue trend\n- Best-selling product categories")
    st.caption("Safety: SELECT-only, parsed validation, hard result limit, read-only DB transaction, and statement timeout.")

if "messages" not in st.session_state:
    st.session_state.messages = []

for message in st.session_state.messages:
    with st.chat_message(message["role"]):
        st.markdown(message["content"])
        if message.get("result"):
            st.code(message["result"]["sql"], language="sql")
            st.dataframe(pd.DataFrame(message["result"]["rows"]), use_container_width=True, hide_index=True)
            st.caption(f"{message['result']['explanation']} · {message['result']['attempts']} attempt(s)")

question = st.chat_input("e.g. Which cities generated the most completed-order revenue?")
if question:
    st.session_state.messages.append({"role": "user", "content": question})
    with st.chat_message("user"):
        st.markdown(question)
    with st.chat_message("assistant"):
        with st.spinner("Generating and safely running SQL…"):
            try:
                response = requests.post(f"{API_BASE_URL}/query", json={"question": question}, timeout=45)
                response.raise_for_status()
                result = response.json()
                st.code(result["sql"], language="sql")
                st.dataframe(pd.DataFrame(result["rows"]), use_container_width=True, hide_index=True)
                st.caption(f"{result['explanation']} · {result['attempts']} attempt(s)")
                st.session_state.messages.append({"role": "assistant", "content": "Query completed.", "result": result})
            except requests.RequestException as exc:
                message = f"I couldn't complete that query: {exc}"
                st.error(message)
                st.session_state.messages.append({"role": "assistant", "content": message})

