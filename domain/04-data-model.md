# Data model

Medallion architecture (bronze/silver/gold) — see [02-architecture.md](02-architecture.md) for how
data flows between layers and why they're split this way.

## Bronze — raw, append-only

No cleaning, no dedup. A faithful record of whatever came off the stream, partitioned by hour.

```
ais_raw
├── ts_utc            timestamp   -- AIS message timestamp
├── mmsi              string      -- vessel identifier (can repeat, can be missing)
├── lat, lon           float
├── sog                float      -- speed over ground (knots)
├── cog                float      -- course over ground (degrees)
├── heading            float
├── nav_status         int        -- AIS navigational status code
├── rot                float      -- rate of turn
├── msg_type           int        -- AIS message type (1/3 = position, 5 = static)
└── source_ingest_ts   timestamp  -- when our consumer received it
```

## Silver — cleaned, typed, geo-enriched

```
vessel_position                    vessel_static
├── mmsi          string           ├── mmsi          string  (PK)
├── ts_utc        timestamp        ├── imo           string
├── lat, lon       float           ├── name          string  ⚠️ see 06-security.md
├── sog            float           ├── ship_type     string
└── nav_status     int             ├── length, width  float
   (PK: mmsi + ts_utc,             ├── callsign      string
    deduplicated)                  └── flag          string
```

```
port_geofences                     port_events
├── port_id       string  (PK)     ├── mmsi          string
├── port_name     string           ├── port_id       string
├── country       string           ├── event_type    enum(enter, exit)
└── geom          polygon          └── ts_utc        timestamp
   (or center + radius if no          (derived: crossing vessel_position
    official polygon available)        against port_geofences)
```

`vessel_static` isn't always populated — AIS message type 5 (static) is transmitted far less
frequently than type 1/3 (position). The model has to tolerate null `name`/`imo` without breaking
downstream tools.

## Gold — dbt marts, the semantic layer the tools consume

```
dim_vessel                         dim_port
├── mmsi          string  (PK)     ├── port_id       string  (PK)
├── imo           string           ├── name          string
├── name          string           ├── country       string
├── ship_type     string           ├── lat, lon       float
└── flag          string           └── timezone      string
```

```
fct_port_calls
├── port_id        string
├── mmsi           string
├── arrival_ts     timestamp
├── departure_ts   timestamp
├── dwell_hours    float
└── is_anchorage   boolean
   -- dbt: consecutive (enter, exit) pairs from port_events by mmsi+port_id,
   -- filtered to commercial ship_type (see "Commercial traffic filter" below)
```

### Commercial traffic filter (validated in Phase 0 with real data)

`fct_port_calls` does **not** include every vessel that passes through the geofence — only
commercial ones. Exploring 14 real days of Aarhus data
([notebooks/01_aarhus_7day_trend.ipynb](../notebooks/01_aarhus_7day_trend.ipynb)) showed that most
vessels present *every single day* aren't port calls at all — they're local service fleet (tugs,
pilotage, ferries). Counted the same as a cargo ship or tanker, the congestion metric ends up
dominated by vessels that never "wait their turn", they just operate there.

```sql
-- include
ship_type IN ('Cargo', 'Tanker', 'Container', 'Bulk carrier')
-- explicitly exclude
ship_type IN ('Tug', 'Pilot', 'Port tender', 'HSC', 'Passenger', 'Pleasure',
              'SAR', 'Dredging', 'Law enforcement', 'Military', 'Fishing')
```

This filter is validated by the vessel's declared function (`ship_type`), not by a "days present in
the sampling window" threshold — a day-count threshold is an artifact of how many days were
downloaded, while ship type is a stable property independent of the window.

```
fct_port_congestion_daily
├── port_id            string
├── date               date
├── vessels_in_port    int
├── vessels_waiting    int
├── avg_dwell_hours    float
├── dwell_hours_p90    float
└── trend_7d           float     -- % change vs. the mean of the previous 7 days
   -- dbt: daily aggregation over fct_port_calls
```

```
fct_vessel_voyage_history
├── mmsi           string
├── seq_num        int          -- chronological order of the vessel's calls
├── port_id        string
├── arrival_ts     timestamp
└── departure_ts   timestamp
   -- dbt: fct_port_calls ordered by mmsi + arrival_ts
```

`fct_port_congestion_daily` is the table the `port_congestion` tool relies on — without real data
there, the agent's answer would be a well-disguised hallucination.

## dbt test contracts (minimum)

- `not_null` + `unique` on the PK of every dim/fct.
- `relationships` from `fct_port_calls.port_id` → `dim_port.port_id`.
- `accepted_range` on `dwell_hours`: only `>= 0`, **no ceiling rejecting high values as an
  error.** Phase 0 found a real case (MMSI 249637000, "TZAREVNA", a 169m cargo ship, 14 days
  moored without moving, declared destination = the port itself) — a real port call can last
  weeks. A test that discards this as a "geofencing bug" would be discarding valid data.
  If the goal is to genuinely detect a geofencing bug (a vessel that never leaves), the right
  signal is crossing a high `dwell_hours` with a sustained average `SOG` ≈ 0 — not a fixed hour
  ceiling.

For the same reason, `avg_dwell_hours` in `fct_port_congestion_daily` should always be read
alongside `dwell_hours_p90` — with few vessels per day ([08-phases.md](08-phases.md)), a single
long call like the one above distorts the average far more than it would at a high-volume port.

## Where each tool draws from

See the full contract for each tool in [05-agent-tools-eval.md](05-agent-tools-eval.md):

- `port_lookup` → `dim_port`
- `port_congestion` → `fct_port_congestion_daily`
- `vessel_history` → `fct_vessel_voyage_history` (+ `dim_vessel` for the name)
