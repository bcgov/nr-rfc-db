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