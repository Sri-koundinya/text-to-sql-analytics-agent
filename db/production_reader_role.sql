-- Run as the managed database's administrator after the schema has been created.
-- Example:
-- psql "$env:DATABASE_URL" -v reader_password='use-a-long-random-password' -f .\db\production_reader_role.sql
-- Never commit the actual password.

\if :{?reader_password}
\else
  \echo 'Pass -v reader_password=... when running this script.'
  \quit
\endif

ALTER ROLE analytics_reader WITH LOGIN PASSWORD :'reader_password' NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
REVOKE ALL ON SCHEMA public FROM analytics_reader;
GRANT USAGE ON SCHEMA public TO analytics_reader;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM analytics_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO analytics_reader;

