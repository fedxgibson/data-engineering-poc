{#
  Bronze: near-raw AIS message log (just rename + cast + dedup of literally
  repeated rows). Source: the 14 days of Aarhus data already filtered by
  scripts/fetch_ais.py during Phase 0 (see domain/08-phases.md).

  The "single port, batch" scope cut (domain/07-scope-cutlines.md) means this
  replaces the full national ais_raw from domain/04-data-model.md -- it's
  already geographically bounded to Aarhus at the source file level, not by
  this model.
#}

with source as (

    select * from read_parquet('{{ var("raw_ais_glob") }}')

),

renamed as (

    select
        strptime("Timestamp", '%d/%m/%Y %H:%M:%S') as ts_utc,
        "Type of mobile"                            as type_of_mobile,
        MMSI                                        as mmsi,
        Latitude                                     as lat,
        Longitude                                    as lon,
        "Navigational status"                       as nav_status,
        ROT                                          as rot,
        SOG                                          as sog,
        COG                                          as cog,
        Heading                                      as heading,
        nullif(IMO, 'Unknown')                       as imo,
        nullif(Callsign, 'Unknown')                  as callsign,
        nullif(nullif(Name, 'Unknown'), '')          as name,
        nullif("Ship type", 'Undefined')             as ship_type,
        Length                                        as length_m,
        Width                                         as width_m,
        nullif(Destination, 'Unknown')               as destination

    from source

)

-- dedup: Phase 0 found ~2s gaps between consecutive messages from the same
-- mmsi, consistent with the same message being received by several shore
-- base stations.
select distinct * from renamed
