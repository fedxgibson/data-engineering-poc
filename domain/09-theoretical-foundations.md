# Theoretical foundations: Phase 0, Phase 1, and Phase 2

This document doesn't describe *what* was built (that's in [08-phases.md](08-phases.md) and the
code) but *why* each piece exists: what conceptual problem it solves, what area of data-systems
theory it comes from, and what alternative was discarded and why. It's the basis for defending every
decision in an interview without resorting to "because that's how it's done".

Each section follows the same format: **what it is** → **what problem it solves** → **where it was
applied**.

---

## Phase 0 — Data validation

### AIS (Automatic Identification System)

**What it is**: a VHF radio protocol mandatory under the SOLAS convention for vessels above a certain
tonnage. Every vessel transmits two main message types: *position* (type 1/3 — lat/lon, heading,
speed, every few seconds) and *static/voyage* (type 5 — name, IMO, draught, destination, transmitted
much less often). Shore-based stations and satellites capture and relay it.

**What problem it solves**: it's the only public source of maritime telemetry with enough temporal
and spatial resolution to infer business events (arrival, departure, congestion) without depending on
a proprietary port or carrier system.

**A structural limitation worth knowing**: the fields are *self-reported* by the vessel, not
verified by a third party — which is why Phase 0 measured real `Name`/`IMO` coverage instead of
assuming they'd always be populated ([00_explore_ais_data.ipynb](../notebooks/00_explore_ais_data.ipynb)).

### Batch vs. streaming: why we started in batch

**What it is**: two ingestion paradigms. *Batch* processes a bounded set of data already at rest, in
reproducible passes. *Streaming* processes an unbounded flow with low latency, and forces you to
solve problems that don't exist in batch (windowing, watermarks, at-least-once/exactly-once
delivery).

**What problem choosing batch solves here**: Phase 0 needs to iterate quickly on the shape of the
data (how much coverage does `Name` have? is position frequency enough?) — questions that are
cheaper to answer by re-reading a fixed file than by operating an Event Hubs consumer. The full
design ([02-architecture.md](02-architecture.md)) does include streaming as the production version;
the trade-off documented in [07-scope-cutlines.md](07-scope-cutlines.md) is explicitly "latency vs.
infrastructure complexity", not "streaming is better than batch in the abstract" — for validating a
data model, batch is the right tool.

### Geofencing by bounding box (instead of a polygon)

**What it is**: geofencing is determining whether a point (lat/lon) falls inside a region of
interest. The most precise form is a polygon (point-in-polygon); the simplest is a rectangular box
(`lat BETWEEN ... AND lon BETWEEN ...`).

**What problem using a bbox solves**: a polygon needs the port's real geometry (not always available
without a license) and a spatial extension in the query engine. A bbox is two numeric comparisons —
trivial to index, trivial to reason about, and enough when the cost of a false positive (water
outside the port but inside the box) is low compared to the cost of building exact geometry.
`domain/04-data-model.md` already documented this as an accepted fallback ("or center + radius if no
official polygon is available") — Phase 0 executed it that way from day one.

### Columnar format (Parquet) as a cache for intermediate results

**What it is**: Parquet stores by column, not by row. For analytical workloads (aggregating,
filtering by a few columns over many rows) this is far more efficient than row-by-row CSV: only the
needed column gets read, it compresses better (values of the same type and domain end up
contiguous), and it enables *predicate pushdown* (skipping whole blocks that don't match a filter).

**What problem it solves here**: it avoids re-reading and re-filtering 3.1GB of national CSV every
time a new question about Aarhus comes up. The pattern (`scripts/fetch_ais.py`) downloads and filters
once, writes one Parquet file per day, and every later notebook or dbt model reads that Parquet — the
same *incremental materialization* principle that underpins the entire Phase 1 medallion
architecture.

### Out-of-core processing (chunking)

**What it is**: a technique for processing a dataset larger than available memory, reading it in
bounded fragments (*chunks*) and accumulating only the partial result that matters, instead of
materializing the whole dataset in RAM.

**What problem it solves**: a single day's CSV is 3.1GB uncompressed; loading it entirely into a
pandas `DataFrame` is unnecessary when the final target is a subset of ~120,000 rows (0.7% of the
total). `pd.read_csv(..., chunksize=500_000)` over the zip's stream
([fetch_ais.py](../scripts/fetch_ais.py)) applies the bounding-box filter chunk by chunk and discards
the rest — bounded memory, independent of the source file's size.

### DuckDB as an embedded analytical engine (OLAP)

**What it is**: DuckDB is a *columnar*, *vectorized* database engine that runs embedded in the
process (no separate server), built for analytical workloads (OLAP) rather than transactional ones
(OLTP). "Vectorized" means it operates on blocks of values at a time, not row by row — which is why
aggregations over millions of rows are fast without needing a cluster.

**What problem it solves**: it lets you query the Parquet files directly with SQL
(`read_parquet(glob)`) with no prior load step into a database — the file *is* the table. This is
what makes it feasible to run all of Phase 1 on a laptop without standing up Postgres or a cloud
warehouse, and it's consistent with DuckDB's role as documented in [03-tech-stack.md](03-tech-stack.md)
as the PoC's query engine.

### The principle behind all of Phase 0: validate before designing

**What it is**: in data engineering, designing a schema or a pipeline *before* looking at the real
data is a bet that your assumptions about the domain are correct. The alternative — explore first,
commit to a schema afterward — is slower up front but avoids rewriting work when reality doesn't
match the assumption.

**What problem it solves**: exactly the two findings that changed this project's design — the
`Ship type` filter and the TZAREVNA case — only surface if you look at the data before writing dbt.
Designing `fct_port_congestion_daily` without this step would have produced a "congestion" metric
dominated by tugboats, with nothing in the code flagging it as wrong.

### Metrics for deciding "is there signal or is it noise?"

- **Coverage %** (`pct_known`): the fraction of non-null / non-"Unknown" values in a field. It's the
  simplest data-completeness metric, and the one that decides whether a field can be a PK or has to
  be treated as optional.
- **Coefficient of variation** (`std / mean`): normalizes the standard deviation by the mean, which
  lets you compare "how much something varies" independent of its scale. A CV of 0.12 over
  ~24 vessels/day (see [01_aarhus_7day_trend.ipynb](../notebooks/01_aarhus_7day_trend.ipynb)) says
  "there's real variation, but it's narrow" — a reading the mean and the deviation on their own
  don't give as directly.
- **Percentiles (p50/p90/p99)** instead of just the average: under long-tailed distributions (like
  `dwell_hours`, with the 335-hour TZAREVNA case), the average gets distorted by a few extreme
  values. The 90th percentile describes "what most cases look like, ignoring the extremes" far more
  robustly — which is why `fct_port_congestion_daily` reports `dwell_hours_p90` alongside
  `avg_dwell_hours`.

### Notebooks as a disposable tool

**What it is**: a Jupyter notebook combines executable code with its output and explanatory prose in
the same unit (*literate programming*), and keeps state between cells — you can inspect an
intermediate variable without re-running everything from scratch.

**What problem it solves, and what it doesn't**: it's ideal for one-off exploration, where the value
is in iterating fast and seeing intermediate results (charts, tables). It's not ideal as production
code: hidden state between cells can mask execution-order bugs, and it's hard to test. That's why the
download+filter function was written once in [scripts/fetch_ais.py](../scripts/fetch_ais.py) —
reusable, importable, testable — and the notebooks just *call* it and do the exploratory analysis
around it. It's the concrete application of the rule "whatever survives exploration moves into a
module".

---

## Phase 1 — Data pipeline

### Medallion architecture: why three layers and not one

**What it is**: a *multi-hop* pattern where data advances through layers of increasing refinement
(bronze → silver → gold), each materialized separately.

**What problem it solves**: separation of concerns between "fidelity to the source" (bronze),
"correctness and cleaning" (silver), and "business shape" (gold). The concrete advantage this
project got from it: when the `ship_type` filter finding surfaced, it was enough to change
`dim_vessel` (gold) — bronze and silver weren't touched, because the problem was a business
definition issue ("what counts as a port call"), not a data-quality one. If everything lived in one
layer, that change would have been much harder to isolate and test.

### dbt and the ELT paradigm

**What it is**: dbt (*data build tool*) doesn't extract or load data — it assumes it's already in
the warehouse (or, as here, accessible as files) and handles only the **T** in ETL: transformation,
written as declarative SQL. Every model is a `SELECT` describing the desired final state of a table,
not a sequence of imperative steps. dbt compiles the `{{ ref(...) }}` references between models into
a dependency graph (DAG) and automatically figures out execution order.

**Why ELT and not classic ETL**: with modern query engines (DuckDB, cloud warehouses), it's cheaper
to load raw data and transform it *inside* the engine with SQL than to maintain an external process
(Python/Spark) doing the transformation before loading. Declarative SQL is also more readable and
auditable for a data team than an equivalent imperative script.

**What problem dbt specifically solves here**: it gives versioning, testing (see below), and lineage
(`dbt docs generate` can show the full bronze→silver→gold graph) for free, without writing your own
infrastructure for it — the reason it was chosen over "loose Python scripts transforming data", as
already argued in [03-tech-stack.md](03-tech-stack.md).

### Dimensional model (Kimball): facts and dimensions

**What it is**: an analytical modeling pattern where tables are split into **dimensions**
(descriptive entities that change with low cardinality — `dim_vessel`, `dim_port`) and **facts**
(events or measurements, high-cardinality — `fct_port_calls`, one row per port call).

**What problem it solves**: facts can be aggregated (`fct_port_congestion_daily` is literally an
aggregation of `fct_port_calls`) and dimensions can be enriched (adding `flag` to `dim_vessel`
tomorrow breaks nothing that already queries the table) independently of each other. It's also the
model that makes the agent's tools trivial ([05-agent-tools-eval.md](05-agent-tools-eval.md)):
`port_congestion` is a `SELECT` with a `WHERE` over an already-aggregated fact table, not an ad-hoc
query joining five sources in real time.

### Deduplication: where duplicates come from and how to handle them

**What it is**: in systems with multiple receivers observing the same event (here: several
shore-based AIS stations receiving the same vessel transmission), it's normal to receive the same
message more than once. It's a *delivery semantics* problem — the same kind of problem streaming
systems solve with "exactly-once" guarantees, applied here in batch.

**What problem it solves**: Phase 0 detected median gaps of 2 seconds between messages from the same
vessel — suspiciously low for the real cadence of AIS transmission, a sign of duplicates.
`stg_ais_raw` handles the trivial case (`SELECT DISTINCT` over identical rows); `stg_vessel_position`
handles the case of the same `mmsi`+`ts_utc` with slightly different values via
`ROW_NUMBER() OVER (PARTITION BY mmsi, ts_utc ORDER BY ts_utc)`, keeping a single row per key. Without
this step, any event count (`vessels_in_port`, number of calls) would be inflated.

### Window functions: `LAG`/`LEAD` and `ROW_NUMBER`

**What they are**: unlike `GROUP BY` (which collapses rows into one), a window function computes a
value *relative to other rows* without losing individual row detail — for example, "what was this
same vessel's previous timestamp?" (`LAG`) or "what's this row's order number within its group?"
(`ROW_NUMBER`).

**What problem it solves**: they're the natural tool for reasoning about per-entity time series
without leaving declarative SQL. `port_events.sql` uses `LAG`/`LEAD` to compare each message's
timestamp against the previous and next one for the same `mmsi`; `fct_vessel_voyage_history.sql` uses
`ROW_NUMBER` to number a vessel's calls in chronological order.

### Session windowing: from web analytics to maritime geofencing

**What it is**: a technique originating in web analytics to group a single user's events into
"sessions", separated by an inactivity threshold (e.g., 30 minutes with no activity = a new session).
The event itself doesn't mark the session boundary — the *gap* between consecutive events does.

**What problem it solves, and why it replaced the original design here**: the design in
`04-data-model.md` assumed `port_events` would be derived from a literal inside/outside crossing of
a polygon (point-in-polygon). But the source data already came pre-filtered to Aarhus's bounding box
from Phase 0 — there are no "outside" positions to detect that crossing against. The same web-session
logic applies directly: if a vessel disappears from the area for longer than a threshold
(`session_gap_hours = 4`), it's interpreted as having left and come back as a new call. It's a
concrete example of a general engineering principle: **the derivation method adapts to the data
available; the output contract (schema) stays the same** — documented explicitly in the model itself
([port_events.sql](../dbt/models/silver/port_events.sql)) so whoever reads it understands it's a
decision, not an oversight.

### Data testing as a contract

**What it is**: just as software testing verifies behavioral invariants of code, data testing
(dbt `tests`) verifies invariants of the data itself: uniqueness of a key (`unique`), absence of
nulls (`not_null`), referential integrity (`relationships`), or that a value falls within a valid
range (`accepted_range`). Run on every `dbt run`/`dbt test`, they act as a contract that any future
change to the pipeline has to keep satisfying.

**Why the `dwell_hours` test has no ceiling**: a naive test would say "no call lasts more than N
days, so let's cap it". But the real TZAREVNA case (335.9 hours, a vessel sitting still with
`SOG ≈ 0`) shows a long call is a valid business fact, not an error. The right distinction between
"this is a statistical outlier" and "this is a geofencing bug" isn't an hour threshold — it's
crossing a high `dwell_hours` with a sustained average speed ≈ 0, something that requires domain
reasoning, not just statistics. This is the same principle behind [06-security.md](06-security.md):
automated rules are necessary but don't replace judgment about what the data means in the real
domain.

### Seeds: versioned reference data

**What it is**: dbt treats small, relatively static CSV files (`seeds/`) as reference data loaded as
version-controlled tables in git, instead of hardcoding them inside a SQL query or keeping them in a
separate spreadsheet.

**What problem it solves**: `port_geofences.csv` (Aarhus's bbox) and `ship_type_classification.csv`
(which vessel types count as commercial traffic) are exactly that kind of data — small, rarely
changing, and needed consistently by multiple models. Putting it in a seed instead of repeating the
list of commercial types inline in every gold model means changing a vessel type's classification is
a one-row edit in a CSV, versioned and auditable, not a search through every place the value was
copied.

### Embedded warehouse and reproducibility

**What it is**: `data/warehouse.duckdb` is a single binary file containing every table dbt
materializes. There's no separate database server to manage.

**What problem it solves**: full pipeline reproducibility. Deleting that file and running
`dbt seed && dbt run && dbt test` again rebuilds exactly the same state from the Parquet files in
`data/interim/` — there's no hidden state on a server that depends on prior manual steps. It's the
*idempotency* property expected of any serious data pipeline, and the reason the `.duckdb` file is in
`.gitignore`: it's a derived, regenerable artifact, not a source of truth.

---

## Phase 2 — Agentic layer

### Typed tools as capabilities, not direct data access

**What it is**: instead of giving the LLM a database connection or the ability to generate free SQL,
it gets a fixed, small menu of functions (`port_lookup`, `port_congestion`, `vessel_history`), each
with a validated input contract (Pydantic) and a **fixed** SQL query, written in advance. The model
decides *which* tool to call and *with what parameters* — never *what operation* runs against the
data. It's the concrete application of **capability-based security**: an actor can only do what the
capabilities it was handed allow, not whatever is technically possible in the system.

**What problem it solves**: it bounds the blast radius of any model failure — a hallucination, a
badly written prompt, poisoned data like the Phase 2 injection case
([05-agent-tools-eval.md](05-agent-tools-eval.md)) — to whatever the specific tool allows, never to
"whatever the model feels like writing". It's also the precondition for the eval set to compare
**structured fields** against golden values with numeric tolerance: if the model generated free SQL,
every question would produce a different query and there'd be no way to write a deterministic test,
only "does the text answer sound reasonable?" — the kind of weak evaluation this project deliberately
avoids.

### Facade pattern: stable contract, replaceable implementation

**What it is**: the tool is the public interface; the gold dbt model behind it is the
implementation. As long as `port_congestion(port_id, date_from, date_to)` keeps accepting those
parameters and returning the same shape, the logic in `fct_port_congestion_daily` can change freely
(a different percentile calculation, a different database, a different engine) without the agent
knowing.

**What problem it solves**: it decouples the data layer's evolution from the agent's evolution. It's
the same principle behind a versioned HTTP API or a repository in classic software architecture —
separating "what can be asked for" from "how it gets resolved".

### The absence of a capability is a reviewed decision, not an accident

**What it is**: if the agent can't answer something, it's because that specific tool doesn't exist —
not because the model "isn't smart enough".

**Real example**: asking the agent for "a list of vessels sorted by dwell time" fails explicitly
(see `eval_13` in [05-agent-tools-eval.md](05-agent-tools-eval.md)) because none of the 3 tools
returns a list of vessels with individual dwell times — `port_congestion` gives port-level
aggregates, `vessel_history` requires a specific MMSI. With free text-to-SQL, the model would "solve"
this on its own, with nobody reviewing the resulting query, its permissions, or whether the eval set
covers it. With fixed tools, adding that capability requires a deliberate step: a new function, a new
test, a new golden case — the same least-privilege principle applied to *functionality*, not just
data.

### Isolating agent state per request (`contextvars`)

**What it is**: `agent/tools.py` logs every tool call in a record the eval harness and the API use to
audit what ran. The first version stored it in a global Python list — it worked in the eval, which
runs one question at a time, but it would have silently corrupted under FastAPI, where the same
process serves concurrent requests.

**What problem it solves**: `contextvars.ContextVar` isolates that state per async task/thread
instead of sharing it across the whole process — the same API frameworks like FastAPI/Starlette use
to propagate request context without passing it explicitly through every function. It's a concrete
reminder that a design valid for a sequential script (the eval) can be incorrect under real
concurrency (the API), and that a change in execution context deserves revisiting assumptions about
shared state.

### The system prompt as operational context, not "personality"

**What it is**: beyond instructing *how* to behave, the system prompt can carry concrete facts about
the system's current state — here, the dataset's real date range — computed dynamically on every
call, not hardcoded.

**What problem it solves**: without that fact, a question like "the last week of data" forces the
model to *discover* the range by trial and error, calling `port_congestion` with arbitrary ranges
until it finds one with data — in one real run, 23 calls before getting it right. Giving it that fact
up front isn't "cheating" for the agent: it's the same logic as not forcing a system to brute-force
infer something the backend already knows for certain. The fix dropped that question from 23 tool
calls to 2 without changing behavior on any other eval-set case.

---

## Summary: concept → why → where

| Concept | Solves | File/model |
|---|---|---|
| Batch before streaming | Iterate quickly on the shape of the data | [scripts/fetch_ais.py](../scripts/fetch_ais.py) |
| Bbox geofencing | Simplicity with no real polygon geometry | `port_geofences` seed |
| Parquet + incremental cache | No re-scanning 3.1GB per question | `data/interim/*.parquet` |
| Chunking (out-of-core) | Bounded memory over large files | `fetch_ais.py::filter_day_to_bbox` |
| Embedded DuckDB | Analytical SQL with no server | `dbt/profiles.yml`, notebooks |
| Coverage / CV / percentiles | Deciding "is there signal or noise?" with numbers | notebooks 00 and 01 |
| Medallion (bronze/silver/gold) | Isolating business changes from quality changes | `dbt/models/*` |
| Declarative ELT (dbt) | Testing + lineage with no custom infrastructure | `dbt/dbt_project.yml` |
| Dimensional model | Agent tools as simple `SELECT`s | `dim_vessel`, `fct_port_calls` |
| Deduplication | Multiple base stations see the same message | `stg_ais_raw`, `stg_vessel_position` |
| Window functions | Per-entity time series in pure SQL | `port_events.sql` |
| Session windowing | Adapting the method to the available data | `port_events.sql` |
| Data testing as a contract | Verifiable invariants on every run | `_silver__schema.yml`, `_gold__schema.yml` |
| Versioned seeds | Auditable reference data, not hardcoded | `seeds/*.csv` |
| Embedded warehouse | An idempotent, reproducible pipeline | `data/warehouse.duckdb` (gitignored) |
| Typed tools (capability-based security) | Bounding the model's blast radius, not trusting free SQL | `agent/tools.py` |
| Facade pattern | Stable interface, replaceable data implementation | tools → gold models |
| Missing capability as a reviewed decision | New functionality needs a tool + test, not model "magic" | `eval_13` finding |
| `contextvars` for per-request state | Isolating logs across the API's concurrent requests | `agent/tools.py::_call_log_var` |
| Data range in the system prompt | Stopping the agent from brute-forcing what the backend already knows | `agent/runner.py::_data_range_hint` |
