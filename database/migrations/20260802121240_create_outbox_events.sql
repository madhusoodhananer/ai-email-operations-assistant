-- Migration: 20260802121240_create_outbox_events
-- Created:   2026-08-02 12:12:40 UTC
-- Author:    MADHUSOODANAN
--
-- Purpose:
--   External effects that must happen after the business transaction commits.
--   The business record and the intent to notify are inserted in one local
--   transaction; a separate worker drains this table (ADR-003, 4).
--
--   No foreign key to a business table: entity_type/entity_id are polymorphic
--   so any committed outcome can enqueue an effect. This is deliberate, and it
--   means nothing at the database level guarantees entity_id resolves.
--
--   payload is self-contained by design. A consumer must not have to re-read
--   the business entity, which may have changed since the event was raised.
--
--   Delivery is at-least-once. If the external call succeeds and the mark-sent
--   fails, the next sweep sends again — inherent to the pattern, accepted in
--   Version 1.
--
-- The BEGIN/COMMIT block is required. database/apply-migrations.sh inserts the
-- schema_migrations row just before the COMMIT, so the schema change and the
-- record of it commit together — or neither does.
--
-- Once applied anywhere other than a local database, treat this file as
-- immutable — editing it will not re-run it. Correct mistakes with a new
-- migration.

BEGIN;

CREATE TYPE outbox_event_status AS ENUM (
    'pending',
    'processing',
    'sent',
    'failed',
    'dead'
);

CREATE TABLE outbox_events(
    id UUID PRIMARY KEY,
    seq bigserial UNIQUE NOT NULL,
    event_type text NOT NULL,            -- message_routed, sales_lead_created, ...
    entity_type text NOT NULL,           -- routing_decision, sales_lead, ...
    entity_id UUID NOT NULL,
    dedupe_key text NOT NULL,            -- consumer-visible idempotency key
    payload jsonb NOT NULL,
    status outbox_event_status NOT NULL DEFAULT 'pending',
    attempts integer NOT NULL DEFAULT 0,
    last_error text,
    available_at timestamptz NOT NULL DEFAULT now(),
    claimed_by text,                     -- worker holding the delivery lease
    lease_expires_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    sent_at timestamptz,

    UNIQUE(dedupe_key),

    CONSTRAINT outbox_events_attempts_check
        CHECK (attempts >= 0),
    CONSTRAINT outbox_events_lease_check
        CHECK ((claimed_by IS NULL) = (lease_expires_at IS NULL)),
    CONSTRAINT outbox_events_sent_at_check
        CHECK ((status = 'sent') = (sent_at IS NOT NULL))
);

-- The drain query: pending events whose backoff has elapsed.
CREATE INDEX outbox_events_status_available_idx
    ON outbox_events(status, available_at);

-- The recovery sweep for events whose delivery worker died mid-flight.
CREATE INDEX outbox_events_lease_expiry_idx
    ON outbox_events(lease_expires_at)
    WHERE status = 'processing';

-- Answers "what happened to this entity" without scanning the whole table.
CREATE INDEX outbox_events_entity_idx
    ON outbox_events(entity_type, entity_id);

COMMIT;
