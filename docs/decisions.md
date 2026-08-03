# Architecture Decision Records

This is the index of significant architectural decisions taken on this project. Each decision lives in its own file under [`architecture/adr/`](architecture/adr/), named `ADR-<number>-<slug>.md`.

Records are immutable: once a decision is accepted it is not edited in place. If a decision is later reversed, a new record is added and the original is marked **Superseded**, so the reasoning behind past choices remains readable.

## Status values

| Status | Meaning |
| --- | --- |
| **Proposed** | Under discussion; not yet binding. |
| **Accepted** | In force. Implementation should follow it. |
| **Superseded** | Replaced by a later record, which is named in the file. |

## Index

| ID | Decision | Status | Date |
| --- | --- | --- | --- |
| [ADR-001](architecture/adr/ADR-001-database-choice.md) | Use PostgreSQL as the primary data store | Accepted | 2026-07-31 |
| [ADR-002](architecture/adr/ADR-002-ai-provider.md) | Use OpenAI as the initial LLM provider, behind a provider abstraction | Accepted | 2026-07-31 |
| [ADR-003](architecture/adr/ADR-003-idempotency.md) | Enforce idempotency with database constraints and a transactional outbox | Accepted | 2026-07-31 |
| [ADR-004](architecture/adr/ADR-004-processing-runs.md) | Model processing runs as the execution boundary | Accepted | 2026-08-02 |

## Writing a new record

1. Copy the structure of an existing record: Context, Decision, Rationale, Alternatives considered, Consequences.
2. Number it sequentially and give it a descriptive slug.
3. State the alternatives honestly, including why each was rejected — a record that only argues for the chosen option is not useful later.
4. Record the costs accepted alongside the benefits.
5. Add a row to the index above.
