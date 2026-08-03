-- Migration: 20260802121225_create_routing_decisions
-- Created:   2026-08-02 12:12:25 UTC
-- Author:    MADHUSOODANAN
--
-- Purpose:
--   The accepted route derived from an analysis.
--
--   Kept out of email_analyses on purpose. FR-8 and NFR-4 require routing to be
--   reconstructable, and folding it into the analysis would make model output
--   and business policy look like one thing. routing_rule_version is what makes
--   an old decision explainable after the rules change.
--
-- The BEGIN/COMMIT block is required. database/apply-migrations.sh inserts the
-- schema_migrations row just before the COMMIT, so the schema change and the
-- record of it commit together — or neither does.
--
-- Once applied anywhere other than a local database, treat this file as
-- immutable — editing it will not re-run it. Correct mistakes with a new
-- migration.

BEGIN;

CREATE TABLE routing_decisions(
    id UUID PRIMARY KEY,
    seq bigserial UNIQUE NOT NULL,
    processing_run_id UUID NOT NULL,
    analysis_id UUID NOT NULL,
    owning_team text NOT NULL,           -- sales, support, billing, ...
    route_reason text,
    routing_rule_version text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),

    -- The route must belong to one chain: this analysis must be the analysis of
    -- this run. Separate single-column FKs would allow a decision that points at
    -- run B and an analysis of run C.
    FOREIGN KEY (analysis_id, processing_run_id)
        REFERENCES email_analyses(id, processing_run_id),

    UNIQUE(processing_run_id),
    UNIQUE(analysis_id)
);

CREATE INDEX routing_decisions_owning_team_idx
    ON routing_decisions(owning_team, created_at DESC);

COMMIT;
