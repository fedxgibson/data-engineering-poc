# Port Intelligence Agent

A PoC built as a portfolio piece for the **Software Engineer, AI & Data** application at
Maersk ([R193814](https://www.maersk.com/careers/vacancies/wd/Software-Engineer_R193814/jt-software-engineer)).

An agent that answers questions about port congestion and vessel call history from real AIS data
(Danish Maritime Authority), over typed tools — no free text-to-SQL — with an eval set versioned in
CI instead of a one-off demo.

## Problem

The posting asks for agentic AI + data engineering + Python/Azure + enterprise integrations. This
project attacks those four axes directly, with real Danish maritime data — the same domain as
Maersk. Full detail in [domain/01-problem.md](domain/01-problem.md).

## Architecture

Ingestion (Event Hubs) → bronze/silver/gold lake (Blob + Parquet + dbt) → semantic layer
(DuckDB/Postgres) → agent with typed tools → FastAPI + mock SAP OData, all traced with
OpenTelemetry.

Full diagrams (architecture, layer model, query sequence, deployment) in
[domain/02-architecture.md](domain/02-architecture.md).

## Eval results

Real run against the Claude API (`claude-opus-5`), 15 questions, over the real Aarhus warehouse
(14 days, Feb 2025) + 1 synthetic fixture for the prompt injection case. See categories and
methodology in [domain/05-agent-tools-eval.md](domain/05-agent-tools-eval.md).

| Metric | Value |
|---|---|
| Correct answers / total | 13/15 automatic (2 flagged for manual review, both correct behavior) |
| Average latency per question | 7.3 s |
| Total eval set cost | $0.34 |
| Average cost per query | $0.023 |
| Prompt injection cases blocked | 2/2 — the agent cited the payload as literal data, never executed it or revealed internal instructions |

The two non-automated items ask things no clean structured check can verify: `eval_13` asks for
something no tool supports (listing vessels by date), and `eval_06` asks about a date range entirely
outside the dataset. In both, the agent explicitly acknowledged the limit and didn't invent an
answer — see the detail in [domain/05-agent-tools-eval.md](domain/05-agent-tools-eval.md).

## Cost per query

$0.023 average per question with `claude-opus-5` (input + output tokens accumulated across all of a
question's tool calls, measured directly from each response's `usage` — see
[eval/run_eval.py](eval/run_eval.py)). In production this would be measured via OpenTelemetry
(Phase 4, [domain/08-phases.md](domain/08-phases.md)); here it was measured directly because the
eval set's volume doesn't justify that yet.

Real finding from Phase 3 while testing the API with open-ended questions (not the eval set's):
a question like "the last week of data" made the agent probe date ranges blindly — one real run hit
23 calls to `port_congestion` (from 2019 to 2025) before landing on the dataset's real 14-day range.
Fixed by injecting the real date range into the system prompt
([agent/runner.py](agent/runner.py)), which dropped that same question to 2 tool calls. That's why
this table's average cost can vary depending on exactly which questions get run — the fixed eval set
didn't show it because its questions already come with an explicit date range.

## Design documentation

| Document | Content |
|---|---|
| [domain/01-problem.md](domain/01-problem.md) | What problem it solves and why this domain |
| [domain/02-architecture.md](domain/02-architecture.md) | Architecture, mermaid diagrams, sequences, deployment |
| [domain/03-tech-stack.md](domain/03-tech-stack.md) | Chosen stack and why, discarded alternatives |
| [domain/04-data-model.md](domain/04-data-model.md) | Bronze/silver/gold schema |
| [domain/05-agent-tools-eval.md](domain/05-agent-tools-eval.md) | Tool contracts + eval set design |
| [domain/06-security.md](domain/06-security.md) | Threat model: prompt injection, least-privilege, tenant scoping |
| [domain/07-scope-cutlines.md](domain/07-scope-cutlines.md) | What gets cut and what doesn't if time is tight |
| [domain/08-phases.md](domain/08-phases.md) | Implementation phases, in order, each with a deliverable and a gate |
| [domain/09-theoretical-foundations.md](domain/09-theoretical-foundations.md) | Theoretical grounding: what each tool/technique is and why it was used (Phases 0-2) |

## Video

3-minute Loom: *(link to be added)*

## Status

- **Phase 0** (data validation) — complete: [notebooks/](notebooks/).
- **Phase 1** (bronze/silver/gold pipeline) — complete: [dbt/](dbt/), 19/19 tests green.
- **Phase 2** (agent + eval set) — complete: [agent/](agent/), [eval/](eval/), 13/15 PASS + 2 correct manual.
- **Phase 3** (FastAPI backend + mock SAP OData) — complete: [api/](api/), API-key auth, rate limiting (30/min) verified, `/query` and `/sap/PortCallSet` tested with real data.
- **Phase 4** (OpenTelemetry observability) — complete: [agent/tracing.py](agent/tracing.py), a span per tool call + a span per request + an HTTP span, all nested under one trace_id — see real evidence in [domain/08-phases.md](domain/08-phases.md#real-evidence-implemented).
- **Phase 5** (CI/CD + Azure) — pending.
- **Phase 6** (wrap-up: README + Loom) — pending.

Detail on each phase in [domain/08-phases.md](domain/08-phases.md).
