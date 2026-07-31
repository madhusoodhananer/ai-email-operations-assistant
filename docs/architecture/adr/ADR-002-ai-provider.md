# ADR-002 — Use OpenAI as the initial LLM provider, behind a provider abstraction

| | |
| --- | --- |
| **Status** | Accepted |
| **Date** | 2026-07-31 |
| **Supersedes** | — |
| **Superseded by** | — |
| **Related** | [ADR-001](ADR-001-database-choice.md), [ADR-003](ADR-003-idempotency.md) |

## Context

Three steps in the pipeline depend on a language model: classification, structured extraction, and draft reply generation. Each is a paid network call to a third party that can be slow, rate-limited, or unavailable, and whose output is not guaranteed to be identical across calls.

The provider must therefore satisfy the following.

- **Reliable structured output.** Classification and extraction feed database columns and routing logic. The provider needs enforced JSON schema output, not prose that happens to look like JSON, so that a malformed response is a rare validated failure rather than the normal case.
- **Pinnable model versions.** The data model stores `model_name` on every `email_analyses` row so results can be attributed to the model that produced them. That attribution is meaningless if the provider silently upgrades the model behind an unversioned alias. Dated or pinned snapshots are required.
- **Determinism controls.** Low temperature and schema-constrained output reduce variation between calls. Variation cannot be eliminated, so the surrounding system must not assume that a retry reproduces the earlier answer — see ADR-003.
- **Cost and latency at volume.** The reference workload is 5,000 emails per day. With classification and extraction on every message and drafting on a subset, per-token cost is a first-class design constraint, not an afterthought.
- **Operational maturity.** Documented rate limits, meaningful error codes, and a public status channel. The retry logic in `processing_attempts` depends on being able to distinguish a transient 429 or 5xx from a permanent 4xx.
- **Data handling controls.** Email bodies contain third-party personal data. The provider must offer controls over retention and training use.
- **Reversibility.** No provider is a safe long-term bet in this market. The choice must not become load-bearing.

## Decision

**OpenAI** is the LLM provider for Version 1, for classification, extraction, and draft generation.

The provider is reached **only through an internal abstraction in `api/`** — never by calling the vendor API directly from scattered n8n nodes. The abstraction owns credentials, model selection, timeouts, retry classification, schema validation, and the recording of `model_name`, `prompt_version`, and `raw_response`.

Model identifiers are **pinned to explicit versions** in configuration. Changing a model is a deliberate, recorded change, never an implicit one.

## Rationale

| Requirement | How OpenAI addresses it |
| --- | --- |
| Structured output | Schema-constrained structured output and tool calling, so classification and extraction return parseable objects by construction. |
| Pinnable versions | Dated model snapshots can be referenced explicitly, keeping the stored `model_name` truthful. |
| Determinism controls | Temperature and schema constraints are configurable per call. |
| Cost and latency | A tiered model range, allowing a small cheap model for classification and a stronger one only where draft quality justifies the cost. |
| Operational maturity | Documented rate limits, distinguishable error codes, and a public status page. |
| Data handling | Retention and training-use controls are available under the API terms. |
| Reversibility | Nothing above is unique to OpenAI, which is precisely why the abstraction exists. |

The decision is deliberately shallow. The valuable and hard-won parts of this system are the pipeline, the idempotency guarantees, the audit trail, and the prompts — none of which are provider-specific. Choosing a provider is a configuration decision dressed up as an architectural one, and the architecture should reflect that.

## Alternatives considered

| Option | Assessment | Outcome |
| --- | --- | --- |
| **Anthropic Claude** | Genuinely comparable on every requirement above: strong schema-constrained output, pinned model versions, mature API. There is no technical case that it fails to meet the need. Not selected only because Version 1 benefits from a single provider and fewer moving parts, and OpenAI credentials were already the project's assumed default. This is the first candidate if OpenAI is displaced. | Deferred, not rejected |
| **Google Gemini** | Competitive on price and latency with native schema support. Set aside for Version 1 on grounds of team familiarity and tooling maturity in the n8n ecosystem, not capability. | Deferred |
| **Self-hosted open-weight models** (Llama, Mistral, via Ollama or similar) | The only option where email content never leaves the perimeter, and the only one with no per-message cost — both real advantages for this workload. Rejected for Version 1 because it trades a solved problem for an unsolved one: GPU provisioning, capacity planning, and materially weaker schema-adherence, all before a single email is classified. Worth revisiting if data residency becomes a hard client requirement or volume makes per-token cost dominant. | Rejected for V1 |
| **Multiple providers from day one** | Removes single-vendor risk, but doubles prompt tuning, evaluation, and failure modes at the point where the pipeline itself is not yet proven. The abstraction preserves this option at near-zero cost, so it can be adopted when there is evidence it is needed. | Rejected as premature |

## Consequences

**Accepted benefits**

- Schema-constrained output makes malformed responses an exception to be validated against, rather than the normal case to be parsed defensively.
- A single credential and one integration surface keeps Version 1 small.
- Tiered models allow cost to be tuned per step without changing the architecture.
- The abstraction means a provider swap touches one module, not every workflow.

**Accepted costs**

- **Cost scales linearly with volume.** At the reference workload this is significant and must be actively managed: classify against a truncated body, use the cheapest model that passes evaluation for classification, and generate drafts only when `requires_draft` is true.
- **Provider availability becomes system availability.** Retries and the attempts table handle transient failures, but a sustained outage stalls the pipeline. Version 1 accepts this; a fallback provider is deferred to the point where the abstraction makes it cheap.
- **Email content leaves the trust boundary.** For this portfolio project only fictional test data is used. Any real deployment requires a data processing agreement, retention and training-use controls confirmed in writing, redaction of obvious secrets before transmission, and an explicit answer on data residency.
- **Pinned models get deprecated.** Migration is not automatic and cannot be assumed safe. A labelled evaluation set is needed before any model change so that a swap can be measured rather than hoped for. That evaluation set does not exist yet and is a prerequisite for the first model upgrade.
- **Retries are not reproducible.** Even at low temperature, the same prompt may yield a different answer. The system must reuse a stored successful result via its idempotency key rather than re-calling the model and assuming agreement — the mechanism specified in ADR-003.
- **The abstraction must be enforced.** Its value disappears the moment a workflow calls the vendor API directly. Any such call is a defect, not a shortcut.
