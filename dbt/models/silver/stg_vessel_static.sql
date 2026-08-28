{#
  Silver: one static record per mmsi. AIS type 5 (static) is transmitted far
  less often than position (domain/04-data-model.md), so the same mmsi can
  carry null values in some messages and populated ones in others -- we keep
  the most frequent non-null value per field (mode() in DuckDB ignores NULL).
#}

with base as (

    select mmsi, imo, callsign, name, ship_type, length_m, width_m
    from {{ ref('stg_ais_raw') }}
    where type_of_mobile = 'Class A'

)

select
    mmsi,
    mode(imo)        as imo,
    mode(callsign)   as callsign,
    mode(name)       as name,
    mode(ship_type)  as ship_type,
    mode(length_m)   as length_m,
    mode(width_m)    as width_m
from base
group by mmsi
