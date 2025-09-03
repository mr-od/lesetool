import streamlit as st
import psycopg2

# Database connection parameters
#DB_HOST = '103.251.164.211'
#DB_PORT = '5432'
#DB_NAME = 'ecologic_1'
#DB_USER = 'casaos'
#DB_PASSWORD = 'casaos'

DB_HOST = 'postgres'
DB_PORT = '5432'
DB_NAME = 'directus'
DB_USER = 'directus'
DB_PASSWORD = 'directus'

@st.cache_resource
def get_connection():
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD
    )

def fetch_query(query):
    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.execute(query)
        rows = cur.fetchall()
        return rows
    except Exception as e:
        conn.rollback()  # Reset the connection
        st.error(f"Database error: {e}")
        return []
    finally:
        cur.close()

def fetch_regions():
    return fetch_query("SELECT * FROM regions LIMIT 10;")

def fetch_spotprice():
    return fetch_query("SELECT * FROM spot_prices LIMIT 500;")

def fetch_batteries():
    return fetch_query("SELECT * FROM batteries LIMIT 100;")

def fetch_battery_degradation():
    return fetch_query("SELECT * FROM battery_degradation LIMIT 100;")

st.title("View Local Energy Data")

if st.button("Load Regions"):
    data = fetch_regions()
    st.dataframe(data)

if st.button("Load SpotPrice"):
    spot_price = fetch_spotprice()
    st.dataframe(spot_price)

if st.button("Load Batteries"):
    batteries = fetch_batteries()
    st.dataframe(batteries)

if st.button("Load Battery Degradation"):
    battery_degradation = fetch_battery_degradation()
    st.dataframe(battery_degradation)