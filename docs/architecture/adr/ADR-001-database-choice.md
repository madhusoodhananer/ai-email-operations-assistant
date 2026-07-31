# ADR-001 — Use PostgreSQL as the primary data store

| | |
| --- | --- |
| **Status** | Accepted |
| **Date** | 2026-07-31 |
| **Supersedes** | — |
| **Superseded by** | — |

## Context

The system needs a durable store for email records, classification and extraction output, routing decisions, review state, and the audit log.

That workload places several demands on the store:

- **Transactional integrity.** Processing an email touches several tables — the message record, the extracted fields, the routing decision, and the audit entry. These must commit as a unit, or a failure mid-pipeline leaves the system in a state where an email appears routed but has no decision record behind it.
- **Enforced structure.** The extracted schema and routing labels form a controlled vocabulary. Invalid states should be rejected by the database, not merely discouraged by application code, because multiple components (n8n workflows, the API, the review console) write to the same tables.
- **Semi-structured payloads.** Raw model output, message headers, and provider metadata are irregular and will change shape as prompts evolve. Forcing them into fixed columns early would mean a migration for every prompt revision.
- **Query performance under growth.** The review console and audit queries filter by status, team, classification, and time window. These need indexes to stay responsive as volume grows.
- **Room to scale.** The store should not become the constraint that forces a rewrite once throughput increases.

## Decision

**PostgreSQL** is the primary data store for the system.

## Rationale

PostgreSQL satisfies all five requirements in a single engine:

| Requirement | How PostgreSQL addresses it |
| --- | --- |
| Transactional integrity | Full ACID transactions, so a multi-table pipeline step commits atomically or not at all. |
| Enforced structure | Foreign keys, `CHECK` constraints, unique constraints, and enumerated types push invariants into the schema. |
| Semi-structured payloads | Native `JSONB` stores irregular model output alongside relational columns, with the ability to query and index into the document. |
| Query performance | A mature indexing system, including partial and expression indexes and GIN indexes over `JSONB`. |
| Future scalability | Proven behavior at volume, with partitioning, replication, and a broad managed-hosting ecosystem available without changing engines. |

The decisive property is that these are not separate systems to integrate. A relational core with `JSONB` columns avoids splitting state across a relational database and a document store, which would reintroduce the transactional problem the choice was meant to solve.

## Alternatives considered

| Option | Assessment | Outcome |
| --- | --- | --- |
| **MySQL** | The closest alternative and a legitimate choice: ACID transactions, constraints, and mature indexing. Rejected on the margin — its JSON type is less capable than `JSONB` for the irregular model output this system stores, and it offers weaker support for expression and partial indexing. The gap is narrow, and this decision would be inexpensive to revisit. | Rejected |
| **Airtable** | A hosted product rather than a database. API rate limits sit directly in the processing path, referential integrity and transactional guarantees are limited, and per-record pricing scales badly with an audit log that grows with every message. Creates vendor lock-in over the system's system of record. | Rejected |
| **Google Sheets** | Not a database. No transactions, no constraints, no meaningful indexing, and no safe concurrent writes from parallel workflow executions. Workable only as a throwaway prototype, and the migration cost away from it would be paid at exactly the point the system started to matter. | Rejected |

## Consequences

**Accepted benefits**

- Data integrity is enforced at the storage layer, so it holds regardless of which component writes.
- Schema can evolve incrementally: stable fields become columns, volatile model output stays in `JSONB` until its shape settles.
- The audit log gains a queryable, indexable home suitable for compliance and debugging.
- Managed PostgreSQL is available from every major cloud provider, so hosting is not a lock-in decision.

**Accepted costs**

- The project takes on operational responsibility for a database: migrations, backups, connection management, and upgrades.
- Local development requires PostgreSQL running, which is handled through the Docker Compose setup rather than assumed to be installed.
- Schema changes need managed migrations, which is more process than a schemaless store would demand. This is a deliberate trade in favor of correctness.
- Storing irregular payloads in `JSONB` is permissive by design. Discipline is required to promote fields into real columns once they stabilize, or the schema quietly degrades into a document store.
