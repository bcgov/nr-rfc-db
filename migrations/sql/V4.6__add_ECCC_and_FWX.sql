CREATE TABLE if not exists ASP.ECCC_raw (
                 station_code TEXT NOT NULL,
                 datetime TIMESTAMP WITH TIME ZONE NOT NULL,
                 TA REAL,
                 PC REAL,
                 f_Read BOOLEAN,
                 PRIMARY KEY (station_code, datetime));

CREATE TABLE if not exists ASP.FWX_raw (
                 station_code TEXT NOT NULL,
                 datetime TIMESTAMP WITH TIME ZONE NOT NULL,
                 TA REAL,
                 PC REAL,
                 RH REAL,
                 WS REAL,
                 WD REAL,
                 PRIMARY KEY (station_code, datetime));

ALTER TABLE ASP.stations ADD COLUMN network TEXT, ADD COLUMN RFC_ID TEXT;

CREATE TABLE if not exists ASP.NWP_forecast (
                 model TEXT NOT NULL,
                 runtime TIMESTAMP WITH TIME ZONE NOT NULL,
                 datetime TIMESTAMP WITH TIME ZONE NOT NULL,
                 rfc_id TEXT NOT NULL,
                 TA REAL,
                 PC REAL,
                 PRIMARY KEY (model, runtime, datetime, rfc_id));