#!/bin/sh
set -eu

# Runs only when the PostgreSQL volume is initialised for the first time.
# Passwords are passed as psql variables so they are quoted as SQL literals and
# never interpolated into the SQL source by the shell.
psql \
  --set=ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" \
  --dbname postgres \
  --set=cms_password="$CMS_DB_PASSWORD" \
  --set=app_password="$APP_DB_PASSWORD" <<'SQL'
SELECT format('CREATE ROLE campus_cms LOGIN PASSWORD %L', :'cms_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'campus_cms')\gexec

SELECT format('CREATE ROLE campus_app LOGIN PASSWORD %L', :'app_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'campus_app')\gexec

SELECT 'CREATE DATABASE campus_cms_dev OWNER campus_cms'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'campus_cms_dev')\gexec

SELECT 'CREATE DATABASE campus_app_dev OWNER campus_app'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'campus_app_dev')\gexec

-- Nobody may connect by default; each role reaches only its own database
-- (AGENTS.md §2.3).
REVOKE CONNECT ON DATABASE campus_cms_dev FROM PUBLIC;
REVOKE CONNECT ON DATABASE campus_app_dev FROM PUBLIC;
GRANT CONNECT ON DATABASE campus_cms_dev TO campus_cms;
GRANT CONNECT ON DATABASE campus_app_dev TO campus_app;
SQL

# Lock the public schema inside each database down to its owner.
for pair in campus_cms_dev:campus_cms campus_app_dev:campus_app; do
  db=${pair%%:*}
  owner=${pair#*:}
  psql \
    --set=ON_ERROR_STOP=1 \
    --username "$POSTGRES_USER" \
    --dbname "$db" \
    --set=owner="$owner" <<'SQL'
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO :"owner";
SQL
done
