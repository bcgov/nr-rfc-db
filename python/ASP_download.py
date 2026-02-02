import os
import datetime
import pandas as pd
import NRUtil.NRObjStoreUtil as NRObjStoreUtil
from sqlalchemy import create_engine, MetaData, Table, inspect, text
import psycopg
from io import StringIO

today = datetime.date.today()
start_day = today - datetime.timedelta(days=1)
day_str = start_day.strftime("%Y-%m-%d")

src_url = "https://www.env.gov.bc.ca/wsd/data_searches/snow/asws/data/"
file_list = ["TA.csv", "PC.csv", "SD.csv", "SW.csv"]

def update_table(data, table_name):
    conn = psycopg.connect("dbname='your_dbname' user='your_user' host='localhost' password='your_password'")
    cur = conn.cursor()

    cur.execute(f"""CREATE TEMP TABLE temp_table (
    LIKE {table_name}
    ) ON COMMIT DROP;""") # ON COMMIT DROP ensures the temp table is automatically deleted

    output = StringIO()
    # Select only the columns needed for the update and match the order of the temp table columns
    data.to_csv(output, sep='\t', header=False, index=False)
    output.seek(0)
    cur.copy_from(output, 'temp_table', null='') # Use tab as delimiter for copy_from
    # 3. Execute an UPDATE statement to update the main table from the temp table
    update_query = """
    UPDATE table_name AS t
    SET 
        column_to_update = tt.column_to_update,
        another_column = tt.another_column
    FROM temp_table AS tt
    """
    cur.execute(update_query)

    # 4. Commit the changes
    conn.commit()

    # 5. Close connections
    cur.close()
    conn.close()

def get_schema(table_name: str):
    split_name = table_name.split('.')
    if len(split_name)==2:
        return split_name[0], split_name[1]
    else:
        return '', split_name[-1]

def get_primary_keys(table_name: str, engine):
    metadata = MetaData()
    pks = []

    schema_nm, table_nm = get_schema(table_name)
    try:
        # Reflect the table from the database
        table = Table(table_nm, metadata, autoload_with=engine,schema=schema_nm)
        
        # Access the primary key columns
        primary_key_columns = [pk_column.name for pk_column in table.primary_key.columns.values()]
        pks = primary_key_columns

    except Exception as e:
        print(f"Error reflecting table with SQLAlchemy: {e}")
    
    return pks

def upsert_df_to_postgres(df: pd.DataFrame, table_name: str, engine):
    """
    Performs an upsert from a pandas DataFrame to a PostgreSQL table 
    using a temporary table approach. 
    Assumes a primary key or unique constraint is defined on the target table.
    """

    conn = engine.connect()
    # 1. Generate SQL statement to create a temporary table:
    #Temporary table copes columns from 
    create_temp_table = text((f"""CREATE TEMP TABLE temp_table (
    LIKE {table_name} INCLUDING CONSTRAINTS
    ) ON COMMIT DROP;"""))
    conn.execute(create_temp_table)
    
    # 2. Use pandas.to_sql to quickly load data into the temporary table
    #    'if_exists="replace"' creates a new temp table each time.
    df.to_sql('temp_table', engine, if_exists='replace', index=False)

    # 3. Construct the ON CONFLICT DO UPDATE statement
    #    Replace 'id_col' with your actual primary key column name(s).
    #    Specify the columns to update on conflict (all except the key(s)).
    pk_cols = get_primary_keys(table_name, engine)
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
    conn.commit() # Commit the transaction

    if conn:
        conn.close()

    # 5. The temporary table is dropped automatically by PostgreSQL at the end of the session
    print(f"Data upserted successfully into {table_name}")


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
# Connection string (adjust credentials as needed)
engine = create_engine('postgresql+psycopg://rfc_db_user:default@localhost:5433/rfc_db_1', echo=True)


df_query = pd.read_sql(f"SELECT * FROM ASP.measurements WHERE datetime > '{day_str}'", con=engine)
merged_df = merged_df[merged_df['datetime']>datetime.datetime.combine(start_day, datetime.time.min)]
merged_df['datetime'] = merged_df['datetime'].dt.tz_localize('UTC')

df_update = merged_df.merge(df_query, how='outer', indicator=True).query('_merge == "left_only"').drop(columns=['_merge'])


# Append data (might cause key conflicts)
upsert_df_to_postgres(df = df_update, table_name ='asp.measurements', engine = engine)
#web_data = merged_df[merged_df['station_code']=='1A01P']
#pg_data = df_query[df_query['station_code']=='1A01P']
#out_merge = web_data.merge(pg_data, how='outer', indicator=True)

engine.dispose()
#merged_df.to_sql('measurements', schema="asp", con=engine, if_exists='append', index=False)
#Check data in database

# Replace table entirely
# df.to_sql('your_table_name', con=engine, if_exists='replace', index=False)