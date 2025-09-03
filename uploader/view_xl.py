import streamlit as st
import pandas as pd
import duckdb
st.title("Site Evaluation")
st.markdown("LocalEnergyModel v5.1")

@st.cache_data
def load_data(path: str):
    data = pd.read_excel(path)
    return data

uploaded_file = st.file_uploader("Upload an Excel file", type=["xlsx"])

if uploaded_file is None:
    st.info("Please upload an Excel file to proceed.")
    st.stop()

df = load_data(uploaded_file)
st.dataframe(df)


