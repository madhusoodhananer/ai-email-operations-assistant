-- Migration: 20260802121205_create_processing_runs
-- Created:   2026-08-02 12:12:05 UTC
-- Author:    MADHUSOODANAN
--
-- Purpose:
--   One deliberate pass over one email — the execution boundary for retries,
--   leases, reprocessing, and the current accepted outcome (ADR-004).
--
--   Transient retries stay inside a run. A prompt, model, threshold, or routing
--   change creates a new run, so the earlier result stays auditable.
--
-- The BEGIN/COMMIT block is required. database/apply-migrations.sh inserts the
-- schema_migrations row just before the COMMIT, so the schema change and the
-- record of it commit together — or neither does.
--
-- Once applied anywhere other than a local database, treat this file as
-- immutable — editing it will not re-run it. Correct mistakes with a new
-- migration.

BEGIN;

CREATE TYPE processing_run_trigger AS ENUM (
    'initial',
    'manual_reprocess',
    'retry_recovery',
    'system_replay'
);

CREATE TYPE processing_run_status AS ENUM (
    'queued',
    'processing',
    'completed',
    'manual_review',
    'failed',
    'cancelled',
    'superseded'
);

CREATE TABLE processing_runs(
    id UUID PRIMARY KEY,
    seq bigserial UNIQUE NOT NULL,
    email_message_id UUID NOT NULL REFERENCES email_messages(id),
    parent_run_id UUID REFERENCES processing_runs(id),
    trigger_type processing_run_trigger NOT NULL,
    triggered_by text,                   -- user, service, or workflow
    idempotency_key text NOT NULL,
    status processing_run_status NOT NULL DEFAULT 'queued',
    is_current boolean NOT NULL DEFAULT false,
    config_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    claimed_by text,                     -- worker holding the lease
    lease_expires_at timestamptz,        -- claim expiry for stuck-run recovery
    started_at timestamptz,
    completed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    UNIQUE(idempotency_key),

    -- Redundant for uniqueness — id is already the primary key — but a
    -- composite foreign key needs a unique constraint covering exactly the
    -- columns it references. This is what lets child tables prove their
    -- denormalized email_message_id belongs to the run they point at.
    UNIQUE(id, email_message_id),

    -- data-model.md 13: only a completed or manual-review run may be current.
    CONSTRAINT processing_runs_current_status_check
        CHECK (NOT is_current OR status IN ('completed', 'manual_review')),

    -- A lease without a holder, or a holder without an expiry, is a half-set
    -- claim that the recovery sweeper cannot reason about.
    CONSTRAINT processing_runs_lease_check
        CHECK ((claimed_by IS NULL) = (lease_expires_at IS NULL))
);

-- One accepted current outcome per email. A plain unique constraint cannot
-- express this, because every non-current run would collide.
CREATE UNIQUE INDEX processing_runs_one_current_per_email
    ON processing_runs(email_message_id)
    WHERE is_current;

-- One active run per email, so two workers cannot process the same message and
-- pay for the same model call twice. Conservative by choice — it rules out
-- parallel experiments on one message in Version 1.
CREATE UNIQUE INDEX processing_runs_one_active_per_email
    ON processing_runs(email_message_id)
    WHERE status IN ('queued', 'processing');

-- Drives the sweeper that reclaims runs abandoned by a dead worker.
CREATE INDEX processing_runs_lease_expiry_idx
    ON processing_runs(lease_expires_at)
    WHERE status = 'processing';

COMMIT;
