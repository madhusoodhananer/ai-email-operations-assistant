# ADR-004 - Model processing runs as the execution boundary

| | |
| --- | --- |
| **Status** | Accepted |
| **Date** | 2026-08-02 |
| **Supersedes** | Open questions in [ADR-003](ADR-003-idempotency.md) about current analysis and stuck processing |
| **Superseded by** | - |
| **Related** | [ADR-001](ADR-001-database-choice.md), [ADR-003](ADR-003-idempotency.md) |

## Context

The system must support both retries and deliberate reprocessing.

Those are not the same operation:

- A retry happens because a step failed transiently, such as a timeout or rate
  limit. The user still expects the same logical processing pass to finish.
- A reprocess happens because something meaningful changed, such as a prompt,
  model, confidence threshold, or routing rule. The old result must remain
  auditable, and the new result may become the current accepted outcome.

The earlier model attached most processing state directly to `email_messages`.
That works for a single pass, but it breaks once an email can be processed more
than once. It also leaves two important questions unresolved: how to identify the
current analysis, and how to recover work stuck in `processing` when a worker
dies.

## Decision

Introduce `processing_runs` as a first-class table and make it the execution
boundary for the pipeline.

A processing run represents one deliberate pass over one email. It owns:

- processing attempts;
- the accepted analysis for that run;
- routing decision;
- optional sales lead;
- optional draft;
- optional manual review item;
- lease and recovery state.

Automatic transient retries stay inside the same run. Manual or configuration
driven reprocessing creates a new run.

Only one queued or processing run may exist for the same email at a time in
Version 1. Only one run may be marked current for the same email.

## Rationale

This separates the source message from the work performed on it.

An email is a fact received from the provider. A run is our attempt to interpret
and act on that fact under a specific configuration. When the configuration
changes, the email does not change; the run does.

This also gives us a practical concurrency control point before expensive model
calls. A worker claims a run with a lease. If another worker sees an active lease,
it yields rather than making a duplicate model call. If the worker dies, the
lease expires and the run can be resumed.

The current result is represented by `processing_runs.is_current`, guarded by a
partial unique index on `(email_message_id) WHERE is_current = true`. Historical
runs remain available, while operational queries have a clear current answer.

## Alternatives considered

| Option | Assessment | Outcome |
| --- | --- | --- |
| Keep `processing_status` on `email_messages` | Simple for the first demo, but it confuses email identity with processing lifecycle and fails under reprocessing. | Rejected |
| Mark `email_analyses.is_current` directly | Works for classification but ignores routing, lead, draft, and review outcomes that belong to the same pass. | Rejected |
| Use only `created_at DESC` to find the current analysis | Easy to query, but wrong under concurrent or failed reprocessing. The newest row is not always the accepted row. | Rejected |
| Create a separate lock table | Could serialize workers, but adds another lifecycle to maintain. A run lease gives us the same control while preserving audit context. | Rejected for Version 1 |
| Allow parallel active runs for the same email | Useful for experiments, but increases model spend and complicates current-result rules. | Deferred |

## Consequences

**Accepted benefits**

- Retries and reprocessing have different, explicit meanings.
- Attempt history is grouped under the run it belongs to.
- Stuck work can be reclaimed through lease expiry.
- The current outcome is explicit and protected by a database constraint.
- Duplicate model spend is reduced because workers claim a run before calling the
  model.

**Accepted costs**

- The schema gains another central table.
- Some writes become multi-row state transitions that must happen in a transaction.
- `is_current` is a mutable pointer, so the history is not purely append-only.
  This is accepted because operators need a current answer and auditors still
  retain every prior run.
- Version 1 does not support parallel experimentation on the same email.

## Implementation notes

The final SQL migration should include:

- `UNIQUE (idempotency_key)` on `processing_runs`;
- a partial unique index allowing one active run per email;
- a partial unique index allowing one current run per email;
- `claimed_by` and `lease_expires_at` fields for worker recovery;
- foreign keys from attempts, analyses, routes, leads, drafts, and reviews back
  to `processing_runs`.

External calls must still not happen inside database transactions. The run lease
is a claim mechanism, not a distributed transaction.
