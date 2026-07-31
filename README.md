# AI Email Operations Assistant

> An enterprise-inspired automation platform that classifies, enriches, drafts, and routes inbound email using n8n orchestration and large language models.

![Status](https://img.shields.io/badge/status-under%20development-orange)
![Orchestration](https://img.shields.io/badge/orchestration-n8n-EA4B71)
![License](https://img.shields.io/badge/license-MIT-blue)

---

## Overview

Shared inboxes are one of the most expensive unmanaged queues in a business. Support, sales, billing, and operations mail arrives unstructured, is triaged manually, and is routed by tribal knowledge — which makes response times unpredictable and quality inconsistent.

**AI Email Operations Assistant** treats that inbox as a production pipeline. Every inbound message is ingested, classified, structured, enriched with an AI-generated draft reply, and routed to the owning team — with retries, audit logging, and a human review path built in from the start.

The project is deliberately built to enterprise software engineering standards: documented architecture, explicit design decisions, a defined data model, and testable components — not a single monolithic automation.

## Core Capabilities

| Capability | Description |
| --- | --- |
| **Email classification** | Categorizes inbound mail by intent, topic, and urgency using an LLM-backed classifier with a controlled label taxonomy. |
| **Structured extraction** | Pulls entities and business fields (order IDs, account references, dates, amounts, sentiment) into a normalized schema. |
| **AI draft generation** | Produces context-aware draft replies grounded in the extracted data and team-specific tone and policy prompts. |
| **Intelligent routing** | Directs each message to the correct business team or queue based on classification, confidence, and routing rules. |
| **Retry & failure handling** | Isolates transient failures, applies bounded retries with backoff, and escalates poison messages to a dead-letter path. |
| **Audit logging** | Persists a traceable record of every decision — inputs, model outputs, confidence, and final action — for compliance and debugging. |
| **Human-in-the-loop review** | Low-confidence or high-risk messages are held for manual approval before anything is sent. |

## Architecture

```
                  Inbound Email
                        │
                        ▼
            ┌────────────────────────┐
            │       Ingestion        │
            │         (n8n)          │
            └───────────┬────────────┘
                        │
                        ▼
            ┌────────────────────────┐
            │     Classification     │
            │         (LLM)          │
            └───────────┬────────────┘
                        │
                        ▼
            ┌────────────────────────┐
            │       Extraction       │
            │         (LLM)          │
            └───────────┬────────────┘
                        │
                        ▼
            ┌────────────────────────┐
            │    Draft Generation    │
            │         (LLM)          │
            └───────────┬────────────┘
                        │
                        ▼
            ┌────────────────────────┐
            │   Routing & Decision   │
            │         Engine         │
            └─┬───────────────────┬──┘
   confident  │                   │  low confidence
              ▼                   ▼
      ┌────────────────┐  ┌────────────────┐
      │   Team Queue   │  │ Manual Review  │
      └───────┬────────┘  └───────┬────────┘
              │                   │
              └─────────┬─────────┘
                        │
                        ▼
            ┌────────────────────────┐
            │ Audit Log + Data Store │
            └────────────────────────┘

        Cross-cutting: retry policy · dead-letter queue · observability
```

Detailed design documentation lives in [`docs/`](docs/):

- [`docs/architecture.md`](docs/architecture.md) — system architecture and component responsibilities
- [`docs/requirements.md`](docs/requirements.md) — functional and non-functional requirements
- [`docs/data-model.md`](docs/data-model.md) — entities, schemas, and persistence design
- [`docs/decisions.md`](docs/decisions.md) — architecture decision records (ADRs)

## Repository Structure

```
ai-email-operations-assistant/
├── api/            # Backend service endpoints and integration layer
├── database/       # Schema definitions, migrations, and seed data
├── docker/         # Container definitions and local orchestration
├── docs/           # Architecture, requirements, data model, and ADRs
│   └── architecture/adr/   # Architecture decision records, one file each
├── frontend/       # Review and operations console
├── n8n/            # n8n workflow definitions and exported pipelines
├── prompts/        # Versioned LLM prompt templates
├── sample-data/    # Representative email fixtures for development
└── tests/          # Automated test suites
```

## Technology Stack

| Layer | Technology |
| --- | --- |
| Workflow orchestration | n8n |
| Intelligence | Large language models (classification, extraction, drafting) |
| Persistence | Relational database for state and audit logs |
| Packaging | Docker |
| Interface | Web-based review console |

> Concrete technology selections are recorded as they are made in [`docs/decisions.md`](docs/decisions.md).

## Getting Started

> **Note:** The project is under active development. The steps below describe the intended developer workflow; components are being implemented incrementally.

### Prerequisites

- Docker and Docker Compose
- An n8n instance (self-hosted via the provided compose configuration)
- API credentials for the chosen LLM provider
- Mailbox access credentials (IMAP/Graph/Gmail API) for the target inbox

### Local setup

```bash
# 1. Clone the repository
git clone https://github.com/<your-org>/ai-email-operations-assistant.git
cd ai-email-operations-assistant

# 2. Create your local environment file
cp .env.example .env   # then populate credentials

# 3. Start the local stack
docker compose -f docker/docker-compose.yml up -d

# 4. Import the workflow definitions into n8n
#    (see n8n/README for import instructions)
```

### Configuration

All credentials and environment-specific values are supplied through environment variables. No secrets are committed to the repository.

## Design Principles

1. **Deterministic where possible, probabilistic where valuable.** Routing rules and retry logic are explicit code; only genuinely language-shaped work is delegated to a model.
2. **Every decision is auditable.** Model inputs, outputs, and confidence scores are persisted so any outcome can be reconstructed after the fact.
3. **Fail safe, not silent.** Transient errors retry; unrecoverable ones escalate to a human. Nothing is dropped.
4. **Humans stay in control.** Drafts are proposals. Sending is gated by confidence thresholds and review policy.
5. **Prompts are versioned artifacts.** Prompt changes are reviewed and released like code, not edited in place in production.

## Roadmap

- [ ] Email ingestion pipeline and normalization layer
- [ ] Classification workflow with a defined label taxonomy
- [ ] Structured extraction schema and validation
- [ ] AI draft generation with team-specific prompt templates
- [ ] Routing engine and confidence thresholds
- [ ] Retry, backoff, and dead-letter handling
- [ ] Audit logging and persistence
- [ ] Manual review console
- [ ] Automated test suite and evaluation harness
- [ ] Deployment and operational runbook

## Project Status

🚧 **Under development.** Interfaces, schemas, and workflow definitions are subject to change. Follow the roadmap above for current progress.

## Contributing

Contributions are welcome once the core pipeline stabilizes. In the meantime, please open an issue to discuss proposed changes or raise design questions against the documents in [`docs/`](docs/).

## License

Released under the [MIT License](LICENSE).
