select
    mmsi,
    row_number() over (partition by mmsi order by arrival_ts) as seq_num,
    port_id,
    arrival_ts,
    departure_ts
from {{ ref('fct_port_calls') }}
