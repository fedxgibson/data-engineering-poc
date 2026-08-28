# Tech stack

Each choice is tied to a concrete gap against the role ([01-problem.md](01-problem.md)), not personal
preference. Where a simpler alternative exists, it's documented — and the
[minimal scope cut](07-scope-cutlines.md) uses it explicitly.

## Ingestion and streaming

| Piece | Choice | Why |
|---|---|---|
| Data source | Danish Maritime Authority (historical) / AISStream (real-time) | Real, Danish, free data — same domain as Maersk |
| Broker | Azure Event Hubs | Azure's native streaming service; demonstrates the piece of the posting that weighs heaviest as a gap ("Azure preferred") |
| Consumer | Python (`azure-eventhub`) | Same language the posting asks for, no unnecessary intermediate layers |
| Cut alternative | Batch historical dump, no Event Hubs | See [07-scope-cutlines.md](07-scope-cutlines.md) — valid for the weekend cut |

## Storage and transformation

| Piece | Choice | Why |
|---|---|---|
| Lake | Azure Blob Storage + Parquet | Standard columnar format, cheap, and Azure's native storage |
| Query engine | DuckDB (dev/PoC) or Postgres (if concurrency is needed) | DuckDB allows fast iteration over Parquet with no infra; Postgres if the mock SAP OData needs concurrent writes |
| Transformations | dbt | The de facto standard for modeling bronze→silver→gold with tests and versioned lineage — not loose Python scripts transforming data |

## Agentic layer

| Piece | Choice | Why |
|---|---|---|
| Agent framework | Typed tools over Pydantic (no heavy framework, or a minimal runner) | Avoids the free text-to-SQL trap; each tool is a function with a verifiable input/output schema |
| Model | Claude (via API) | Native support for structured tool use and good behavior rejecting instructions injected in data — relevant to [06-security.md](06-security.md) |
| Eval | Custom set of golden questions/answers, run in CI | Explicit differentiator versus "demo with no metrics" — see [05-agent-tools-eval.md](05-agent-tools-eval.md) |

## Why an LLM layer instead of a fixed menu of parametric tools

A fair objection: why not just expose `port_congestion(port_id, date_from, date_to)` as a plain form
or a parametric endpoint and let the user fill in the fields? We actually built both, on purpose —
`/sap/PortCallSet` (with `$top`) *is* that menu: instant, free, deterministic, zero hallucination
risk. `/query` is the LLM layer on top of the exact same typed tools. They coexist because they solve
different parts of the problem, not because the LLM is strictly better.

**Where the LLM earns its cost:**

- **Translating ambiguous intent into exact parameters.** A menu requires the caller to already know
  the schema — that Aarhus is `DKAAR`, that "last week" has to anchor to the end of the dataset
  (2025-02-26) rather than today. The agent resolves a typo like "Arhus" through `port_lookup`
  without anyone pre-programming that specific correction.
- **Orchestrating multiple tools from a single request.** "How's congestion in Aarhus this last
  week?" triggers `port_lookup` → `port_congestion` chained automatically. A menu would require
  someone to wire that sequence by hand, screen by screen.
- **Synthesizing several numeric outputs into a readable answer.** A p90 of 63 hours or a −18.2%
  trend means nothing out of context to a non-technical stakeholder; the agent turns raw JSON into a
  narrative that cites its sources ([06-security.md](06-security.md)'s traceability point still holds — every
  claim in the answer is tied back to a real tool call, never invented).
- **Explaining its own limits instead of failing silently.** A form with no matching field simply
  can't ask the question. Asked for a vessel ranking that no tool supports (the `eval_13` case,
  [05-agent-tools-eval.md](05-agent-tools-eval.md)), the agent explains exactly what's missing and
  offers a workaround — that's not something a static menu can do.

**Where the menu wins, no contest:** for a fixed, repeated query shape — an ops dashboard checking
congestion every morning — the menu is strictly better. Real numbers from this project: **~$0.03 and
~9 seconds per question** through the agent, versus milliseconds and $0 hitting `/sap/PortCallSet`
directly. The LLM layer is worth its cost specifically for unstructured, conversational, multi-tool
questions — not as a universal front end over every possible query.

## Backend

| Piece | Choice | Why |
|---|---|---|
| API | FastAPI | Python, typed with Pydantic, free OpenAPI — fits directly with the posting's "Python/SQL" |
| Auth | Simple API key or OAuth2 client-credentials (depending on time) | Enough to demonstrate the pattern without building an IdP |
| Rate limiting | `slowapi` or a custom middleware | A sign of operational maturity, not a cosmetic detail |
| Enterprise mock | SAP OData-style endpoint (`/sap/PortCallSet`) | Simulates the kind of integration the posting mentions without depending on a real SAP system |

## CI/CD and observability

| Piece | Choice | Why |
|---|---|---|
| CI/CD | GitHub Actions | Standard, free, and runs the eval set as a merge gate |
| Containers | Docker | Packages the consumer, API, and dbt reproducibly |
| Azure runtime | Azure Container Apps | Serverless-ish, cheap for a PoC, but genuinely "runs on Azure", not just local |
| Tracing | OpenTelemetry | Traces every agent tool call: latency, tokens, cost — this is what turns "the agent works" into "the agent is observable in production" |

## Why not [the obvious alternative]

- **Full LangChain/LlamaIndex**: adds an abstraction layer that obscures exactly what's meant to be
  shown (typed tools, explicit control). A thin, custom runner over the Claude API is more legible in
  a 10-minute code review.
- **Free text-to-SQL**: it's the "easy" solution, and exactly the pattern a platform team cannot
  approve for production without heavy sandboxing — see [06-security.md](06-security.md).
- **Kubernetes**: overkill for the size of this PoC; Container Apps demonstrates the same Azure
  competency at a fraction of the operational effort.
