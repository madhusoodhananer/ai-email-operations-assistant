# ADR-003 — Enforce idempotency with database constraints and a transactional outbox

| | |
| --- | --- |
| **Status** | Accepted |
| **Date** | 2026-07-31 |
| **Supersedes** | — |
| **Superseded by** | — |
| **Related** | [ADR-001](ADR-001-database-choice.md), [ADR-002](ADR-002-ai-provider.md) |

## Context

Every step in this pipeline will run more than once. That is not a failure mode to be designed away; it is the normal operating condition.

- Email providers redeliver webhooks when an acknowledgement is slow or lost.
- n8n retries failed executions, and an operator may replay one by hand.
- An administrator may deliberately reprocess an email after a prompt change, a model change, or an integration fix.
- A step can fail *after* its side effect has already happened — the model call succeeds and the database insert fails, or the record is written and the notification is not.

Repetition is cheap in some places and expensive in others. Re-running a classification wastes money. Re-running a lead insert corrupts the CRM. Re-running a Slack notification tells the sales team about the same lead twice. The system needs a single, consistent answer for how a repeated step behaves.

Two specific problems have to be solved rather than assumed away.

**Check-then-insert is not a concurrency control.** The obvious workflow shape — query for an existing record, insert if absent — has a window between the check and the insert. Two executions can both find nothing and both insert. This is not a rare interleaving; webhook redelivery makes concurrent duplicates the expected case.

**A database transaction cannot span an external service.** Slack, Gmail, and the model provider cannot participate in a rollback. Holding a transaction open across a network call produces two failure shapes, both bad: the notification is sent and the transaction then rolls back, so Slack reports a lead that does not exist; or the record commits and the notification fails, and retrying the whole step sends duplicates.

## Decision

Idempotency is enforced **by the database**, and external side effects are dispatched **through a transactional outbox**. Workflow logic may optimize, but it is never the guarantee.

> Note: ADR-004 later introduces `processing_runs` as the execution boundary.
> The principle in this ADR remains accepted, but current table-level constraints
> should be read from [the data model](../../data-model.md) and ADR-004 where
> they involve runs, attempts, current outcomes, or leases.

### 1. Uniqueness lives in the schema

| Table | Constraint | Meaning |
| --- | --- | --- |
| `email_messages` | `UNIQUE (provider, provider_message_id)` | One record per source message, whatever the delivery count. |
| `processing_attempts` | `UNIQUE (email_message_id, step_name, attempt_number)` | Every attempt is preserved; the same attempt cannot be recorded twice. |
| `email_analyses` | `UNIQUE (idempotency_key)` | One stored analysis per logical classification operation. |
| `sales_leads` | `UNIQUE (email_message_id)` | Version 1 assumes at most one lead per email. |
| `email_drafts` | `UNIQUE (email_message_id, analysis_id, draft_version)` plus `UNIQUE (idempotency_key)` | Multiple versions are legitimate; a retry of the same generation is not. |
| `manual_reviews` | `UNIQUE (email_message_id, analysis_id, reason)` | A new analysis may raise a new review; the same analysis may not raise the same one twice. |

`status` is deliberately excluded from the review key. Including it would allow a resolved review to be recreated with a different status and defeat the constraint.

### 2. Insert first, then handle the conflict

The canonical shape for any create is:

```
attempt insert
    ├── success        → continue with the new record
    └── duplicate key  → fetch and continue with the existing record
```

A duplicate key is an expected outcome, not an error. For webhook redelivery in particular, returning the existing record is the correct response — the caller asked for the message to be processed, and it has been.

### 3. Model calls are keyed, not repeated

Model output is not reproducible. Even at low temperature the same prompt may return a different answer (ADR-002), so a retry must **reuse the stored result** rather than call again and hope for agreement.

Each classification operation carries an idempotency key derived from:

```
classification : <email_message_id> : <prompt_version> : <model_name> : <input_hash>
```

`input_hash` is computed over a **precisely defined normalization** — sender address, subject, and cleaned plain-text body, whitespace-collapsed — and nothing volatile. Timestamps, headers, and provider-assigned identifiers are excluded, because any volatile input makes the key unmatchable on retry and silently disables the deduplication it exists to provide.

Before calling the model, the pipeline checks whether a successful attempt already exists for that step. If so, the stored analysis is reused.

A deliberate change to the prompt version or the model produces a different key, and therefore a new analysis — which is the intended behavior for reprocessing.

### 4. External effects go through an outbox

The business record and the *intent* to notify are committed together, in one local transaction:

```
BEGIN
  insert analysis
  update email status
  insert business record        (e.g. sales_lead)
  insert outbox_event  status = pending
COMMIT
```

A separate worker drains the outbox: read pending, perform the external call, mark sent, or leave it for a later sweep. No external call happens inside a transaction, and no transaction is held open across a network boundary.

This applies to every outward action — sales and finance notifications, admin error mail, Gmail draft creation.

### 5. The transactional block is a single unit in `api/`

n8n commits per node, so a transaction spanning several nodes is not reliable. The block above must be executed as one unit — a stored procedure or a single endpoint in `api/`. Workflows call that unit; they do not assemble it from individual database nodes.

## Alternatives considered

| Option | Assessment | Outcome |
| --- | --- | --- |
| **Application-level check-then-insert** | Simple and readable, and it removes most duplicates in practice. It does not remove the ones that matter, because the check and the insert are not atomic. Retained as an optimization to avoid pointless work, never as the guarantee. | Rejected as the mechanism |
| **Distributed lock per email** | A lock keyed on the message ID would serialize concurrent executions. It adds an external dependency, introduces lock expiry and orphaned-lock handling, and still needs the unique constraint as a backstop for the case where the lock fails. More machinery for a weaker guarantee than the constraint already provides. | Rejected |
| **Distributed transaction across database and external services** | Would give exactly the semantics wanted. Slack, Gmail, and the model provider do not support two-phase commit, so it is not available. | Not available |
| **Dual write — commit, then call the external service directly with retries** | The common shortcut, and the source of the exact failure interleavings this ADR exists to prevent. A crash between commit and call loses the notification silently; a retry of the combined step duplicates it. | Rejected |
| **Exactly-once delivery to external services** | Not achievable across a network boundary without cooperation from the receiver. Pursuing it produces complexity that does not pay. At-least-once delivery with idempotent consumers is the reachable target and is what the outbox provides. | Rejected as unachievable |
| **Deduplicate on message content hash alone** | Would treat two genuinely distinct emails with identical content as one. The provider's message identifier is the correct identity; the content hash belongs in the model-call key, where it serves a different purpose. | Rejected |

## Consequences

**Accepted benefits**

- Duplicate protection holds no matter which component writes, including manual database access and future services.
- The full attempt history is preserved, so "it eventually succeeded" and "it succeeded on the third try after two timeouts" are distinguishable.
- Model spend is bounded by real work rather than by retry count.
- Business data and notification intent commit atomically, so a notification is never sent for a record that does not exist.

**Accepted costs**

- **Delivery is at-least-once, not exactly-once.** If a Slack call succeeds and the subsequent mark-as-sent fails, the next sweep sends again. This is inherent to the pattern. Gmail draft creation can be keyed on `analysis_id` and made idempotent; Slack offers no such key, so duplicate notifications are an accepted failure mode in Version 1.
- **The outbox needs a table and a worker.** `outbox_events` is not in the Version 1 table list in the data model and must be added there. The draining worker needs its own retry policy, a poison-event path, and an alert on pending events that are not clearing — an outbox nobody monitors is a silent queue of undelivered work.
- **Duplicate-key errors must be classified, not merely caught.** A conflict on `processing_attempts` means another execution already owns that step, and the correct response is to yield, not to retry into a loop. Treating every constraint violation identically will produce one.
- **`NULL` defeats plain unique constraints in PostgreSQL.** `manual_reviews.analysis_id` is nullable, and distinct `NULL`s do not collide, so reviews raised with no analysis — a failure before classification, for instance — will not be deduplicated by an ordinary unique index. This needs `NULLS NOT DISTINCT`, a partial index, or a sentinel value, and it is a real gap rather than a theoretical one.
- **Latency increases slightly.** Notifications go out on the sweeper's schedule, not inline. For this workload that is immaterial, but it is a change in behavior.

**Open, not decided here**

- **Which analysis is current.** Reprocessing under a new prompt version deliberately creates a second analysis. Nothing yet marks which one is in force for the review console. Ordering by `created_at` breaks under concurrency; an explicit `superseded_by` reference or an `is_current` flag with a partial unique index is needed.
- **No lease on the `processing` status.** A worker that dies mid-run leaves the row in `processing` permanently, and no retry reclaims it. A `claimed_at` timestamp plus a sweeper that reclaims rows past a threshold would close this.
- **Outbox event ordering.** Version 1 assumes events for an entity are independent. If an update event can overtake its create event, ordering guarantees will be needed.
