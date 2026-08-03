#!/usr/bin/env bash
# Create the role + databases used by the app and the test suite.
# Run AFTER Postgres is installed and running (brew services start postgresql@16).
set -euo pipefail

DB_USER="${DB_USER:-calendar}"
DB_PASS="${DB_PASS:-calendar}"

# Connect to the default 'postgres' db as the current OS user (brew default).
psql postgres <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${DB_USER}') THEN
    CREATE ROLE ${DB_USER} LOGIN PASSWORD '${DB_PASS}';
  END IF;
END
\$\$;
SQL

createdb -O "${DB_USER}" calendar 2>/dev/null && echo "created db: calendar" || echo "db calendar already exists"
createdb -O "${DB_USER}" calendar_test 2>/dev/null && echo "created db: calendar_test" || echo "db calendar_test already exists"

echo "Done. Now run: alembic upgrade head"
