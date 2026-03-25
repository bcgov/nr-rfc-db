CREATE VIEW ASP.station_latest_swe AS
SELECT DISTINCT ON (station_code)
    s.station_code,
    s.latitude,
    s.longitude,
    d.sw,
    d.datetime
FROM ASP.stations s
JOIN ASP.measurements d ON s.station_code = d.station_code
ORDER BY s.station_code, d.datetime DESC;