import bcdata
import requests
import datetime
import geopandas as gpd
import pandas as pd
import numpy as np
import jwt
import os
from dotenv import load_dotenv

load_dotenv()

def get_asp_metadata():
    # bcdc_get_data equivalent: downloads to a temp file
    # The ID "ebe546aa..." refers to the Automated Snow Weather Station Locations
    resource_id = "ebe546aa-ac34-491c-a828-fdc87fb70610"
    data = bcdata.get_data(resource_id)

    # 2. Load the data (usually GeoJSON for this resource)
    # If 'data' is a list of GeoJSON features (common for bcdata)
    asp_meta = gpd.GeoDataFrame.from_features(data["features"])

    # 3. Data manipulation using pandas/geopandas
    meta = (
        asp_meta
        # rename() equivalent
        .rename(columns={
            'LOCATION_ID': 'station_code',
            'LOCATION_NAME': 'name',
            'OPERATOR': 'agency',
            'ELEVATION': 'elevation',
            'LATITUDE': 'latitude',
            'LONGITUDE': 'longitude'
        })
        # mutate() and replace_na() equivalent
        .assign(
            active = lambda x: x['STATUS'] == 'Active',
            elevation = lambda x: x['elevation'].fillna(0),
            agency = lambda x: x['agency'].fillna('Unknown')
        )
        # select() equivalent
        [['station_code', 'name', 'agency', 'active', 'elevation', 'longitude', 'latitude']]
    )
    meta = meta[meta['active'] == True]
    meta['network'] = 'BC Snow Program'
    return meta

def get_fwx_metadata():
    resource_url = "https://www.for.gov.bc.ca/ftp/HPR/external/!publish/BCWS_DATA_MART/2023/2023_BCWS_WX_STATIONS.csv"
    fwx_data = pd.read_csv(resource_url)
    meta = (
        fwx_data
        # rename() equivalent
        .rename(columns={
            'STATION_CODE': 'station_code',
            'STATION_NAME': 'name',
            'ELEVATION_M': 'elevation',
            'LATITUDE': 'latitude',
            'LONGITUDE': 'longitude'
        })
        # select() equivalent
        [['station_code', 'name', 'elevation', 'longitude', 'latitude']]
    )
    meta['elevation'] = meta['elevation'].replace({pd.NA: 0, np.nan: 0})
    meta['network'] = 'BC Wildfire Service'
    meta['active'] = True
    return meta

def get_eccc_metadata():
    resource_url = "https://hpfx.collab.science.gc.ca/today/observations/doc/swob-xml_station_list.csv"
    eccc_data = pd.read_csv(resource_url)
    geog_to_keep = ['British Columbia', 'Yukon']
    eccc_data = eccc_data[eccc_data['Province/Territory'].isin(geog_to_keep)]
    meta = (
        eccc_data
        # rename() equivalent
        .rename(columns={
            'IATA_ID': 'station_code',
            'Name': 'name',
            'Data_Provider': 'agency',
            'Elevation(m)': 'elevation',
            'Latitude': 'latitude',
            'Longitude': 'longitude'
        })
        # select() equivalent
        [['station_code', 'name', 'agency', 'elevation', 'longitude', 'latitude']]
    )
    meta['network'] = 'Environment and Climate Change Canada'
    meta['elevation'] = meta['elevation'].replace({pd.NA: 0, np.nan: 0})
    meta['active'] = True
    meta['station_code'] = meta['station_code'].str[1:] # Remove any leading/trailing whitespace
    return meta

def get_swe_historical_data():
    # bcdc_get_data equivalent: downloads to a temp file
    # The ID "ebe546aa..." refers to the Automated Snow Weather Station Locations
    resource_url = "http://www.env.gov.bc.ca/wsd/data_searches/snow/asws/data/SW_DailyArchive.csv"
    asp_data = pd.read_csv(resource_url)
    
    asp_data.columns = asp_data.columns.str.split(' ').str[0]
    
    melted_df = asp_data.melt(id_vars='DATE(UTC)', 
                     var_name='station_code', 
                     value_name='sw')
    # 3. Data manipulation using pandas/geopandas
    melted_df.rename(columns={'DATE(UTC)': 'date'}, inplace=True)
    melted_df = melted_df.replace({pd.NA: None, np.nan: None})
    melted_df['date'] = pd.to_datetime(melted_df['date'], format="%Y-%m-%d %H:%M")
    melted_df['date'] = melted_df['date'].dt.strftime('%Y-%m-%dT%H:%M:%S')
    melted_df = melted_df.dropna(subset=['sw'])
    melted_df['ta']=None
    melted_df['pc']=None
    melted_df['sd']=None
    return melted_df


def generate_token(role="web_user"):
    payload = {
        "role": role,
        "exp": datetime.datetime.now(datetime.UTC) + datetime.timedelta(hours=1),
        "iat": datetime.datetime.now(datetime.UTC)
    }
    return jwt.encode(payload, JWT_SECRET, algorithm="HS256")

def insert_metadata(data_df, table_name, api_url, token=None):
    # Use it in your request
    payload = data_df.to_dict(orient='records')
    #token = generate_token()
    # 3. API endpoint and headers
    # Replace 'localhost:3000' and 'measurements' with your actual values
    
    url = f"{api_url}/{table_name}"
    schema = "asp"
    #table_name = "stations"
    headers = {
        "Content-Type": "application/json",
        "Content-Profile": schema,  # Specify the 'data' schema for the insert
        "Prefer": "resolution=merge-duplicates" # This enables UPSERT logic
    }
    if token is not None:
        headers["Authorization"] = f"Bearer {token}"

    response = requests.post(url, json=payload, headers=headers)
    print(response.status_code)

# This MUST match the secret in your OpenShift Secret / postgrest.conf
JWT_SECRET = os.getenv("JWT_SECRET")

if True:
    token = generate_token()
    local_db_url = "http://localhost:3000"
    openshift_db_url = "https://rfc-db-dev.apps.silver.devops.gov.bc.ca"

if True:
    hist = get_swe_historical_data()
    table_name = "historical"
    #insert_metadata(hist, table_name, local_db_url)
    insert_metadata(hist, table_name, openshift_db_url, token)

if False:
    meta1 = get_asp_metadata()
    meta2 = get_fwx_metadata()
    meta3 = get_eccc_metadata()
    meta_climateobs = pd.read_csv("data/ClimateOBS_metadata.csv")
    meta_climateobs = meta_climateobs.rename(columns={
        'STATION_CODE': 'station_code',
        'RFC_ID': 'rfc_id'
    })[['station_code', 'rfc_id']]
    meta = pd.concat([meta1, meta2, meta3], ignore_index=True)
    meta = meta.drop_duplicates(subset=['station_code'])
    meta['station_code'] = meta['station_code'].astype(str)
    meta = meta.merge(meta_climateobs, on='station_code', how='left')
    meta = meta.replace({pd.NA: None, np.nan: None})
    counts = meta.groupby('name').cumcount().add(1).astype(str)
    meta['name'] = meta['name'].astype(str) + counts.mask(counts == '1', '')
    print(meta.head())
    table_name = "stations"
    insert_metadata(meta, table_name, openshift_db_url, token)
    #insert_metadata(meta, table_name, openshift_db_url, token)