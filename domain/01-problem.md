# The problem

## Context

This PoC exists as a portfolio piece for the **Software Engineer, AI & Data** application at Maersk
(Copenhagen, ref. [R193814](https://www.maersk.com/careers/vacancies/wd/Software-Engineer_R193814/jt-software-engineer)).

The posting asks for: agentic AI, data pipelines, Python/SQL backend, Azure, CI/CD, observability, and
SAP/non-SAP integrations. The real gap against the role isn't "knowing how to code" — it's
demonstrating Python + data engineering + Azure + agents in a real project, with verifiable evidence,
not a smoke-and-mirrors demo.

## Why "Port Intelligence Agent"

We need a domain that:

- Uses **real, public data**, not synthetic — immediate credibility.
- Is **maritime and Danish** — a direct mirror of Maersk's business.
- Has enough temporal and spatial structure to justify a serious data pipeline
  (streaming, geofencing, aggregations), not a CRUD app disguised as an "agent".
- Supports genuine business questions that an agent with typed tools can answer better than
  a static dashboard.

The source: AIS (Automatic Identification System) data from the **Danish Maritime Authority**
(historical, open, and free) or **AISStream** for a real-time variant. Every vessel broadcasts its
position, heading, and speed every few seconds — the same kind of operational signal that feeds
scheduling and port-capacity decisions at a shipping line.

## The question the system needs to answer

> "How is congestion at the port of Aarhus this week, and how does it compare with the call history
> of a specific vessel?"

That forces solving, in layers:

1. **Ingestion** of a noisy geospatial event stream, reliably.
2. **Transformation** of raw positions into business events (arrival, departure, dwell time,
   congestion).
3. **Exposure** of those metrics to an agent that answers in natural language without hallucinating
   numbers.
4. **Verification** that the agent answers correctly — not a demo, an evaluated system.

## What this PoC is NOT

- Not a generic chatbot over maritime data.
- Not free text-to-SQL against the database — that's plausible-but-fragile, and exactly the pattern
  an enterprise platform team cannot ship to production without heavy sandboxing.
- Not aiming for global port coverage or production-grade real-time — it aims for demonstrable depth
  within a bounded scope.

## Success criteria

The repo should be able to answer, with evidence:

- Does the pipeline work end-to-end with real data?
- Does the agent answer with correct data, measured against an eval set with golden answers?
- Does it run on Azure, even at a reduced scale?
- Is there an explicit security posture for the agentic pattern (not just "it works")?

See [02-architecture.md](02-architecture.md) for the design, [05-agent-tools-eval.md](05-agent-tools-eval.md)
for how the agent's success is measured, and [07-scope-cutlines.md](07-scope-cutlines.md) for what's
in and out of scope for a long weekend.
