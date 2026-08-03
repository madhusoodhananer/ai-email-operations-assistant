-- Migration: 20260802121220_create_manual_reviews
-- Created:   2026-08-02 12:12:20 UTC
-- Author:    MADHUSOODANAN
--
-- Purpose:
--   Work items for a trusted internal reviewer — low confidence, an invalid
--   model response, or a run that failed outright.
--
--   analysis_id is nullable because a review can be raised before any analysis
--   exists. That is exactly why the dedupe key uses NULLS NOT DISTINCT: with
--   ordinary unique semantics two NULLs do not collide, and pre-classification
--   failures would enqueue the same review repeatedly (ADR-003, consequences).
--   Requires PostgreSQL 15+; we are pinned to 16.4.
--
--   status is deliberately not part of the key. Including it would let a
--   resolved review be recreated with a different status.
--
-- The BEGIN/COMMIT block is required. database/apply-migrations.sh inserts the
-- schema_migrations row just before the COMMIT, so the schema change and the
-- record of it commit together — or neither does.
--
-- Once applied anywhere other than a local database, treat this file as
-- immutable — editing it will not re-run it. Correct mistakes with a new
-- migration.

BEGIN;

CREATE TYPE manual_review_reason AS ENUM (
    'low_confidence',
    'invalid_ai_response',
    'unsupported_attachment',
    'suspicious_content',
    'missing_required_data',
    'processing_failed'
);

CREATE TYPE manual_review_status AS ENUM (
    'pending',
    'in_review',
    'resolved',
    'dismissed'
);

CREATE TABLE manual_reviews(
    id UUID PRIMARY KEY,
    seq bigserial UNIQUE NOT NULL,
    processing_run_id UUID NOT NULL,
    email_message_id UUID NOT NULL,
    analysis_id UUID,
    reason manual_review_reason NOT NULL,
    status manual_review_status NOT NULL DEFAULT 'pending',
    assigned_to text,                    -- reviewer identifier; text in Version 1
    review_notes text,
    resolved_category text,
    resolved_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    -- The run and its email always travel together.
    FOREIGN KEY (processing_run_id, email_message_id)
        REFERENCES processing_runs(id, email_message_id),

    -- Only enforced when analysis_id is set. Default MATCH SIMPLE skips the
    -- check if any referencing column is NULL, which is exactly right here: a
    -- review raised before classification has no analysis to be consistent with.
    FOREIGN KEY (analysis_id, processing_run_id)
        REFERENCES email_analyses(id, processing_run_id),

    UNIQUE NULLS NOT DISTINCT (processing_run_id, analysis_id, reason),

    CONSTRAINT manual_reviews_resolved_at_check
        CHECK ((status IN ('resolved', 'dismissed')) = (resolved_at IS NOT NULL))
);

CREATE INDEX manual_reviews_status_created_idx
    ON manual_reviews(status, created_at);

CREATE INDEX manual_reviews_email_message_idx
    ON manual_reviews(email_message_id);

COMMIT;
