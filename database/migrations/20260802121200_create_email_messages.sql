-- Migration: 20260802121200_create_email_messages
-- Created:   2026-08-02 12:12:00 UTC
-- Author:    MADHUSOODANAN
--
-- Purpose:
--   The normalized inbound email. One row per source message regardless of how
--   many times the provider delivers it — the (provider, provider_message_id)
--   key is what makes webhook redelivery safe (ADR-003).
--
--   Processing state deliberately does not live here. An email can be processed
--   more than once, so run state belongs to processing_runs (ADR-004).
--
-- The BEGIN/COMMIT block is required. database/apply-migrations.sh inserts the
-- schema_migrations row just before the COMMIT, so the schema change and the
-- record of it commit together — or neither does.
--
-- Once applied anywhere other than a local database, treat this file as
-- immutable — editing it will not re-run it. Correct mistakes with a new
-- migration.

BEGIN;

CREATE TYPE email_ingestion_status AS ENUM (
    'received',
    'ignored',
    'quarantined'
);

CREATE TABLE email_messages(
    id UUID PRIMARY KEY,
    seq bigserial UNIQUE NOT NULL,
    mailbox_id UUID NOT NULL REFERENCES mailboxes(id),
    provider text NOT NULL,              -- copied from the source for audit
    provider_message_id text NOT NULL,   -- stable id assigned by the provider
    thread_id text,
    from_email text NOT NULL,
    from_name text,
    to_emails text[] NOT NULL,
    cc_emails text[] NOT NULL DEFAULT '{}',
    subject text NOT NULL DEFAULT '',
    body_text text NOT NULL,             -- cleaned plain text; see data-model.md 14
    received_at timestamptz NOT NULL,    -- arrival at the provider, not at us
    has_attachments boolean NOT NULL DEFAULT false,
    ingestion_status email_ingestion_status NOT NULL DEFAULT 'received',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    UNIQUE(provider, provider_message_id)
);

CREATE INDEX email_messages_mailbox_received_idx
    ON email_messages(mailbox_id, received_at DESC);

CREATE INDEX email_messages_thread_id_idx
    ON email_messages(thread_id);

CREATE INDEX email_messages_from_email_idx
    ON email_messages(from_email);

COMMIT;
