
CREATE SCHEMA IF NOT EXISTS ASP;

CREATE TABLE if not exists ASP.measurements (
                 station_code TEXT NOT NULL,
                 datetime TIMESTAMP WITH TIME ZONE NOT NULL,
                 TA NUMERIC,
                 PC NUMERIC,
                 SW NUMERIC,
                 SD NUMERIC,
                 PRIMARY KEY (station_code, datetime));
