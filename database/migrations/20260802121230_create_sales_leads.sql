-- Migration: 20260802121230_create_sales_leads
-- Created:   2026-08-02 12:12:30 UTC
-- Author:    MADHUSOODANAN
--
-- Purpose:
--   Created only when the accepted category is a sales inquiry.
--
--   Uniqueness is on the run and the analysis, not on the email. Version 1 still
--   assumes one lead per email, but keying it this way lets a reprocess produce
--   a corrected lead while the earlier one survives as evidence.
--
--   Note: ADR-003 lists UNIQUE (email_message_id) here. data-model.md 9 revised
--   that once runs existed, and ADR-003 defers to the data model on anything
--   involving runs. The data model is what this follows.
--
-- The BEGIN/COMMIT block is required. database/apply-migrations.sh inserts the
-- schema_migrations row just before the COMMIT, so the schema change and the
-- record of it commit together — or neither does.
--
-- Once applied anywhere other than a local database, treat this file as
-- immutable — editing it will not re-run it. Correct mistakes with a new
-- migration.

BEGIN;

CREATE TYPE sales_lead_status AS ENUM (
    'new',
    'review_required',
    'qualified',
    'discarded'
);

CREATE TABLE sales_leads(
    id UUID PRIMARY KEY,
    seq bigserial UNIQUE NOT NULL,
    processing_run_id UUID NOT NULL,
    analysis_id UUID NOT NULL,
    email_message_id UUID NOT NULL,
    customer_name text,
    customer_type text,                  -- individual, company, partner, ...
    company_name text,
    contact_email text NOT NULL,
    phone text,
    address text,
    website text,
    service_requested text,
    requirement_summary text,
    budget_amount numeric(14,2),
    budget_currency char(3),             -- ISO 4217
    urgency text,
    lead_status sales_lead_status NOT NULL DEFAULT 'new',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    -- Both denormalized parents are pinned to the analysis, and the analysis is
    -- itself pinned to its run and email. A lead therefore cannot reference
    -- email A, run B, and analysis C from unrelated chains.
    FOREIGN KEY (analysis_id, processing_run_id)
        REFERENCES email_analyses(id, processing_run_id),
    FOREIGN KEY (analysis_id, email_message_id)
        REFERENCES email_analyses(id, email_message_id),

    UNIQUE(processing_run_id),
    UNIQUE(analysis_id),

    CONSTRAINT sales_leads_budget_currency_check
        CHECK (budget_currency IS NULL OR budget_currency ~ '^[A-Z]{3}$'),
    CONSTRAINT sales_leads_budget_amount_check
        CHECK (budget_amount IS NULL OR budget_amount >= 0),

    -- An amount with no currency is not an amount anyone can act on.
    CONSTRAINT sales_leads_budget_pair_check
        CHECK (budget_amount IS NULL OR budget_currency IS NOT NULL)
);

CREATE INDEX sales_leads_status_created_idx
    ON sales_leads(lead_status, created_at DESC);

CREATE INDEX sales_leads_contact_email_idx
    ON sales_leads(contact_email);

COMMIT;
