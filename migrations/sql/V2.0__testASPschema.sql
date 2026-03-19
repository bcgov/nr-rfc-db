CREATE SCHEMA IF NOT EXISTS ASP;

CREATE TABLE if not exists ASP.measurements (
                 station_code TEXT NOT NULL,
                 datetime TIMESTAMP WITH TIME ZONE NOT NULL,
                 TA REAL,
                 PC REAL,
                 SW REAL,
                 SD REAL,
                 PRIMARY KEY (station_code, datetime));

-- locations
CREATE TABLE if not exists ASP.stations (
                 station_code TEXT PRIMARY KEY,
                 name TEXT NOT NULL UNIQUE,
                 agency TEXT,
                 active BOOLEAN,
                 elevation NUMERIC,
                 latitude NUMERIC,
                 longitude NUMERIC);