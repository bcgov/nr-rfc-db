CREATE OR REPLACE VIEW asp.latestswe AS
SELECT DISTINCT ON (m.station_code)
    m.station_code,
    m.datetime,
    m.sw,
    -- Difference from today at 8:00 AM UTC
    m.sw - (
        SELECT m2.sw 
        FROM asp.measurements m2 
        WHERE m2.station_code = m.station_code 
          AND m2.datetime = (CURRENT_DATE + interval '8 hours')
        LIMIT 1
    ) AS sw_diff_today_8am,
    -- Difference from yesterday at 8:00 AM UTC
    m.sw - (
        SELECT m3.sw 
        FROM asp.measurements m3 
        WHERE m3.station_code = m.station_code 
          AND m3.datetime = (CURRENT_DATE - interval '16 hours')
        LIMIT 1
    ) AS sw_diff_yesterday_8am,
    s.latitude,
    s.longitude
FROM asp.measurements m
JOIN asp.stations s ON m.station_code = s.station_code
WHERE m.sw IS NOT null
  AND m.datetime >= now() - interval '3 hours'
ORDER BY m.station_code, m.datetime DESC;