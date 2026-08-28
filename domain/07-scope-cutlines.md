# Scope cutlines

This document exists to avoid scope creep and to be able to talk about trade-offs with judgment in
the interview — "why I didn't do X" is as strong an argument as "why I did Y".

## Full version vs. long-weekend cut

| Dimension | Full version | Minimal cut (weekend) |
|---|---|---|
| Ingestion | Streaming via Event Hubs | Batch: historical dump from the Danish Maritime Authority |
| Query engine | Postgres (or a hybrid DuckDB + Postgres) | Local DuckDB, no server |
| Ports covered | Several | Just one (Aarhus or Copenhagen) |
| Agent tools | 4 (`port_lookup`, `port_congestion`, `vessel_history`, `compare_ports`) | 3 (no `compare_ports`) |
| Eval set | 30 questions | 15 questions |
| Deploy | Azure Container Apps with Event Hubs + Blob | Same Azure Container Apps, but serving the already-processed batch |
| Secrets | Azure Key Vault | Environment variables (documented as a known gap, not hidden) |

The deploy row is deliberate: **even the minimal cut runs on Azure**. "Runs on Azure, even if small"
weighs more in the evaluation than "it's big but runs on my laptop" — that's the difference between
demonstrating the competency the posting asks for and demonstrating something else.

## What never gets cut, no matter the scope

- The eval set with golden answers running in CI — it's the project's central differentiator
  ([05-agent-tools-eval.md](05-agent-tools-eval.md)). A PoC without this is just another demo.
- Typed tools over the semantic layer (never free text-to-SQL) — it's the foundation of the security
  argument ([06-security.md](06-security.md)).
- The prompt injection case via `vessel_static.name` in the eval set — it's the domain-specific
  differentiating angle, it costs nothing to add, and it's worth a lot in the conversation.
- OpenTelemetry tracing tool calls — without this, "observability" is just a word in the README with
  no evidence behind it.

## What gets cut first if time runs short

In this order, from first to cut to last:

1. `compare_ports` (4th tool) — nice, not essential; the 3 base tools already sustain the eval set.
2. Real streaming via Event Hubs → historical batch. The bronze/silver/gold pipeline is the same,
   only the entry point changes.
3. Multiple ports → a single port. The geofencing and aggregation logic doesn't change, only the
   data volume.
4. Azure Key Vault → environment variables, explicitly documented in
   [06-security.md](06-security.md) as a known gap.

## Final deliverable (regardless of which cut is chosen)

- Repo with a one-page README: problem → architecture → eval results → cost per query
  (see the template in the [root README](../README.md)).
- A 3-minute Loom showing the real flow (not just slides).
- The link goes in the cover letter, not attached as a file.

See [08-phases.md](08-phases.md) for the concrete implementation order and at which point in each
phase each of these cuts applies.
