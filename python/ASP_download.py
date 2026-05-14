import os
import datetime
import requests
import pandas as pd
import numpy as np
#import NRUtil.NRObjStoreUtil as NRObjStoreUtil
#from sqlalchemy import create_engine, MetaData, Table, inspect, text
#import psycopg
import logging.config
import pathlib
import jwt
#from dotenv import load_dotenv

#load_dotenv()


logger = logging.getLogger(__name__)

class db_connect:
    def __init__(self):
        host = os.getenv("PG_HOST", 'localhost')
        #port = os.getenv("PG_PORT", '5433')
        port = os.getenv("PG_PORT", '15432')
        username = os.getenv("PG_USERNAME", 'rfc_db_user')
        password = os.getenv("PG_PASSWORD", 'default')
        database = os.getenv('PG_DBNAME', 'rfc_db_1')
        dsc = f"postgresql+psycopg://{username}:{password}@{host}:{port}/{database}"
        self.engine = create_engine(dsc, echo=True)
        #self.conn: psycopg.Connection|None = None
    
    def exit(self):
        self.engine.dispose()

    def _get_schema(self, table_name: str):
        split_name = table_name.split('.')
        if len(split_name)==2:
            return split_name[0], split_name[1]
        else:
            return '', split_name[-1]
    
    def _get_primary_keys(self, table_name: str):
        metadata = MetaData()
        pks = []

        schema_nm, table_nm = self._get_schema(table_name)
        try:
            # Reflect the table from the database
            table = Table(table_nm, metadata, autoload_with=self.engine, schema=schema_nm)
            
            # Access the primary key columns
            primary_key_columns = [pk_column.name for pk_column in table.primary_key.columns.values()]
            pks = primary_key_columns

        except Exception as e:
            print(f"Error reflecting table with SQLAlchemy: {e}")
        
        return pks

    def query(self, query:str):
        return pd.read_sql(query, con=self.engine)
        #df_query = pd.read_sql(f"SELECT * FROM ASP.measurements WHERE datetime > '{day_str}'", con=engine)

    def diff_from_db(self, df: pd.DataFrame, table_name: str):
        min_day = df['datetime'].min().strftime("%Y-%m-%d")
        max_day = df['datetime'].max().strftime("%Y-%m-%d")
        df_query = self.query(f"SELECT * FROM {table_name} WHERE datetime BETWEEN '{min_day}' AND '{max_day}'")
        df_diff = df.merge(df_query, how='outer', indicator=True).query('_merge == "left_only"').drop(columns=['_merge'])
        return df_diff

    def upsert_df_to_postgres(self, df: pd.DataFrame, table_name: str):
        """
        Performs an upsert from a pandas DataFrame to a PostgreSQL table 
        using a temporary table approach. 
        Assumes a primary key or unique constraint is defined on the target table.
        """

        with self.engine.connect() as conn:
            with conn.begin():
                # 1. Generate SQL statement to create a temporary table:
                #Temporary table copes columns from 
                create_temp_table = text((f"""CREATE TEMP TABLE temp_table (
                LIKE {table_name} INCLUDING CONSTRAINTS
                ) ON COMMIT DROP;"""))
                conn.execute(create_temp_table)
                
                df = self.diff_from_db(df=df, table_name=table_name)
                # 2. Use pandas.to_sql to quickly load data into the temporary table
                #    'if_exists="replace"' creates a new temp table each time.
                df.to_sql('temp_table', conn, if_exists='append', index=False)

                # 3. Construct the ON CONFLICT DO UPDATE statement
                #    Replace 'id_col' with your actual primary key column name(s).
                #    Specify the columns to update on conflict (all except the key(s)).
                pk_cols = self._get_primary_keys(table_name)
                update_cols = [col for col in df.columns if col not in pk_cols]
                
                # Create the SET clause for the UPDATE part of the query
                set_clause = ", ".join([f"{col} = EXCLUDED.{col}" for col in update_cols])
                conflict_cols_clause = ", ".join(pk_cols)

                #This query worked when manually entered in DBeaver:
                upsert_query = text(f"""
                    INSERT INTO {table_name}
                    SELECT * FROM temp_table
                    ON CONFLICT ({conflict_cols_clause})
                    DO UPDATE SET {set_clause};
                """)
                conn.execute(upsert_query)
                #conn.commit() # Commit the transaction


        # 5. The temporary table is dropped automatically by PostgreSQL at the end of the session
        print(f"Data upserted successfully into {table_name}")

src_url = "https://www.env.gov.bc.ca/wsd/data_searches/snow/asws/data/"
file_list = ["TA.csv", "PC.csv", "SD.csv", "SW.csv"]

def ASP_download():
    df_list = list()
    for file in file_list:
        var_name = file.split('.')[0].lower()
        df = pd.read_csv(os.path.join(src_url,file))
        df.columns = [str.split(" ")[0] for str in df.columns]
        df = df.rename(columns={df.columns[0]: "datetime"})
        output = df.melt(id_vars=['datetime'], var_name='station_code',value_name=var_name)
        output = output.set_index(['station_code','datetime'])
        df_list.append(output)
    merged_df = pd.concat(df_list, axis=1) 
    merged_df = merged_df.reset_index()
    merged_df['datetime'] = pd.to_datetime(merged_df['datetime'], format="%Y-%m-%d %H:%M")
    
    return merged_df

def post_data(payload, url, schema, token):
    headers = {
        "Content-Type": "application/json",
        "Content-Profile": schema,  # Specify the 'data' schema for the insert
        "Prefer": "resolution=merge-duplicates", # This enables UPSERT logic
        "Authorization": f"Bearer {token}"
    }
    chunk_size = 10000
    chunked_list = [payload[i:i + chunk_size] for i in range(0, len(payload), chunk_size)]
    for chunk in chunked_list:
        response = requests.post(url, json=chunk, headers=headers)
        if response.status_code == 201:
            print("Success: Data inserted.")
        else:
            print(f"Error {response.status_code}: {response.text}")
# Connection string (adjust credentials as needed)
#engine = create_engine('postgresql+psycopg://rfc_db_user:default@localhost:5433/rfc_db_1', echo=True)


table_name = "your_table_name"

def get_primary_keys(base_url, table_name, schema):
    # Query the information_schema via PostgREST
    # Note: Ensure your PostgREST role has SELECT permissions on information_schema
    pk_query_url = f"{base_url}/rpc/get_pks" # Alternative: query views directly if exposed
    # Most common direct view query:
    pk_url = f"{base_url}/information_schema/key_column_usage"
    params = {
        "table_name": f"eq.{table_name}",
        "select": "column_name",
        "table_schema": f"eq.{schema}" # Adjust schema if necessary
    }

    pk_response = requests.get(pk_url, params=params)
    pk_columns = [row['column_name'] for row in pk_response.json()]
    on_conflict_str = ",".join(pk_columns)
    return on_conflict_str




# Append data (might cause key conflicts)
#upsert_df_to_postgres(df = df_update, table_name ='asp.measurements', engine = engine)
#web_data = merged_df[merged_df['station_code']=='1A01P']
#pg_data = df_query[df_query['station_code']=='1A01P']
#out_merge = web_data.merge(pg_data, how='outer', indicator=True)

#engine.dispose()
#merged_df.to_sql('measurements', schema="asp", con=engine, if_exists='append', index=False)
#Check data in database

# Replace table entirely
# df.to_sql('your_table_name', con=engine, if_exists='replace', index=False)
def generate_token(role="web_user"):
    payload = {
        "role": role,
        "exp": datetime.datetime.now(datetime.UTC) + datetime.timedelta(hours=1),
        "iat": datetime.datetime.now(datetime.UTC)
    }
    return jwt.encode(payload, JWT_SECRET, algorithm="HS256")

if __name__ == "__main__":
    log_config = pathlib.Path(__file__).parent / "logging.config"
    logging.config.fileConfig(log_config)
    logger = logging.getLogger("main")
    logger.info("Starting")

    #rfc_db = db_connect()
    today = datetime.date.today()
    start_day = today - datetime.timedelta(days=30)
    day_str = start_day.strftime("%Y-%m-%d")

    ASP_data = ASP_download()
    ASP_data = ASP_data[ASP_data['datetime']>datetime.datetime.combine(start_day, datetime.time.min)]
    ASP_data['datetime'] = ASP_data['datetime'].dt.tz_localize('UTC')

    # This MUST match the secret in your OpenShift Secret / postgrest.conf
    JWT_SECRET = os.getenv("JWT_SECRET")

    

    # Use it in your request
    token = generate_token()

    #rfc_db.upsert_df_to_postgres(df = ASP_data, table_name = 'asp.measurements')
    #Test: send data via API call
    # 2. Convert DataFrame to a list of dictionaries (JSON array)
    ASP_data['datetime'] = ASP_data['datetime'].dt.strftime('%Y-%m-%dT%H:%M:%S')
    ASP_data = ASP_data.replace({pd.NA: None, np.nan: None})
    payload = ASP_data.to_dict(orient='records')

    # 3. API endpoint and headers
    # Replace 'localhost:3000' and 'measurements' with your actual values
    #base_url = "http://localhost:3000"
    #base_url = "https://rfc-database.apps.silver.devops.gov.bc.ca"
    base_url = "https://rfc-db.apps.silver.devops.gov.bc.ca"
    table_name = "measurements"
    url = f"{base_url}/{table_name}"
    schema = "asp"

    post_data(payload=payload, url=url, schema=schema, token=token)
    
#db_content = rfc_db.query("SELECT * FROM asp.measurements")

#Example API call to retrieve data:
#http://localhost:3000/measurements?datetime=gte.2026-01-01&datetime=lte.2026-01-05
#https://rfc-db.apps.silver.devops.gov.bc.ca/measurements?datetime=gte.2026-01-01&datetime=lte.2026-01-05