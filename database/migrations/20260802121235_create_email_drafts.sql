-- Migration: 20260802121235_create_email_drafts
-- Created:   2026-08-02 12:12:35 UTC
-- Author:    MADHUSOODANAN
--
-- Purpose:
--   Proposed replies. Separate from analyses because a draft can be
--   regenerated, edited, approved, or discarded independently of the
--   classification that prompted it.
--
--   Versioning is keyed on (analysis_id, draft_version) so a deliberate
--   regeneration is legitimate, while idempotency_key stops a retry from
--   creating a second version 1.
--
--   There is no 'sent' status. FR-13 says the system does not send replies, and
--   a status that cannot occur makes operational reports dishonest.
--
-- The BEGIN/COMMIT block is required. database/apply-migrations.sh inserts the
-- schema_migrations row just before the COMMIT, so the schema change and the
-- record of it commit together — or neither does.
--
-- Once applied anywhere other than a local database, treat this file as
-- immutable — editing it will not re-run it. Correct mistakes with a new
-- migration.

BEGIN;

CREATE TYPE email_draft_status AS ENUM (
    'generated',
    'reviewed',
    'approved',
    'edited',
    'discarded'
);

CREATE TABLE email_drafts(
    id UUID PRIMARY KEY,
    seq bigserial UNIQUE NOT NULL,
    processing_run_id UUID NOT NULL,
    analysis_id UUID NOT NULL,
    email_message_id UUID NOT NULL,
    draft_version integer NOT NULL,      -- 1, 2, 3, ...
    draft_subject text NOT NULL,
    draft_body text NOT NULL,
    status email_draft_status NOT NULL DEFAULT 'generated',
    model_name text NOT NULL,            -- pinned version, never an alias (ADR-002)
    prompt_version text NOT NULL,
    input_hash text NOT NULL,
    idempotency_key text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    -- Both denormalized parents are pinned to the analysis, and the analysis is
    -- itself pinned to its run and email, so a draft cannot straddle two chains.
    FOREIGN KEY (analysis_id, processing_run_id)
        REFERENCES email_analyses(id, processing_run_id),
    FOREIGN KEY (analysis_id, email_message_id)
        REFERENCES email_analyses(id, email_message_id),

    UNIQUE(analysis_id, draft_version),
    UNIQUE(idempotency_key),

    CONSTRAINT email_drafts_draft_version_check
        CHECK (draft_version >= 1)
);

CREATE INDEX email_drafts_run_idx
    ON email_drafts(processing_run_id);

CREATE INDEX email_drafts_status_created_idx
    ON email_drafts(status, created_at DESC);

COMMIT;
