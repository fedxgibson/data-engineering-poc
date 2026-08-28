{#
  Gold: consecutive (enter, exit) pairs per mmsi, filtered to commercial
  vessels via the inner join against dim_vessel (domain/04-data-model.md).

  is_anchorage stays fixed at false: with a single geofence per port
  (Phase 0/1) there's no way to distinguish an outer anchorage from a berth --
  that would need a second, inner polygon, out of scope for the minimal cut
  (domain/07-scope-cutlines.md).
#}

with events as (

    select * from {{ ref('port_events') }}

),

enters as (

    select
        mmsi, port_id, ts_utc as arrival_ts,
        row_number() over (partition by mmsi order by ts_utc) as seq
    from events
    where event_type = 'enter'

),

exits as (

    select
        mmsi, port_id, ts_utc as departure_ts,
        row_number() over (partition by mmsi order by ts_utc) as seq
    from events
    where event_type = 'exit'

),

paired as (

    select
        e.mmsi,
        e.port_id,
        e.arrival_ts,
        x.departure_ts,
        date_diff('second', e.arrival_ts, x.departure_ts) / 3600.0 as dwell_hours,
        false as is_anchorage
    from enters e
    inner join exits x
        on e.mmsi = x.mmsi and e.seq = x.seq

)

select p.*
from paired p
inner join {{ ref('dim_vessel') }} v
    on p.mmsi = v.mmsi
