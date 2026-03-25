import bcdata
import requests
import datetime
import geopandas as gpd
import pandas as pd
import jwt
import os
from dotenv import load_dotenv

load_dotenv()

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

# 4. st_drop_geometry() equivalent: convert GeoDataFrame to regular DataFrame
#meta = pd.DataFrame(meta.drop(columns='geometry'))

print(meta.head())

def generate_token(role="web_user"):
    payload = {
        "role": role,
        "exp": datetime.datetime.now(datetime.UTC) + datetime.timedelta(hours=1),
        "iat": datetime.datetime.now(datetime.UTC)
    }
    return jwt.encode(payload, JWT_SECRET, algorithm="HS256")


# This MUST match the secret in your OpenShift Secret / postgrest.conf
JWT_SECRET = os.getenv("JWT_SECRET")

# Use it in your request
meta = meta[meta['active'] == True]
payload = meta.to_dict(orient='records')
#token = generate_token()
# 3. API endpoint and headers
# Replace 'localhost:3000' and 'measurements' with your actual values
base_url = "http://localhost:3000"
#base_url = "https://rfc-database.apps.silver.devops.gov.bc.ca"
url = f"{base_url}/stations"
schema = "asp"
table_name = "stations"
headers = {
    "Content-Type": "application/json",
    "Content-Profile": schema,  # Specify the 'data' schema for the insert
    "Prefer": "resolution=merge-duplicates" # This enables UPSERT logic
    #"Authorization": f"Bearer {token}"
}

response = requests.post(url, json=payload, headers=headers)
print(response.status_code)