-- Migration: 20260802121215_create_email_analyses
-- Created:   2026-08-02 12:12:15 UTC
-- Author:    MADHUSOODANAN
--
-- Purpose:
--   The validated classification and extraction result from the single model
--   call required by FR-4.
--
--   extracted_payload and raw_response are separate on purpose: the application
--   trusts only the validated payload. raw_response is evidence for debugging
--   and audit, not business data.
--
--   confidence_threshold records the value in force when the decision was made,
--   so a later change to CONFIDENCE_THRESHOLD does not rewrite history.
--
-- The BEGIN/COMMIT block is required. database/apply-migrations.sh inserts the
-- schema_migrations row just before the COMMIT, so the schema change and the
-- record of it commit together — or neither does.
--
-- Once applied anywhere other than a local database, treat this file as
-- immutable — editing it will not re-run it. Correct mistakes with a new
-- migration.

BEGIN;

CREATE TYPE analysis_priority AS ENUM (
    'low',
    'medium',
    'high',
    'critical'
);

CREATE TABLE email_analyses(
    id UUID PRIMARY KEY,
    seq bigserial UNIQUE NOT NULL,
    processing_run_id UUID NOT NULL,
    email_message_id UUID NOT NULL,
    category text NOT NULL,              -- text until the taxonomy is closed
    priority analysis_priority NOT NULL,
    confidence numeric(4,3) NOT NULL,
    confidence_threshold numeric(4,3) NOT NULL,
    summary text,
    recommended_action text,
    requires_draft boolean NOT NULL DEFAULT false,
    requires_manual_review boolean NOT NULL DEFAULT false,
    extracted_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    raw_response jsonb NOT NULL,
    model_name text NOT NULL,            -- pinned version, never an alias (ADR-002)
    prompt_version text NOT NULL,        -- e.g. email-classifier-v1.0
    schema_version text NOT NULL,
    input_hash text NOT NULL,            -- over the normalized input (ADR-003 3)
    idempotency_key text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),

    -- Composite parent reference. A single-column FK on each of these would
    -- only prove the run exists and the email exists — not that the run is a
    -- run *of that email*. This pins the analysis to one processing chain, and
    -- transitively guarantees both parents exist, so the single-column FKs are
    -- redundant and omitted.
    FOREIGN KEY (processing_run_id, email_message_id)
        REFERENCES processing_runs(id, email_message_id),

    UNIQUE(processing_run_id),

    -- Targets for the composite foreign keys in routing_decisions, sales_leads,
    -- email_drafts, and manual_reviews. Redundant for uniqueness; required so
    -- those children can reference (id, processing_run_id) and
    -- (id, email_message_id) as a unit.
    UNIQUE(id, processing_run_id),
    UNIQUE(id, email_message_id),

    -- A workflow retry reuses the stored analysis instead of paying for a
    -- second, possibly different, model answer.
    UNIQUE(idempotency_key),

    CONSTRAINT email_analyses_confidence_check
        CHECK (confidence >= 0 AND confidence <= 1),
    CONSTRAINT email_analyses_confidence_threshold_check
        CHECK (confidence_threshold >= 0 AND confidence_threshold <= 1)
);

CREATE INDEX email_analyses_message_created_idx
    ON email_analyses(email_message_id, created_at DESC);

CREATE INDEX email_analyses_category_priority_idx
    ON email_analyses(category, priority);

COMMIT;
