select
    port_id,
    port_name                    as name,
    country,
    (lat_min + lat_max) / 2      as lat,
    (lon_min + lon_max) / 2      as lon,
    timezone
from {{ ref('port_geofences') }}
