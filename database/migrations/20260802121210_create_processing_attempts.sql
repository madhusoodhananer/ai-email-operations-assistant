-- Migration: 20260802121210_create_processing_attempts
-- Created:   2026-08-02 12:12:10 UTC
-- Author:    MADHUSOODANAN
--
-- Purpose:
--   Makes retries visible. Without this table the system can say only that
--   processing eventually succeeded, not that two provider calls timed out
--   first.
--
--   No updated_at: an attempt is an immutable record of one try.
--
-- The BEGIN/COMMIT block is required. database/apply-migrations.sh inserts the
-- schema_migrations row just before the COMMIT, so the schema change and the
-- record of it commit together — or neither does.
--
-- Once applied anywhere other than a local database, treat this file as
-- immutable — editing it will not re-run it. Correct mistakes with a new
-- migration.

BEGIN;

CREATE TYPE processing_attempt_status AS ENUM (
    'started',
    'success',
    'failed'
);

CREATE TABLE processing_attempts(
    id UUID PRIMARY KEY,
    seq bigserial UNIQUE NOT NULL,
    processing_run_id UUID NOT NULL REFERENCES processing_runs(id),
    step_name text NOT NULL,             -- ingest, classify_extract, route, ...
    attempt_number integer NOT NULL,     -- 1-based, within the run and step
    status processing_attempt_status NOT NULL,
    error_type text,                     -- timeout, rate_limit, validation_error
    error_message text,                  -- must be safe for logs
    http_status_code integer,
    execution_id text,                   -- n8n execution id or API request id
    started_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    duration_ms integer,

    -- A conflict here means another execution already owns this step. ADR-003:
    -- yield, do not retry into a loop.
    UNIQUE(processing_run_id, step_name, attempt_number),

    CONSTRAINT processing_attempts_attempt_number_check
        CHECK (attempt_number >= 1),
    CONSTRAINT processing_attempts_duration_ms_check
        CHECK (duration_ms IS NULL OR duration_ms >= 0)
);

CREATE INDEX processing_attempts_run_step_idx
    ON processing_attempts(processing_run_id, step_name);

CREATE INDEX processing_attempts_status_started_idx
    ON processing_attempts(status, started_at);

COMMIT;
