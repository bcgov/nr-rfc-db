CREATE TABLE if not exists sub_basins (
                 sub_basin TEXT PRIMARY KEY,
                 polygon geometry(Polygon, 4269) NOT NULL,
                 CONSTRAINT enforce_dims_geom2 CHECK (st_ndims(polygon) = 2),
                 CONSTRAINT enforce_geotype_geom2 CHECK (geometrytype(polygon) = 'POLYGON'::text),
                 CONSTRAINT enforce_srid_geom2 CHECK (st_srid(polygon) = 4269),
                 CONSTRAINT enforce_valid_geom2 CHECK (st_isvalid(polygon)));

                 