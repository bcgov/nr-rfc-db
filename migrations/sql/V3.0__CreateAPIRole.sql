
-- Role for the API to connect
CREATE ROLE authenticator NOINHERIT LOGIN PASSWORD 'password';

-- Role for anonymous requests
CREATE ROLE web_anon NOLOGIN;
GRANT web_anon TO authenticator;

-- Replace 'public' if your data is in a different schema
GRANT USAGE ON SCHEMA asp TO web_anon;

-- Grant access to all current tables
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA asp TO web_anon;

-- (Optional) Grant access to future tables you might add
ALTER DEFAULT PRIVILEGES IN SCHEMA asp GRANT SELECT ON TABLES TO web_anon;