CREATE VIEW latest_swe AS
SELECT DISTINCT ON (m.station_code)
    m.station_code,
    m.datetime,
    m.sw,
    s.latitude,
    s.longitude
FROM asp.measurements m
JOIN asp.stations s ON m.station_code = s.station_code
ORDER BY m.station_code, m.datetime DESC;