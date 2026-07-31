# Requirements

**Status:** Draft — Version 1 scope
**Last updated:** 2026-07-31

This document defines what the AI Email Operations Assistant must do, what it explicitly will not do in Version 1, and the conditions under which it is considered correct. Architectural decisions that follow from these requirements are recorded in [`decisions.md`](decisions.md).

---

## 1. Problem statement

Shared operational inboxes — support, sales, billing — are unmanaged queues. Messages arrive unstructured, are triaged by hand, and are routed by whoever happens to recognize them. The consequences are unpredictable response times, inconsistent handling, and no record of why any given message was dealt with the way it was.

The system treats that inbox as a processing pipeline: every inbound message is normalized, classified, structured, routed to an owning team, and — where appropriate — given a proposed reply, with a complete record of every decision.

## 2. Stakeholders

| Stakeholder | Interest |
| --- | --- |
| Business teams (sales, support, billing) | Receive correctly routed messages with useful context attached. |
| Reviewer / operator | Resolves low-confidence and failed messages; corrects wrong classifications. |
| Administrator | Reprocesses messages after prompt or model changes; investigates failures. |
| Compliance | Requires that any past decision can be reconstructed and explained. |

## 3. Scope

### In scope for Version 1

Ingestion, classification, extraction, confidence-based routing, sales lead capture, draft generation, manual review queue, notification dispatch, and a complete audit trail.

### Out of scope for Version 1

| Excluded | Reason |
| --- | --- |
| Sending replies automatically | Drafts are proposals. Sending is a separate trust decision, deferred deliberately. |
| Review console user interface | Version 2. Version 1 exposes state through the database and API only. |
| Attachment parsing | Adds file handling, malware exposure, and a second extraction path. Attachment presence is recorded; content is not read. |
| Multiple mailboxes and providers | The schema is provider-aware, but only one source is integrated. |
| More than one lead per email | Assumed one-to-one for Version 1; the schema can be relaxed later. |
| External CRM integration | Leads are captured internally. Pushing to a third-party CRM is a later increment. |
| Multi-language handling | Assumed English for Version 1. |

---

## 4. Functional requirements

### Ingestion

| ID | Requirement |
| --- | --- |
| **FR-1** | The system shall accept inbound email from a configured provider and normalize it into a common internal representation: sender, recipient, subject, cleaned plain-text body, receipt time, thread identifier, and attachment presence. |
| **FR-2** | The system shall process each source message exactly once, identified by provider and provider message identifier, regardless of how many times it is delivered. Redelivery shall return the existing record rather than fail. |
| **FR-3** | The system shall record the receipt of a message before any model call is made, so that no inbound email can be lost by a downstream failure. |

### Analysis

| ID | Requirement |
| --- | --- |
| **FR-4** | The system shall classify each message by category and priority, and extract structured business fields, in a **single model call**. Classification and extraction shall not be separate calls. |
| **FR-5** | The system shall validate every model response against a defined schema before it is used. A response that fails validation shall not be treated as a result. |
| **FR-6** | The system shall record, for every analysis: the model used, the prompt version, the confidence value, and the raw model response. |
| **FR-7** | The system shall compare confidence against a configurable threshold and record the threshold that was applied, so that past decisions remain interpretable after the threshold changes. |

### Routing and business outcomes

| ID | Requirement |
| --- | --- |
| **FR-8** | The system shall route each accepted message to an owning business team based on its category. |
| **FR-9** | The system shall create a sales lead record when, and only when, the message is classified as a sales inquiry. |
| **FR-10** | The system shall notify the owning team of messages routed to it. Notification dispatch shall not be able to succeed for a business record that was not committed. |

### Draft generation

| ID | Requirement |
| --- | --- |
| **FR-11** | The system shall generate a draft reply **only after** confidence and routing checks have passed, and only for messages marked as requiring one. Messages that are low-confidence, rejected, or ineligible shall not incur draft generation cost. |
| **FR-12** | The system shall store drafts separately from analyses, supporting multiple versions per message, and shall preserve earlier versions when a draft is regenerated or edited. |
| **FR-13** | The system shall not send any reply in Version 1. Drafts are created and stored only. |

### Review and recovery

| ID | Requirement |
| --- | --- |
| **FR-14** | The system shall queue a message for manual review when confidence is below threshold, when schema validation fails, or when processing fails permanently, recording the reason. |
| **FR-15** | The system shall allow a reviewer to record a corrected category, review notes, and a resolution. |
| **FR-16** | The system shall allow an administrator to reprocess a message after a prompt, model, or integration change, **preserving** the earlier analysis rather than overwriting it. |
| **FR-17** | The system shall record every processing attempt, including failed ones, with the step, attempt number, outcome, error detail, and duration. A message that succeeded on the third attempt shall be distinguishable from one that succeeded on the first. |

---

## 5. Non-functional requirements

| ID | Category | Requirement |
| --- | --- | --- |
| **NFR-1** | Throughput | The design target is 5,000 messages per day, with the assumption that arrival is uneven and peak hourly rate substantially exceeds the daily average. |
| **NFR-2** | Idempotency | Repeated execution of any step shall not produce duplicate business records, duplicate leads, or repeated model spend. Enforcement shall be in the database, not in workflow logic. See ADR-003. |
| **NFR-3** | Durability | No accepted message shall be lost as a result of a downstream failure. A message that cannot be processed shall end in a recorded failed or review state, never silently dropped. |
| **NFR-4** | Auditability | Every routing decision, classification, and draft shall be reconstructable after the fact, including which model and prompt version produced it. |
| **NFR-5** | Degradation | A model provider outage shall stall processing, not lose it. Work shall resume without manual repair when the provider recovers. |
| **NFR-6** | Consistency | A business record and its outbound notification shall be committed atomically. External calls shall never occur inside a database transaction. |
| **NFR-7** | Security | All credentials shall be supplied through environment variables. No secret shall be committed to the repository. Each integration shall hold the narrowest permission that allows it to function. |
| **NFR-8** | Privacy | Only fictional test data shall be used in this project. Real deployment requires a documented retention period, redaction of obvious secrets before transmission to third parties, and an explicit position on data residency. |
| **NFR-9** | Observability | Failed attempts, undelivered notifications, and messages stuck in an intermediate state shall be visible and alertable. |
| **NFR-10** | Maintainability | Prompts shall be versioned artifacts. Model identifiers shall be pinned explicitly, never floating aliases. |
| **NFR-11** | Cost | Per-message model cost shall be a tracked design constraint. Draft generation, the most expensive step, shall be gated by eligibility. |
| **NFR-12** | Portability | The system shall run locally through a single container orchestration command, with no manually installed dependencies beyond a container runtime. |
| **NFR-13** | Testability | Classification and extraction shall be evaluable against a labelled fixture set without calling the live provider. |

---

## 6. Assumptions

1. One inbound email produces at most one sales lead.
2. Message bodies are English and predominantly plain text; HTML is reduced to text during normalization.
3. The provider supplies a stable, unique message identifier.
4. Volume is bounded by NFR-1; the design is not intended for orders of magnitude beyond it without revision.
5. Reviewers are trusted internal users; authorization within the review queue is not modelled in Version 1.

## 7. Constraints

1. The primary data store is PostgreSQL (ADR-001).
2. The model provider is reached only through the internal abstraction, never directly from workflow nodes (ADR-002).
3. Orchestration is n8n, which commits per node — multi-statement transactions must therefore be executed as a single unit (ADR-003).
4. Only fictional data may be used in this repository.

## 8. Acceptance criteria for Version 1

Version 1 is complete when all of the following hold against the fixture set:

1. A message delivered three times produces exactly one `email_messages` row, one analysis, and one lead.
2. A model call that fails twice and succeeds on the third attempt produces three `processing_attempts` rows and one analysis.
3. A message below the confidence threshold reaches the review queue and generates **no** draft.
4. A message classified as a sales inquiry produces exactly one lead and exactly one notification, with no case in which a notification exists for an uncommitted lead.
5. Reprocessing a message under a new prompt version produces a second analysis while the first remains intact.
6. Every processed message can be traced end to end: source, analysis, model, prompt version, routing decision, and outcome.
7. No credential appears anywhere in the repository history.

## 9. Open questions

These are unresolved and tracked rather than assumed:

1. **Retention period** for message bodies and raw model responses is undefined. Required before any non-fictional data is processed.
2. **Confidence threshold** value is not yet calibrated; it needs a labelled fixture set to choose defensibly.
3. **Category taxonomy** is not yet fixed. It must be closed and enumerated before it can be enforced in the schema.
4. **Reviewer identity** — how `assigned_to` is populated, and whether authorization is needed in Version 2.
5. Three schema-level questions remain open in ADR-003: marking which analysis is current, reclaiming messages stuck in the processing state, and ordering of outbox events.
