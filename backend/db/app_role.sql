-- The restricted database role the app switches into for each request.
--
-- Row-level security policies (in db/structure.sql) limit this role to one
-- business's rows. This file says which tables it may touch at all, and how.
-- Anything not granted here is refused by Postgres, including:
--   * the sessions table (login tokens are checked before a request switches roles)
--   * UPDATE and DELETE on messages and activities, which are append-only
--
-- It's applied after every migrate and schema load (lib/tasks/app_role.rake)
-- and before the test suite runs. Rails leaves privileges out of
-- structure.sql, so this file is their source of truth.
--
-- When you add a table that holds business data, add its grant here and give
-- it a policy in its migration. test/models/row_level_security_test.rb fails
-- if a table with a business_id column has no policy.

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'frontdesk_app') THEN
    CREATE ROLE frontdesk_app NOLOGIN NOBYPASSRLS;
  END IF;
END
$$;

-- Lets the user the app connects as switch into the restricted role.
GRANT frontdesk_app TO CURRENT_USER;

GRANT USAGE ON SCHEMA public TO frontdesk_app;
GRANT EXECUTE ON FUNCTION current_business_id() TO frontdesk_app;

GRANT SELECT, UPDATE ON businesses TO frontdesk_app;
GRANT SELECT ON users TO frontdesk_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON memberships, leads, conversations, appointments TO frontdesk_app;
GRANT SELECT, INSERT, UPDATE ON intake_keys, invitations TO frontdesk_app;
GRANT SELECT, INSERT ON messages, activities TO frontdesk_app;

-- WhatsApp
GRANT SELECT, UPDATE ON channel_accounts TO frontdesk_app;
GRANT SELECT, INSERT, UPDATE ON inbound_events, outbound_messages TO frontdesk_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON assistant_sessions TO frontdesk_app;

-- Notes are append-only; follow-ups are completed/rescheduled, never deleted.
GRANT SELECT, INSERT ON notes TO frontdesk_app;
GRANT SELECT, INSERT, UPDATE ON follow_ups TO frontdesk_app;
