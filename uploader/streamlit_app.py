import streamlit as st
import pandas as pd
# import duckdb

from upload_csv import render_csv_uploader

# from upload_csv import render_csv_uploader
st.title("Site Evaluation")
st.markdown("LocalEnergyModel v5.1")

render_csv_uploader()



