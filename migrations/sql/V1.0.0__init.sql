
DO $$
BEGIN
  IF current_database() <> 'rfc_db_1' THEN
    RAISE EXCEPTION 'Refusing to run migrations on %; expected rfc_db_1', current_database();
  END IF;
END $$;

CREATE EXTENSION IF NOT EXISTS postgis;
