import pandas as pd
from io import StringIO
import streamlit as st
import psycopg2
import io

# # Database connection parameters
DB_HOST = 'postgres'
DB_PORT = '5432'
DB_NAME = 'directus'
DB_USER = 'directus'
DB_PASSWORD = 'directus'


# --- Database connection ---
def get_connection():
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD
    )

# --- Get table columns and detect serial/defaults ---
def get_table_columns(table_name, schema='public'):
    query = """
    SELECT column_name, column_default
    FROM information_schema.columns
    WHERE table_schema = %s AND table_name = %s
    ORDER BY ordinal_position;
    """
    conn = get_connection()
    cur = conn.cursor()
    cur.execute(query, (schema, table_name,))
    columns = cur.fetchall()
    cur.close()
    return [(col[0], col[1] is not None and 'nextval' in str(col[1])) for col in columns]

# --- Optional: fetch site IDs from reference table ---
def fetch_site_ids():
    try:
        conn = get_connection()
        cur = conn.cursor()
        cur.execute("SELECT id FROM solar_production_site ORDER BY id;")
        result = [row[0] for row in cur.fetchall()]
        cur.close()
        return result
    except:
        return [1, 2, 3]  # fallback

# --- Upload to PostgreSQL using COPY ---
def upload_csv_to_table(df, table_name):
    conn = get_connection()
    cur = conn.cursor()
    buffer = StringIO()
    df.to_csv(buffer, index=False, header=False)
    buffer.seek(0)
    columns = ','.join(df.columns)
    sql = f"COPY {table_name} ({columns}) FROM STDIN WITH CSV"
    cur.copy_expert(sql, buffer)
    conn.commit()
    cur.close()

# --- Main Component ---
def render_csv_uploader():
    st.title("Upload CSV to PostgreSQL with Column Mapping")

    uploaded_file = st.file_uploader("Upload CSV", type="csv")
    table_name = st.text_input("PostgreSQL Table Name")

    if uploaded_file and table_name:
        df = pd.read_csv(uploaded_file)
        st.write("CSV Preview:")
        st.dataframe(df.head())

        try:
            db_schema = get_table_columns(table_name)
            db_columns = [name for name, _ in db_schema]
            auto_columns = [name for name, is_auto in db_schema if is_auto]

            required_columns = [col for col in db_columns if col not in auto_columns]

            # Step 1: Map columns
            st.subheader("Map CSV Columns to Table Columns")
            mapping = {}
            for csv_col in df.columns:
                mapped_col = st.selectbox(
                    f"Map CSV column '{csv_col}' to:",
                    options=["-- skip --"] + db_columns,
                    key=csv_col
                )
                if mapped_col != "-- skip --":
                    mapping[csv_col] = mapped_col

            mapped_df = df.rename(columns=mapping)

                    # Step 2: Timestamp parsing (robust + debug)
         # Step 2: Use timestamps as-is (no parsing)
            if 'timestamp' in mapped_df.columns:
                st.info("Skipping timestamp parsing — using raw values.")
                # Optionally show a preview
                st.dataframe(mapped_df[['timestamp']].head(5))

            # Step 3: Handle missing required fields like fk_solar_production_site
            missing_required = [col for col in required_columns if col not in mapped_df.columns]

            if 'fk_solar_production_site' in missing_required:
                site_ids = fetch_site_ids()
                selected_site = st.selectbox("Select Solar Site ID", options=site_ids)
                mapped_df['fk_solar_production_site'] = selected_site

            # Handle missing 'spot_prices_fk' if required but not in CSV
            if 'spot_prices_fk' in missing_required:
                spot_fk = st.number_input("Enter Spot Prices FK (spot_prices_fk):", min_value=1, step=1)
                mapped_df['spot_prices_fk'] = int(spot_fk)

            # Step 4: Upload
            if st.button("Upload to Database"):
                upload_columns = [col for col in required_columns if col in mapped_df.columns]
                if sorted(upload_columns) != sorted(required_columns):
                    st.error(f"Mapped columns {upload_columns} do not match required table columns {required_columns}")
                else:
                    mapped_df = mapped_df[upload_columns]
                    upload_csv_to_table(mapped_df, table_name)
                    st.success(f"Data uploaded to '{table_name}' successfully!")

        except Exception as e:
            st.error(f"Error: {e}")

