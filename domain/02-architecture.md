# Architecture

## Overview

The system has three blocks: **data ingestion/pipeline**, **semantic layer + agent**, and
**backend/observability**. Each one can be run, tested, and deployed independently.

```mermaid
flowchart LR
    subgraph Source
        AIS["Danish Maritime Authority\n(historical) / AISStream\n(real-time)"]
    end

    subgraph Ingestion["Ingestion (Azure)"]
        EH["Event Hubs"]
        CONS["Python Consumer"]
    end

    subgraph Lake["Data Lake (Blob + Parquet)"]
        BRONZE[("Bronze\nraw AIS")]
        SILVER[("Silver\ncleaned + geofenced")]
        GOLD[("Gold\ndbt marts")]
    end

    subgraph Query["Query engine"]
        DUCK["DuckDB / Postgres"]
    end

    subgraph Agent["Agentic layer"]
        LLM["Agent (typed tools)"]
        T1["port_congestion"]
        T2["vessel_history"]
        T3["port_lookup"]
    end

    subgraph API["Backend"]
        FASTAPI["FastAPI"]
        SAP["Mock SAP OData"]
    end

    subgraph Obs["Observability"]
        OTEL["OpenTelemetry"]
    end

    AIS --> EH --> CONS --> BRONZE
    BRONZE -- "dbt: clean + geofence" --> SILVER
    SILVER -- "dbt: aggregations" --> GOLD
    GOLD --> DUCK
    DUCK --> T1 & T2 & T3
    T1 & T2 & T3 --> LLM
    LLM --> FASTAPI
    FASTAPI --> SAP
    FASTAPI -. trace .-> OTEL
    LLM -. trace tool calls .-> OTEL
```

## Layer model (medallion)

Full schema detail in [04-data-model.md](04-data-model.md). In short:

- **Bronze**: raw AIS messages, append-only, untransformed.
- **Silver**: deduplicated, typed, crossed against port geofences → enter/exit events.
- **Gold**: business-ready dbt marts (dwell time, daily congestion, call history).

```mermaid
flowchart TB
    A["ais_raw\n(bronze)"] -->|dedup + typing| B["vessel_position\nvessel_static\n(silver)"]
    B -->|cross with port polygons| C["port_events\nenter / exit\n(silver)"]
    C -->|dbt: consecutive enter-exit pairs| D["fct_port_calls\n(gold)"]
    D -->|dbt: daily aggregation| E["fct_port_congestion_daily\n(gold)"]
    D -->|dbt: per-vessel sequence| F["fct_vessel_voyage_history\n(gold)"]
```

## Sequence: a user query

This is the flow traced in OpenTelemetry — every tool call is recorded with latency,
tokens, and cost.

```mermaid
sequenceDiagram
    actor U as User
    participant API as FastAPI
    participant AG as Agent
    participant TL as Tool: port_lookup
    participant TC as Tool: port_congestion
    participant DB as DuckDB (gold)
    participant OT as OpenTelemetry

    U->>API: POST /query {"question": "congestion in Aarhus this week?"}
    API->>AG: invoke(question)
    AG->>OT: span: agent.run start

    AG->>TL: port_lookup("Aarhus")
    TL->>DB: SELECT port_id FROM dim_port WHERE ...
    DB-->>TL: port_id=DKAAR
    TL-->>AG: Port(id=DKAAR, name="Aarhus")
    AG->>OT: span: tool.port_lookup (latency, tokens)

    AG->>TC: port_congestion(DKAAR, last 7 days)
    TC->>DB: SELECT * FROM fct_port_congestion_daily WHERE ...
    DB-->>TC: CongestionMetrics(...)
    TC-->>AG: typed result (Pydantic)
    AG->>OT: span: tool.port_congestion (latency, tokens)

    AG-->>API: natural-language answer + cited data
    API->>OT: span: agent.run end (total cost, total latency)
    API-->>U: 200 OK
```

Key design points in this sequence:

- The agent **never** generates free-form SQL — each tool runs a fixed, parameterized query against
  the gold layer. This is what separates a "production agent" from a "text-to-SQL demo", and is the
  central argument of [05-agent-tools-eval.md](05-agent-tools-eval.md) and [06-security.md](06-security.md).
- Each tool call is an independent span — this lets you answer "why did this response take 4
  seconds?" or "how much did this query cost?" without ad-hoc instrumentation.

## Simulated enterprise integration

A mock SAP OData-style endpoint (`/sap/PortCallSet`) simulates the kind of integration the posting
mentions ("SAP and non-SAP"). It's not functional against a real SAP system — it's an OData contract
served by FastAPI that demonstrates understanding the integration pattern the role expects.

## Deployment

```mermaid
flowchart LR
    GH["GitHub Actions\n(CI/CD)"] -->|build + push| ACR["Azure Container Registry"]
    ACR --> ACA["Azure Container Apps"]
    ACA --> BLOB["Azure Blob Storage\n(Parquet lake)"]
    ACA --> EH2["Event Hubs\n(if streaming)"]
    GH -->|eval set in CI| EVAL["Eval gate\n(blocks merge on\ngolden-set regression)"]
```

The eval set runs as a CI gate, not a manual test — if a change to the tools or the agent's prompts
breaks a golden answer, the pipeline fails. See [05-agent-tools-eval.md](05-agent-tools-eval.md).

See [03-tech-stack.md](03-tech-stack.md) for why each piece was chosen, and
[07-scope-cutlines.md](07-scope-cutlines.md) for the reduced version of this diagram (batch,
1 port, local DuckDB).

## Batch → streaming migration path

This PoC is batch end to end: a fixed historical dump (14 days, Feb 2025) processed by dbt into
DuckDB. AIS itself is not naturally batch — every vessel broadcasts its position every few seconds —
so it's worth being precise about what moving to real streaming would actually require, rather than
treating it as a small config change.

**The real blocker isn't the processing engine, it's the data source.** There is no live feed behind
this project — `scripts/fetch_ais.py` downloads a static zip from the Danish Maritime Authority.
Real streaming needs a live source first: a terrestrial AIS receiver's raw NMEA output, or a paid
aggregator (Spire, MarineTraffic, AISHub). Nothing below matters until that exists.

Assuming a live feed, what changes layer by layer:

- **Ingestion**: raw NMEA sentences land on Azure Event Hubs, partitioned by MMSI (or a geohash of
  position, if the volume across many ports needs spreading across more partitions than the vessel
  count allows).
- **Bronze**: the one-time dbt parse of a CSV becomes a stream processor (Azure Stream Analytics, or
  Databricks/Spark Structured Streaming for more control) parsing NMEA into the same structured
  schema bronze already defines — the schema doesn't change, only how it gets populated.
- **Silver**: this is where streaming is a genuine *improvement*, not just a lateral move.
  [`port_events.sql`](../dbt/models/silver/port_events.sql) approximates arrival/departure with
  session-windowing (`session_gap_hours`) as a documented stand-in for real geofence-crossing
  detection, because a batch job has no notion of "the vessel just crossed the boundary." A stream
  processor does: native event-time session windows plus watermarking for AIS's routinely late or
  out-of-order pings replace the approximation with the real thing.
- **Gold**: DuckDB is an embedded, single-writer OLAP engine — a good fit for "load a batch, query
  it," a poor fit for continuous concurrent writes. `fct_port_calls` and
  `fct_port_congestion_daily` would move to a served store built for that (Postgres, or Fabric/Synapse
  if staying Azure-native), maintained as continuously-updated aggregates instead of a periodic dbt
  run — matching the "Postgres" row already called out as the full-version alternative in
  [07-scope-cutlines.md](07-scope-cutlines.md).
- **Agent tools**: barely change. `port_congestion` and `vessel_history` already query the gold layer
  through a typed interface that has no opinion on how gold got built — this isolation is exactly why
  the semantic layer exists ([09-theoretical-foundations.md](09-theoretical-foundations.md)). The
  queries stay the same; only the freshness of what they read improves, from "as of the last dbt run"
  to "as of a few seconds ago."
- **Eval set**: becomes harder, not easier. [05-agent-tools-eval.md](05-agent-tools-eval.md)'s golden
  answers assume a frozen dataset — against a live stream they'd need either a frozen historical
  replay for reproducible CI runs, or a shift from exact/tolerance checks to structural ones (right
  shape, right tool, plausible range).

**The trade-off that actually matters**: Event Hubs plus a stream processor run continuously and cost
money whether or not anyone is asking a question; a dbt batch run costs pennies and only runs on
demand. That's worth it when the product is a live dashboard where seconds of freshness matter — it's
not worth it for a PoC whose value is the agent and the eval methodology, which is why this stayed a
documented scope cut ([07-scope-cutlines.md](07-scope-cutlines.md)) rather than something to build.
