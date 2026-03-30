CREATE TABLE if not exists ASP.historical (
                 station_code TEXT NOT NULL,
                 date TIMESTAMP WITH TIME ZONE NOT NULL,
                 TA REAL,
                 PC REAL,
                 SW REAL,
                 SD REAL,
                 PRIMARY KEY (station_code, date));

CREATE MATERIALIZED VIEW ASP.sw_percentiles AS
SELECT 
    station_code,
    to_char(date, 'MM-DD') AS day_of_year, -- Groups all Jan 1sts together
    MIN(SW) AS p0,
    percentile_cont(0.05) WITHIN GROUP (ORDER BY SW) AS p5,
    percentile_cont(0.10) WITHIN GROUP (ORDER BY SW) AS p10,
    percentile_cont(0.25) WITHIN GROUP (ORDER BY SW) AS p25,
    percentile_cont(0.50) WITHIN GROUP (ORDER BY SW) AS p50,
    percentile_cont(0.75) WITHIN GROUP (ORDER BY SW) AS p75,
    percentile_cont(0.90) WITHIN GROUP (ORDER BY SW) AS p90,
    percentile_cont(0.95) WITHIN GROUP (ORDER BY SW) AS p95,
    MAX(SW) AS p100
FROM 
    ASP.historical
WHERE 
    SW IS NOT NULL 
GROUP BY 
    station_code,
    day_of_year
ORDER BY 
    station_code,
    day_of_year;

-- Required for CONCURRENT refresh (allows others to read while it updates)
CREATE UNIQUE INDEX idx_station_day ON ASP.sw_percentiles (station_code, day_of_year);

CREATE OR REPLACE FUNCTION refresh_daily_percentiles()
RETURNS TRIGGER AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY ASP.sw_percentiles;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_refresh_percentiles
AFTER INSERT OR UPDATE ON ASP.historical
FOR EACH STATEMENT EXECUTE FUNCTION refresh_daily_percentiles();