CREATE SCHEMA IF NOT EXISTS HYDRO;

CREATE TABLE if not exists HYDRO.user_groups (
    group_id SERIAL PRIMARY KEY,
    group_name TEXT UNIQUE NOT NULL,
    group_description TEXT NOT NULL);

CREATE OR REPLACE FUNCTION HYDRO.prevent_delete_public_group()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.group_id = 1 THEN
        RAISE EXCEPTION 'Cannot delete the public group (group_id 1)';
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

-- triggers inherit the schema from the table they query
CREATE TRIGGER prevent_delete_public_group_trigger
BEFORE DELETE ON HYDRO.user_groups
FOR EACH ROW
EXECUTE FUNCTION HYDRO.prevent_delete_public_group();

-- have to declare the column before adding the foreign key
CREATE TABLE IF NOT EXISTS HYDRO.users (
                 user_id SERIAL PRIMARY KEY,
                 username TEXT UNIQUE NOT NULL,
                 email TEXT UNIQUE NOT NULL,
                 user_groups INTEGER[] NOT NULL DEFAULT '{1}',
                 password_hash TEXT NOT NULL,
                 password_salt TEXT NOT NULL,
                 algorithm TEXT NOT NULL DEFAULT 'sha256',
                 group_id INTEGER,
                 FOREIGN KEY (group_id) REFERENCES HYDRO.user_groups(group_id) );


CREATE TABLE IF NOT EXISTS HYDRO.owners_contributors (
                 owner_contributor_id SERIAL PRIMARY KEY,
                 name TEXT UNIQUE NOT NULL,
                 contact_name TEXT,
                 phone TEXT,
                 email TEXT,
                 note TEXT
               );

CREATE TABLE if not exists HYDRO.measurements_continuous (
                 timeseries_id INTEGER NOT NULL,
                 datetime TIMESTAMP WITH TIME ZONE NOT NULL,
                 value NUMERIC NOT NULL,
                 grade TEXT,
                 approval TEXT,
                 period INTERVAL,
                 imputed BOOLEAN NOT NULL DEFAULT FALSE,
                 no_update BOOLEAN NOT NULL DEFAULT FALSE,
                 share_with INTEGER[] NOT NULL DEFAULT '{1}',
                 owner INTEGER DEFAULT NULL REFERENCES HYDRO.owners_contributors (owner_contributor_id) ON DELETE SET NULL ON UPDATE CASCADE,
                 contributor INTEGER DEFAULT NULL REFERENCES HYDRO.owners_contributors (owner_contributor_id) ON DELETE SET NULL ON UPDATE CASCADE,
                 PRIMARY KEY (timeseries_id, datetime));
                 
COMMENT ON TABLE HYDRO.measurements_continuous IS 'Stores observations and imputed values for continuous timeseries.';
COMMENT ON COLUMN HYDRO.measurements_continuous.period IS 'Greater than 0 for min, max, sum, mean types of measurements. The periodicity of data can change within a timeseries, for example if recording rates go from every 6 hours to hourly.';
COMMENT ON COLUMN HYDRO.measurements_continuous.imputed IS 'Imputed values may be user-entered. Imputed values are automatically replaced if/when a value becomes available on the remote data store.';

CREATE TABLE if not exists HYDRO.calculated_daily (
                 timeseries_id INTEGER NOT NULL,
                 date DATE NOT NULL,
                 value NUMERIC,
                 grade TEXT,
                 approval TEXT,
                 imputed BOOLEAN NOT NULL DEFAULT FALSE,
                 no_update BOOLEAN NOT NULL DEFAULT FALSE,
                 percent_historic_range NUMERIC,
                 max NUMERIC,
                 min NUMERIC,
                 q90 NUMERIC,
                 q75 NUMERIC,
                 q50 NUMERIC,
                 q25 NUMERIC,
                 q10 NUMERIC,
                 mean NUMERIC,
                 doy_count INTEGER,
                 share_with INTEGER[] NOT NULL DEFAULT '{1}',
                 owner INTEGER DEFAULT NULL REFERENCES HYDRO.owners_contributors (owner_contributor_id) ON DELETE SET NULL ON UPDATE CASCADE,
                 contributor INTEGER DEFAULT NULL REFERENCES HYDRO.owners_contributors (owner_contributor_id) ON DELETE SET NULL ON UPDATE CASCADE,
                 PRIMARY KEY (timeseries_id, date));


COMMENT ON TABLE HYDRO.calculated_daily IS 'Stores calculated daily mean values for timeseries present in table measurements_continuous. Values should not be entered or modified manually but instead are calculated by the AquaCache package function calculate_stats.';
COMMENT ON COLUMN HYDRO.calculated_daily.imputed IS 'TRUE in this column means that at least one of the measurements used for the daily mean calculation was imputed, or, for daily means provided solely in the HYDAT database, that a value was imputed directly to this table.';
COMMENT ON COLUMN HYDRO.calculated_daily.percent_historic_range IS 'The percent of historical range for that measurement compared to all previous records for the same day of year (not including the current measurement). Only populated once a minimum of three values exist for the current day of year (including the current value). February 29 values are the mean of February 28 and March 1. 
For example, a value equal to the maximum historic value is equal to 100% of historical range, while one at the miniumu value is 0%. Values above or below the historical range can have values of less than 0 or greater than 100.
The formula used for the calculation is ((current - min) / (max - min)) * 100';
COMMENT ON COLUMN HYDRO.calculated_daily.max IS 'Historical max for the day of year, excluding current measurement.';
COMMENT ON COLUMN HYDRO.calculated_daily.min IS 'Historical min for the day of year, excluding current measurement.';
COMMENT ON COLUMN HYDRO.calculated_daily.q50 IS 'Historical 50th quantile or median, excluding current measurement.';
COMMENT ON COLUMN HYDRO.calculated_daily.q25 IS 'Number of measurements existing in the calculated_daily table for each day including historic and current measurement.';


CREATE TABLE if not exists HYDRO.images (
    image_id SERIAL PRIMARY KEY,
    img_meta_id INTEGER NOT NULL,
    datetime TIMESTAMP WITH TIME ZONE NOT NULL,
    fetch_datetime TIMESTAMP WITH TIME ZONE,
    format TEXT NOT NULL,
    file BYTEA NOT NULL,
    description TEXT,
    share_with INTEGER[] NOT NULL DEFAULT '{1}',
    owner INTEGER DEFAULT NULL REFERENCES HYDRO.owners_contributors (owner_contributor_id) ON DELETE SET NULL ON UPDATE CASCADE,
    contributor INTEGER DEFAULT NULL REFERENCES HYDRO.owners_contributors (owner_contributor_id) ON DELETE SET NULL ON UPDATE CASCADE,
    UNIQUE (img_meta_id, datetime));

COMMENT ON TABLE HYDRO.images IS 'Holds images of local conditions specific to each location. Originally designed to hold auto-captured images at WSC locations, but could be used for other location images. NOT intended to capture what the instrumentation looks like, only what the conditions at the location are.';


CREATE TABLE IF NOT EXISTS HYDRO.images_index (
                 img_meta_id SERIAL PRIMARY KEY,
                 img_type TEXT NOT NULL CHECK(img_type IN ('auto', 'manual')),
                 first_img TIMESTAMP WITH TIME ZONE,
                 last_img TIMESTAMP WITH TIME ZONE,
                 last_new_img TIMESTAMP WITH TIME ZONE,
                 public BOOLEAN NOT NULL,
                 public_delay INTERVAL,
                 source_fx TEXT,
                 source_fx_args TEXT,
                 description TEXT,
                 location_id INTEGER NOT NULL,
                 visibility_public TEXT NOT NULL CHECK(visibility_public IN ('exact', 'region', 'jitter')) DEFAULT 'exact',
                 share_with INTEGER[] NOT NULL DEFAULT '{1}',
                 owner INTEGER DEFAULT NULL REFERENCES HYDRO.owners_contributors (owner_contributor_id) ON DELETE SET NULL ON UPDATE CASCADE,
                 active BOOLEAN,
                 UNIQUE (location_id, img_type));

COMMENT ON TABLE HYDRO.images_index IS 'Index for images table. Each location at which there is one or more image gets an entry here; images in table images are linked to this table using the img_meta_id.';
COMMENT ON COLUMN HYDRO.images_index.active IS 'Defines if the image series should or should not be imported.';

CREATE TABLE if not exists HYDRO.forecasts (
                   timeseries_id INTEGER,
                   issue_datetime TIMESTAMP WITH TIME ZONE,
                   datetime TIMESTAMP WITH TIME ZONE NOT NULL,
                   value NUMERIC,
                   min NUMERIC,
                   q10 NUMERIC,
                   q25 NUMERIC,
                   q50 NUMERIC,
                   q75 NUMERIC,
                   q90 NUMERIC,
                   max NUMERIC,
                   PRIMARY KEY (timeseries_id, datetime));

COMMENT ON TABLE HYDRO.forecasts IS 'Holds forecast timeseries information. Each timeseries must match up with a timeseries_id from the timeseries table. Quantiles are optional. Data should be deleted after a certain time interval to prevent unecessarily burdening the database.';
COMMENT ON COLUMN HYDRO.forecasts.issue_datetime IS 'The datetime at which the forecast data point (row) was issued.';
COMMENT ON COLUMN HYDRO.forecasts.issue_datetime IS 'The datetime for which the forecast data point (row) is valid.';

CREATE TABLE if not exists HYDRO.measurements_discrete (
                   timeseries_id INTEGER,
                   target_datetime TIMESTAMP WITH TIME ZONE,
                   datetime TIMESTAMP WITH TIME ZONE,
                   value NUMERIC NOT NULL,
                   sample_class TEXT,
                   note TEXT,
                   no_update BOOLEAN NOT NULL DEFAULT FALSE,
                   share_with INTEGER[] NOT NULL DEFAULT '{1}',
                   owner INTEGER DEFAULT NULL REFERENCES HYDRO.owners_contributors (owner_contributor_id) ON DELETE SET NULL ON UPDATE CASCADE,
                   contributor INTEGER DEFAULT NULL REFERENCES HYDRO.owners_contributors (owner_contributor_id) ON DELETE SET NULL ON UPDATE CASCADE,
                   PRIMARY KEY (timeseries_id, datetime, sample_class));

COMMENT ON TABLE HYDRO.measurements_discrete IS 'Holds discrete observations, such as snow survey results, laboratory analyses, etc.';
COMMENT ON COLUMN HYDRO.measurements_discrete.target_datetime IS 'Optional column to be used for things like snow surveys where the measurements are around a certain target date and need to be plotted with the target date rather than the actual sample date.';
COMMENT ON COLUMN HYDRO.measurements_discrete.datetime IS 'The datetime on which the measurement was taken, or on which the sample was acquired in the field.';
COMMENT ON COLUMN HYDRO.measurements_discrete.sample_class IS 'Mostly for aqueous chem samples, to identify the sample as regular, field duplicate, lab duplicate, etc.';
COMMENT ON COLUMN HYDRO.measurements_discrete.value IS 'Values below the detection limit are listed as the negative of the detection limit to keep everything numeric.';
  
CREATE TABLE if not exists HYDRO.sample_class (
                 code TEXT PRIMARY KEY,
                 description TEXT NOT NULL,
                 description_fr TEXT);

INSERT INTO HYDRO.sample_class
(code, description)
 Values ('M', 'Monitoring (routine)'),
        ('D', 'Duplicate/Replicate or split sample'),
        ('I', 'Incident response'),
        ('U', 'Undefined');

ALTER TABLE HYDRO.measurements_discrete
    ADD CONSTRAINT fk_class
    FOREIGN KEY (sample_class)
    REFERENCES HYDRO.sample_class(code)
    ON DELETE CASCADE
    ON UPDATE CASCADE;

CREATE OR REPLACE FUNCTION HYDRO.check_sample_class_exists()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM HYDRO.sample_class WHERE code = NEW.sample_class) THEN
        RAISE EXCEPTION 'Invalid sample class code: %', NEW.sample_class;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER before_insert_or_update_sample_class
BEFORE INSERT OR UPDATE OF sample_class ON HYDRO.measurements_discrete
FOR EACH ROW
EXECUTE FUNCTION HYDRO.check_sample_class_exists();


CREATE TABLE if not exists HYDRO.grades (
                 code TEXT PRIMARY KEY,
                 description TEXT NOT NULL,
                 description_fr TEXT);
                 
insert into HYDRO.grades (code, description) values 
('A', 'Excellent'), 
('B', 'Good'),
('C', 'Fair'),
('D', 'Poor'),
('E', 'Estimated'),
('N', 'Unusable'),
('R', 'Draw down recovery'),
('I', 'Ice'),
('U', 'Undefined'),
('S', 'Sensor issues'),
('Z', 'Unknown');

ALTER TABLE HYDRO.measurements_continuous
                 ADD CONSTRAINT fk_grade
                 FOREIGN KEY (grade)
                 REFERENCES HYDRO.grades(code)
                 ON DELETE CASCADE
                 ON UPDATE CASCADE;
                
ALTER TABLE HYDRO.calculated_daily
                 ADD CONSTRAINT fk_grade
                 FOREIGN KEY (grade)
                 REFERENCES HYDRO.grades(code)
                 ON DELETE CASCADE
                 ON UPDATE CASCADE;

CREATE OR REPLACE FUNCTION HYDRO.check_grade_exists_continuous()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM HYDRO.grades WHERE code = NEW.grade) THEN
        RAISE EXCEPTION 'Invalid grade code: %', NEW.grade;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER before_insert_or_update_grade_continuous
BEFORE INSERT OR UPDATE OF grade ON HYDRO.measurements_continuous
FOR EACH ROW
EXECUTE FUNCTION HYDRO.check_grade_exists_continuous();


CREATE OR REPLACE FUNCTION hydro.check_grade_exists_daily()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM hydro.grades WHERE code = NEW.grade) THEN
        RAISE EXCEPTION 'Invalid grade code: %', NEW.grade;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER before_insert_or_update_grade_daily
BEFORE INSERT OR UPDATE OF grade ON HYDRO.calculated_daily
FOR EACH ROW
EXECUTE FUNCTION HYDRO.check_grade_exists_daily();


CREATE TABLE if not exists HYDRO.approvals (
                 code TEXT PRIMARY KEY,
                 description TEXT NOT NULL,
                 description_fr TEXT);
                
               
INSERT INTO HYDRO.approvals
("code", "description") values
('A', 'Approved'),
('C', 'Work up complete: ready for review'),
('R', 'Reviewed, pending approval'),
('N', 'Not reviewed'),
('U', 'Undefined'),
('Z', 'Unknown');

ALTER TABLE HYDRO.measurements_continuous
                 ADD CONSTRAINT fk_approval
                 FOREIGN KEY (approval)
                 REFERENCES HYDRO.approvals(code)
                 ON DELETE CASCADE
                 ON UPDATE CASCADE;
                
ALTER TABLE HYDRO.calculated_daily
                 ADD CONSTRAINT fk_approval
                 FOREIGN KEY (approval)
                 REFERENCES HYDRO.approvals(code)
                 ON DELETE CASCADE
                 ON UPDATE CASCADE;

CREATE OR REPLACE FUNCTION hydro.check_approval_exists_continuous()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM hydro.approvals WHERE code = NEW.approval) THEN
        RAISE EXCEPTION 'Invalid approval code: %', NEW.approval;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER before_insert_or_update_approval_on_continuous
BEFORE INSERT OR UPDATE OF approval ON hydro.measurements_continuous
FOR EACH ROW
EXECUTE FUNCTION hydro.check_approval_exists_continuous();

CREATE OR REPLACE FUNCTION hydro.check_approval_exists_daily()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM hydro.approvals WHERE code = NEW.approval) THEN
        RAISE EXCEPTION 'Invalid approval code: %', NEW.approval;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER before_insert_or_update_approval_on_daily
BEFORE INSERT OR UPDATE OF approval ON hydro.calculated_daily
FOR EACH ROW
EXECUTE FUNCTION hydro.check_approval_exists_daily();

CREATE TABLE if not exists hydro.datum_list (
    datum_id INTEGER PRIMARY KEY,
    datum_name_en TEXT NOT NULL,
    datum_name_fr TEXT NOT NULL);
COMMENT ON TABLE hydro.datum_list IS 'Holds datum ids (referenced in the table datum_conversions) and their corresponding names in french and english. Taken directly from the datum list provided by HYDAT. Non-hydat datums can be added with datum_id beginning at 1000.';

CREATE TABLE if not exists hydro.datum_conversions (
                 conversion_id SERIAL PRIMARY KEY,
                 location_id INTEGER NOT NULL,
                 datum_id_from INTEGER NOT NULL REFERENCES hydro.datum_list (datum_id),
                 datum_id_to INTEGER NOT NULL REFERENCES hydro.datum_list (datum_id),
                 conversion_m NUMERIC NOT NULL,
                 current BOOLEAN NOT NULL,
                 UNIQUE (location_id, datum_id_to, current));
                
COMMENT ON TABLE hydro.datum_conversions IS 'Holds vertical datum conversions in meters, as well as identifying the most recent conversion for the timeseries.';
COMMENT ON COLUMN hydro.datum_conversions.conversion_id IS 'Integer autoincrement column uniquely identifying the conversion.';

   
COMMENT ON COLUMN hydro.datum_conversions.datum_id_from IS 'The datum_id (matching an entry in table datum_list) from which the conversion value is from. Datum_id 10 is equal to the station assumed datum (station 0 relative to some arbitrary local benchmark).';
COMMENT ON COLUMN hydro.datum_conversions.datum_id_to IS 'The datum_id (matching an entry in table datum_list) from which the conversion value is to.';
COMMENT ON COLUMN hydro.datum_conversions.conversion_m IS 'The elevation offset in meters to apply if transforming elevation values from the datum_id_from to the datum_id_to.';
COMMENT ON COLUMN hydro.datum_conversions.current IS 'TRUE means that the conversion is the most up-to-date in the database. Only one conversion_id can be current for each location.';

CREATE TABLE if not exists hydro.locations (
                 location_id SERIAL PRIMARY KEY,
                 location TEXT UNIQUE NOT NULL,
                 name TEXT UNIQUE NOT NULL,
                 name_fr text UNIQUE ,
                 latitude NUMERIC NOT NULL,
                 longitude NUMERIC NOT null,
                 contact TEXT,
                 geom_id INTEGER NOT NULL,
                 note text,
                 visibility_public TEXT NOT NULL CHECK(visibility_public IN ('exact', 'region', 'jitter')) DEFAULT 'exact',
                 share_with INTEGER[] NOT NULL DEFAULT '{1}',
                 owner INTEGER DEFAULT NULL REFERENCES hydro.owners_contributors (owner_contributor_id) ON DELETE SET NULL ON UPDATE CASCADE
                 );
                
COMMENT ON COLUMN hydro.locations.visibility_public IS 'Visibility of the location on the map. Exact means the location is to be shown exactly where it is. Region means the location is to be shown generally with a region. Jitter means the location is shown at a random location within a toroid of inner/outer radius 2, 5 km around the exact point location. This column does not apply if column public is FALSE.';
COMMENT ON COLUMN hydro.locations.share_with IS 'The user group which is allowed to see this location and any data linked to it. NULL means the location is public.';
COMMENT ON TABLE hydro.locations IS 'Holds location information, including the location name, latitude, longitude, and contact information. The geom_id is a reference to the vectors table, which holds the geometry for the location. Visibility is a flag to indicate how the location should be displayed on the map, if it is shared. Share_with is an array of user groups that are allowed to see the location and any data linked to it.';

CREATE TABLE if not exists hydro.networks (
                 network_id SERIAL PRIMARY KEY,
                 name TEXT UNIQUE NOT NULL,
                 name_fr TEXT UNIQUE,
                 description TEXT NOT NULL,
                 description_fr TEXT,
                 type TEXT NOT NULL CHECK(type IN ('research', 'monitoring', 'other'))
                 );
INSERT INTO hydro.networks (name, description, type) values
('Canada Yukon Hydrometric Network', 'Monitoring of large water bodies and rivers in Yukon and surrounding jurisdictions.', 'monitoring'),
('ECCC Meteorology Network', 'Monitoring of meteorological conditions, largely at airports.', 'monitoring'),
('Small Stream Network', 'Monitoring of smaller waterbodies and rivers/streams in Yukon.', 'monitoring'),
('Snow Survey Network', 'Monitoring of snow pack conditions in Yukon and surrounding jursidictions.', 'monitoring'),
('National Streamflow Network (US)', 'Monitoring of large stream conditions at sites within Alaska.', 'monitoring'),
('Yukon Observational Well Network', 'Monitoring of groundwater conditions at dedicated and adopted wells in Yukon.', 'monitoring'),
('Highway Observation Network', 'Monitoring of water quality (chemical) parameters at background and disturbance sites, often linked to water use licences.', 'monitoring'),
('Yukon Water Quality Network - Water Licence Data', 'Monitoring of water quality parameters at sites subject to a water use licence.', 'monitoring'),
('Yukon Water Quality Network - Groundwater Monitoring', 'Monitoring of background ground water quality parameters.', 'monitoring'),
('Yukon Water Quality Network - Surface Water Monitoring', 'Monitoring of background surface water quality parameters.', 'monitoring');

CREATE TABLE if not exists hydro.locations_networks (
     network_id INTEGER NOT NULL REFERENCES hydro.networks (network_id),
     location_id INTEGER NOT NULL REFERENCES hydro.locations (location_id),
     UNIQUE (network_id, location_id));

CREATE TABLE if not exists hydro.projects (
                 project_id SERIAL PRIMARY KEY,
                 name TEXT UNIQUE NOT NULL,
                 name_fr TEXT UNIQUE,
                 description TEXT NOT NULL,
                 description_fr TEXT,
                 type TEXT NOT NULL CHECK(type IN ('research', 'monitoring', 'other', 'incident response'))
                 );
                
CREATE TABLE if not exists hydro.locations_projects (
                 project_id INTEGER NOT NULL REFERENCES hydro.projects (project_id),
                 location_id INTEGER NOT NULL REFERENCES hydro.locations (location_id),
                 UNIQUE (project_id, location_id));          
                
CREATE TABLE if not exists hydro.document_types (
                 document_type_id SERIAL PRIMARY KEY,
                 document_type_en TEXT NOT NULL UNIQUE,
                 document_type_fr TEXT NOT NULL UNIQUE,
                 description_en TEXT,
                 description_fr TEXT,
                 share_with INTEGER[] NOT NULL DEFAULT '{1}',
                 owner INTEGER DEFAULT NULL REFERENCES hydro.owners_contributors (owner_contributor_id) ON DELETE SET NULL ON UPDATE CASCADE,
                 contributor INTEGER DEFAULT NULL REFERENCES hydro.owners_contributors (owner_contributor_id) ON DELETE SET NULL ON UPDATE CASCADE
                 );
                
CREATE TABLE if not exists hydro.documents (
                 document_id SERIAL PRIMARY KEY,
                 name TEXT UNIQUE NOT NULL,
                 type INTEGER NOT NULL,
                 has_points BOOLEAN NOT NULL DEFAULT FALSE,
                 has_lines BOOLEAN NOT NULL DEFAULT FALSE,
                 has_polygons BOOLEAN NOT NULL DEFAULT FALSE,
                 authors TEXT[],
                 url TEXT,
                 publish_date DATE,
                 description TEXT NOT NULL,
                 format TEXT NOT NULL,
                 document BYTEA NOT NULL,
                 public BOOLEAN NOT NULL DEFAULT FALSE,
                 FOREIGN KEY (type) REFERENCES hydro.document_types(document_type_id) ON UPDATE CASCADE ON DELETE CASCADE);
    

COMMENT ON TABLE hydro.documents IS 'Holds documents and metadata associated with each document. Each document can be associated with one or more location, line, or polygon, or all three.';
COMMENT ON COLUMN hydro.documents.type IS 'One of thesis, report, well log, conference paper, poster, journal article, map, graph, protocol, grading scheme, metadata, other';
COMMENT ON COLUMN hydro.documents.has_points IS 'Flag to indicate that the document_spatial has a point entry for this document.';
COMMENT ON COLUMN hydro.documents.authors IS 'An *array* of one or more authors.';

CREATE TABLE if not exists hydro.timeseries (
                 timeseries_id SERIAL PRIMARY KEY,
                 location TEXT NOT NULL,
                 parameter INTEGER NOT NULL,
                 param_type INTEGER NOT NULL,
                 category TEXT NOT NULL CHECK(category IN ('discrete', 'continuous')),
                 period_type TEXT NOT NULL CHECK(period_type IN ('instantaneous', 'sum', 'mean', 'median', 'min', 'max', '(min+max)/2')),
                 record_rate TEXT NOT NULL,
                 z NUMERIC,
                 start_datetime TIMESTAMP WITH TIME ZONE,
                 end_datetime TIMESTAMP WITH TIME ZONE,
                 last_new_data TIMESTAMP WITH TIME ZONE,
                 last_daily_calculation TIMESTAMP WITH TIME ZONE,
                 last_synchronize TIMESTAMP WITH TIME ZONE,
                 network TEXT,
                 public BOOLEAN NOT NULL,
                 public_delay INTERVAL,
                 source_fx TEXT,
                 source_fx_args TEXT,
                 active BOOLEAN NOT NULL DEFAULT TRUE,
                 note TEXT,
                 share_with INTEGER[] NOT NULL DEFAULT '{1}',
                 owner INTEGER DEFAULT NULL REFERENCES hydro.owners_contributors (owner_contributor_id) ON DELETE SET NULL ON UPDATE CASCADE,
                 UNIQUE (location, parameter, category, period_type, param_type, record_rate, z),
                 CONSTRAINT check_record_rate_constraints
                     CHECK (
                     (category = 'discrete' AND record_rate IS NULL) OR
                     (category = 'continuous' AND record_rate IN ('< 1 day', '1 day', '1 week', '4 weeks', '1 month', 'year'))
                     )
                 );

COMMENT ON TABLE hydro.timeseries IS 'Provides a record of every timeseries in the database. Each timeseries is unique by its combination of location, parameter, param_type, category (continuous or discrete), period_type, record_rate, and z (elevation).Continuous data is data gathered at regular and usually frequent intervals, while discrete data includes infrequent, often manual measurements of values such as snow depth or dissolved element parameters.';
COMMENT ON COLUMN hydro.timeseries.active IS 'Defines if the timeseries should or should not be added to or back-corrected by various AquaCache package functions.';
COMMENT ON COLUMN hydro.timeseries.z IS 'Elevation of the measurement station, in meters. Used for things like thermistor strings, wind towers, or forecast climate parameters at different heights. Z elevations should be taken in the context of the location''s assigned elevation and datum.';
COMMENT ON COLUMN hydro.timeseries.timeseries_id IS 'Autoincrements each time a timeseries is added. NOTE that timeseries should only be added using the R function addACTimeseries.';
COMMENT ON COLUMN hydro.timeseries.location IS 'Matches to the locations table.';
COMMENT ON COLUMN hydro.timeseries.category IS 'Discrete or continuous. Continuous data is data gathered at regular and frequent intervals (usually max 1 day), while discrete data includes infrequent, often manual measurements of values such as snow depth or dissolved element parametes.';
COMMENT ON COLUMN hydro.timeseries.period_type IS 'One of instantaneous, sum, mean, median, min, max, or (min+max)/2. This last value is used for the ''daily mean'' temperatures at met stations which are in fact not true mean temps.';
COMMENT ON COLUMN hydro.timeseries.record_rate IS 'For continuous timeseries, one of < 1 day, 1 day, 1 week, 4 weeks, 1 month, year. For discrete timeseries, NULL.';
COMMENT ON COLUMN hydro.timeseries.start_datetime IS 'First data point for the timeseries.';
COMMENT ON COLUMN hydro.timeseries.end_datetime IS 'Last data point for the timeseries.';
COMMENT ON COLUMN hydro.timeseries.last_new_data IS 'Time at which data was last appended to the timeseries';
COMMENT ON COLUMN hydro.timeseries.last_daily_calculation IS 'Time at which daily means were calculated using function calculate_stats. Not used for discrete timeseries.';
COMMENT ON COLUMN hydro.timeseries.last_synchronize IS 'Time at which the timeseries was cross-checked against values held by the remote or partner database; the local store should have been updated to reflect the remote.';
COMMENT ON COLUMN hydro.timeseries.public_delay IS 'For public = TRUE stations, an option delay with which to serve the data to the public.';
COMMENT ON COLUMN hydro.timeseries.source_fx IS 'Function (from the R package AquaCache) to use for incorporation of new data.';
COMMENT ON COLUMN hydro.timeseries.source_fx_args IS 'Optional arguments to pass to the source function. See notes in function addACTimeseries for usage.';

CREATE TABLE hydro.parameters (
               param_code SERIAL PRIMARY KEY,
               param_name TEXT UNIQUE NOT NULL,
               unit TEXT UNIQUE NOT NULL,
               param_name_fr TEXT UNIQUE NOT NULL,
               "group" TEXT NOT NULL,
               group_fr TEXT NOT NULL,
               sub_group TEXT,
               sub_group_fr TEXT,
               description text,
               description_fr TEXT,
               plot_default_y_orientation TEXT NOT NULL CHECK(plot_default_y_orientation IN ('normal', 'inverted')),
                 plot_default_floor NUMERIC,
                 plot_default_ceiling NUMERIC);

CREATE TABLE hydro.param_types (
               param_type_code SERIAL PRIMARY KEY,
               param_type TEXT UNIQUE NOT NULL,
               param_type_fr TEXT UNIQUE NOT NULL,
               description TEXT,
               description_fr TEXT);
              
CREATE TABLE if not exists hydro.extrema (
                 timeseries_id INTEGER PRIMARY KEY,
                 agency TEXT NOT NULL,
                 year NUMERIC NOT NULL,
                 date DATE NOT NULL,
                 value NUMERIC NOT NULL,
                 period_type TEXT NOT NULL CHECK(period_type IN ('instantaneous', '1-day', '2-day', '3-day', '4-day', '5-day', '6-day', '7-day', 'monthly', 'yearly')),
                 condition TEXT NOT NULL CHECK(condition IN ('open water', 'break-up', 'freeze-up', 'winter')),
                 extrema TEXT NOT NULL CHECK(extrema IN ('minimum', 'maximum')),
                 notes TEXT,
                 deemed_primary BOOLEAN NOT NULL,
                 UNIQUE (timeseries_id, agency, year, period_type, condition, extrema));              

  COMMENT ON TABLE hydro.extrema IS 'Holds vetted information about extrema specific to each time-series. Can be used for calculating return periods. Entries unique on timeseries_id, agency, year, period_type, condition, extrema, which allows for multiple different types of extrema from different authorities (agencies) for each timeseries.';
  COMMENT ON COLUMN hydro.extrema.agency IS 'The agency (authority) which calculated the extreme value. Ex: Water Resources Branch, Water Survey of Canada, Tetra Tech, etc.';
  COMMENT ON COLUMN hydro.extrema.year IS 'The year for which each value is valid.';
  COMMENT ON COLUMN hydro.extrema.date IS 'The exact date on which the extreme value occured.';
  COMMENT ON COLUMN hydro.extrema.period_type IS 'One of instantaneous, 1-day, 2-day, 3-day, 4-day, 5-day, 6-day, 7-day, monthly, yearly. For example, a 1-day max flow is the maximum 1-day averaged flow for the year; instantaneous max flow is the greatest value single data point recorded for the year.';
  COMMENT ON COLUMN hydro.extrema.condition IS 'One of open water, break-up, freeze-up, winter. Any given timeseries can have one value of each for each year.';
  COMMENT ON COLUMN hydro.extrema.extrema IS 'One of minimum or maximum. Necessary along with other descriptive columns to fully describe what each value represents.';
  COMMENT ON COLUMN hydro.extrema.deemed_primary IS 'If TRUE then the extrema value is the best (most reliable) value and should be used for most calculations and representations.';
  

CREATE TABLE if not exists hydro.thresholds (
                 timeseries_id INTEGER PRIMARY KEY,
                 high_advisory NUMERIC,
                 high_watch NUMERIC,
                 high_warning NUMERIC,
                 flood_minor NUMERIC,
                 flood_major NUMERIC,
                 high_first_human_impacts NUMERIC,
                 low_advisory NUMERIC,
                 low_watch NUMERIC,
                 low_warning NUMERIC,
                 low_first_human_impacts NUMERIC,
                 low_aquatic_life_impacts_minor NUMERIC,
                 low_aquatic_life_impacts_major NUMERIC,
                 high_aquatic_life_impacts_minor NUMERIC,
                 high_aquatic_life_impacts_major NUMERIC,
                 FSL NUMERIC,
                 LSL NUMERIC);                

  COMMENT ON TABLE hydro.thresholds IS 'Holds threshold values for a variety of things like streamflows, water levels, flood levels, aquatic life inpacts.';
  COMMENT ON COLUMN hydro.thresholds.high_advisory IS 'Value at which a high water advisory is to be issued.';
 COMMENT ON COLUMN hydro.thresholds.high_watch IS 'Value at which a high water watch is to be issued.';
  COMMENT ON COLUMN hydro.thresholds.high_warning IS 'Value at which a high water warning is to be issued.';
 COMMENT ON COLUMN hydro.thresholds.flood_minor IS 'Value at which a minor flood is to be declared.';
 COMMENT ON COLUMN hydro.thresholds.flood_major IS 'Value at which a major flood is to be declared.';
 COMMENT ON COLUMN hydro.thresholds.high_first_human_impacts IS 'High-side value at which first human impacts are known, such as impacts to navigation.';
 COMMENT ON COLUMN hydro.thresholds.low_first_human_impacts IS 'Low-side value at which first human impacts are known, such as impacts to navigation.';
 COMMENT ON COLUMN hydro.thresholds.low_advisory IS 'Value at which a low water advisory is to be issued.';
 COMMENT ON COLUMN hydro.thresholds.low_watch IS 'Value at which a low water watch is to be issued.';
 COMMENT ON COLUMN hydro.thresholds.low_warning IS 'Value at which a low water warning is to be issued.';
 COMMENT ON COLUMN hydro.thresholds.low_aquatic_life_impacts_minor IS 'Low-side (water temp, level, flow) minor impact threshold to aquatic life.';
 COMMENT ON COLUMN hydro.thresholds.low_aquatic_life_impacts_major IS 'Low-side (water temp, level, flow) major impact threshold to aquatic life.';
 COMMENT ON COLUMN hydro.thresholds.high_aquatic_life_impacts_minor IS 'High-side (water temp, level, flow) minor impact threshold to aquatic life.';
  COMMENT ON COLUMN hydro.thresholds.high_aquatic_life_impacts_major IS 'High-side (water temp, level, flow) major impact threshold to aquatic life.';
COMMENT ON COLUMN hydro.thresholds.fsl IS 'Full supply level (as per water use licence for control structure operations)';
COMMENT ON COLUMN hydro.thresholds.lsl IS 'Low supply level (as per water use licence for control structure operations)';
 
CREATE TABLE if not exists hydro.internal_status (
                 event TEXT NOT NULL,
                 value TIMESTAMP WITH TIME ZONE,
                 PRIMARY KEY (event));
                
COMMENT ON TABLE hydro.internal_status IS 'Holds information about when a certain operation took place on the database using the R functions in the AquaCache package.';

insert into hydro.internal_status (event, value) values
('HYDAT_version', NULL),
('last_new_continuous', NULL),
('last_new_discrete', NULL),
('last_update_daily', NULL),
('last_sync', NULL),
('last_sync_discrete', NULL),
('last_new_rasters', NULL),
('last_new_vectors', NULL),
('last_vacuum', NULL),
('last_new_images', NULL);


CREATE TABLE if not exists hydro.settings (
                 source_fx TEXT NOT NULL,
                 parameter INTEGER NOT NULL,
                 period_type TEXT NOT NULL,
                 record_rate TEXT,
                 remote_param_name TEXT NOT NULL,
                 UNIQUE (source_fx, parameter, period_type, record_rate));


COMMENT ON TABLE hydro.settings IS 'This table stores the name of functions used to pull in new data, the parameter with which they are associated, and the remote parameter name to pass to the source function for each function and database parameter name.';
  COMMENT ON COLUMN hydro.settings.source_fx IS 'The R function (from the AquaCache package) to use for fetching data.';
  COMMENT ON COLUMN hydro.settings.parameter IS 'Parameter integer codes used in the timeseries table.';
 COMMENT ON COLUMN hydro.settings.remote_param_name IS 'The parameter name or code to pass to the parameter param_code of the R function specified in source_fx.';
 
--- see lines AquaCacheInit.R lines 689 through 715 
-- they are populating data, from a file.  This should be a secondary step, ideally the migration
-- should only establish database objects, and fixtures, like lookup tables.

CREATE TABLE if not exists hydro.vectors (
               geom_id SERIAL PRIMARY KEY,
               geom_type TEXT NOT NULL CHECK(geom_type IN ('ST_Point', 'ST_MultiPoint', 'ST_LineString', 'ST_MultiLineString', 'ST_Polygon', 'ST_MultiPolygon')),
               layer_name TEXT NOT NULL,
               feature_name TEXT NOT NULL,
               description TEXT,
               geom GEOMETRY(Geometry, 4269) NOT NULL,
               CONSTRAINT enforce_dims_geom CHECK (st_ndims(geom) = 2),
               CONSTRAINT enforce_srid_geom CHECK (st_srid(geom) = 4269),
               CONSTRAINT enforce_valid_geom CHECK (st_isvalid(geom)),
               UNIQUE (layer_name, feature_name, geom_type)
               );
              
  COMMENT ON TABLE hydro.vectors IS 'Holds points, lines, or polygons as geometry objects that can be references by other tables. For example, the locations table references a geom_id for each location. Retrieve objects from this table using function AquaCache::fetchVector, insert them using AquaCache::insertACVector.';
  COMMENT ON COLUMN hydro.vectors.geom IS 'Enforces epsg:4269 (NAD83).';
  COMMENT ON COLUMN hydro.vectors.layer_name IS 'Non-optional descriptive name for the layer.';
  COMMENT ON COLUMN hydro.vectors.feature_name IS 'Non-optional descriptive name for the feature.';
  COMMENT ON COLUMN hydro.vectors.description IS 'Optional but highly recommended long-form description of the geometry object.';
  COMMENT ON COLUMN hydro.vectors.geom_type IS '*DO NOT TOUCH* Auto-populated by trigger based on the geometry type for each entry.';


CREATE OR REPLACE FUNCTION hydro.update_geom_type()
RETURNS TRIGGER AS $$
  BEGIN
NEW.geom_type := ST_GeometryType(NEW.geom);
RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_geom_type_trigger
BEFORE INSERT OR UPDATE ON hydro.vectors
FOR EACH ROW
EXECUTE FUNCTION hydro.update_geom_type();

CREATE INDEX geometry_idx ON hydro.vectors USING GIST (geom);

CREATE TABLE hydro.documents_spatial (
  document_id INT REFERENCES hydro.documents(document_id),
  geom_id INT REFERENCES hydro.vectors(geom_id),
  PRIMARY KEY (document_id, geom_id)
);

CREATE TABLE IF NOT EXISTS hydro.raster_series_index (
                 raster_series_id SERIAL PRIMARY KEY,
                 model TEXT NOT NULL,
                 type TEXT NOT NULL CHECK(type IN ('reanalysis', 'forecast')),
                 parameter TEXT NOT NULL,
                 param_description TEXT,
                 start_datetime TIMESTAMP WITH TIME ZONE NOT NULL,
                 end_datetime TIMESTAMP WITH TIME ZONE NOT NULL,
                 last_new_raster TIMESTAMP WITH TIME ZONE NOT NULL,
                 last_issue TIMESTAMP WITH TIME ZONE,
                 public BOOLEAN NOT NULL,
                 public_delay INTERVAL,
                 source_fx TEXT,
                 source_fx_args TEXT,
                 active BOOLEAN NOT NULL DEFAULT TRUE,
                 UNIQUE (model, parameter));
                
COMMENT ON TABLE hydro.raster_series_index IS 'Holds metadata about raster series, such as reanalysis or forecast rasters. ';
COMMENT ON COLUMN hydro.raster_series_index.end_datetime IS 'For rasters that have a valid_from and valid_to time, this is the valid_from of the latest raster in the database.';
COMMENT ON COLUMN hydro.raster_series_index.active IS 'Defines if the raster series should or should not be imported.';
             

ALTER TABLE hydro.settings 
                 ADD CONSTRAINT fk_parameter
                 FOREIGN KEY (parameter)
                 REFERENCES hydro.parameters(param_code)
                 ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE hydro.locations
  ADD CONSTRAINT fk_geom_id
  FOREIGN KEY (geom_id)
  REFERENCES hydro.vectors(geom_id)
                 ON UPDATE CASCADE ON DELETE CASCADE;

-- sql in original R script does not define a location_id in the locations table                
--ALTER TABLE hydro.timeseries
--  ADD CONSTRAINT fk_location_id
--  FOREIGN KEY (location_id)
--  REFERENCES hydro.locations(location_id)
--                 ON UPDATE CASCADE ON DELETE CASCADE;
--                