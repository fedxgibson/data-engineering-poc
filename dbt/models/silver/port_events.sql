{#
  Silver: enter/exit events per mmsi.

  IMPORTANT -- documented deviation from the original design (domain/04-data-model.md):
  that document describes port_events as "crossing vessel_position against
  port_geofences" (inside/outside the polygon). But the source data
  (data/interim/aarhus-*.parquet) already comes filtered to Aarhus's bounding
  box from Phase 0 -- every row in this dataset is, by construction, INSIDE
  the geofence. There are no "outside" positions to detect a real crossing
  against.

  Instead, we derive arrival/departure by presence session: if a vessel
  disappears from the area for longer than `session_gap_hours`, it's assumed
  to have left, and a later message is treated as a new call. This is the
  standard "session windowing" technique (the same logic as web session
  analysis), applied to geographic presence instead of an inactivity timeout.
  The output contract (mmsi, port_id, event_type, ts_utc) is identical to what
  domain/04-data-model.md documents -- what changes is the derivation method,
  not the schema.
#}

{% set gap_hours = var('session_gap_hours', 4) %}

with position as (

    select mmsi, ts_utc
    from {{ ref('stg_vessel_position') }}

),

with_neighbors as (

    select
        mmsi,
        ts_utc,
        lag(ts_utc) over (partition by mmsi order by ts_utc)  as prev_ts,
        lead(ts_utc) over (partition by mmsi order by ts_utc) as next_ts
    from position

),

flagged as (

    select
        mmsi,
        ts_utc,
        (prev_ts is null or date_diff('hour', prev_ts, ts_utc) >= {{ gap_hours }}) as is_arrival,
        (next_ts is null or date_diff('hour', ts_utc, next_ts) >= {{ gap_hours }}) as is_departure
    from with_neighbors

)

select mmsi, 'DKAAR' as port_id, ts_utc, 'enter' as event_type
from flagged
where is_arrival

union all

select mmsi, 'DKAAR' as port_id, ts_utc, 'exit' as event_type
from flagged
where is_departure
