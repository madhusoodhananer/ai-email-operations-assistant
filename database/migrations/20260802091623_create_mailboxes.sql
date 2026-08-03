-- Migration: 20260802091623_create_mailboxes
-- Created:   2026-08-02 09:16:23 UTC
-- Author:    MADHUSOODANAN
--
-- Purpose:
--   The configured inbound mailboxes. Foundation table — email_messages and
--   everything downstream hangs off this.
--
-- The BEGIN/COMMIT block is required. database/apply-migrations.sh inserts the
-- schema_migrations row just before the COMMIT, so the schema change and the
-- record of it commit together — or neither does.
--
-- Once applied anywhere other than a local database, treat this file as
-- immutable — editing it will not re-run it. Correct mistakes with a new
-- migration.

BEGIN;

CREATE TABLE mailboxes(
    id UUID PRIMARY KEY,
    seq bigserial UNIQUE NOT NULL,
    provider text NOT NULL,      -- e.g. 'gmail', 'outlook', 'yahoo'
    address text NOT NULL,       -- e.g. 'sales@company.com', 'support@company.com'
    display_name text NOT NULL,  -- e.g. 'Sales', 'Support'
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    UNIQUE(provider, address)
);

COMMIT;
