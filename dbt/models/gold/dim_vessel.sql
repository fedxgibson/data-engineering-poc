{#
  Gold: commercial vessels only (domain/04-data-model.md, "Commercial traffic
  filter" section) -- excludes tugs, pilotage, ferries, and other local
  service fleet found in Phase 0.
#}

select
    s.mmsi,
    s.imo,
    s.name,
    s.ship_type,
    s.callsign
from {{ ref('stg_vessel_static') }} s
inner join {{ ref('ship_type_classification') }} c
    on s.ship_type = c.ship_type
where c.is_commercial
