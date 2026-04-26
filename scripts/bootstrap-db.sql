-- =============================================================================
-- Bootstrap PostgreSQL service account for IAM authentication
--
-- Run once per new RDS instance (stage, prod, ...) AFTER the RDS instance has
-- been created by terraform. Connect as the master user (`dbadmin`) and exec
-- this file via psql.
--
-- IAM auth requires three things on the database side:
--   1. IAM auth enabled on the RDS instance       (terraform: iam_database_authentication_enabled)
--   2. The PostgreSQL user exists                 (this script creates it)
--   3. The user is granted the rds_iam role       (this script grants it)
--
-- Without #2 and #3, every connection attempt returns:
--   FATAL: password authentication failed for user "vocuone_service_user"
--
-- Idempotent: re-running this script is safe; it skips existing objects.
-- =============================================================================

-- The application database name (matches db_name in terraform.tfvars)
\set app_db   appdb

-- The IAM-auth user the Spring Boot app connects as (matches app_db_username)
\set app_user vocuone_service_user

-- ---------------------------------------------------------------------------
-- 1. Create the service-account user. No password — IAM tokens handle auth.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'vocuone_service_user') THEN
    CREATE USER vocuone_service_user;
    RAISE NOTICE 'Created user vocuone_service_user';
  ELSE
    RAISE NOTICE 'User vocuone_service_user already exists';
  END IF;
END
$$;

-- ---------------------------------------------------------------------------
-- 2. Grant the rds_iam role so RDS validates IAM-issued auth tokens.
--    Without this, IAM tokens are rejected as plain passwords.
-- ---------------------------------------------------------------------------
GRANT rds_iam TO vocuone_service_user;

-- ---------------------------------------------------------------------------
-- 3. Database-level access — connect to appdb.
-- ---------------------------------------------------------------------------
GRANT CONNECT ON DATABASE appdb TO vocuone_service_user;

-- ---------------------------------------------------------------------------
-- 4. Schema-level access — read/write objects in `public`.
--    ALTER DEFAULT PRIVILEGES extends the grant to objects created later
--    (e.g. when Flyway/Hibernate runs migrations).
-- ---------------------------------------------------------------------------
\connect appdb

GRANT USAGE, CREATE ON SCHEMA public TO vocuone_service_user;

GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA public TO vocuone_service_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO vocuone_service_user;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO vocuone_service_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL PRIVILEGES ON TABLES    TO vocuone_service_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL PRIVILEGES ON SEQUENCES TO vocuone_service_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL PRIVILEGES ON FUNCTIONS TO vocuone_service_user;

-- ---------------------------------------------------------------------------
-- 5. Verify — should show the user is a member of rds_iam.
-- ---------------------------------------------------------------------------
SELECT
  r.rolname           AS role,
  r.rolcanlogin       AS can_login,
  ARRAY(
    SELECT b.rolname
    FROM pg_auth_members m
    JOIN pg_roles b ON m.roleid = b.oid
    WHERE m.member = r.oid
  ) AS member_of
FROM pg_roles r
WHERE r.rolname = 'vocuone_service_user';

-- Expected output:
--          role          | can_login | member_of
-- -----------------------+-----------+-----------
--  vocuone_service_user  | t         | {rds_iam}
