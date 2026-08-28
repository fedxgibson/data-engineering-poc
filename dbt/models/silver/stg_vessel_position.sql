{#
  Silver: position messages only (Class A), deduplicated by mmsi+ts_utc.
#}

with base as (

    select mmsi, ts_utc, lat, lon, sog, nav_status
    from {{ ref('stg_ais_raw') }}
    where type_of_mobile = 'Class A'

),

deduped as (

    select
        *,
        row_number() over (partition by mmsi, ts_utc order by ts_utc) as rn
    from base

)

select mmsi, ts_utc, lat, lon, sog, nav_status
from deduped
where rn = 1
