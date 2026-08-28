{#
  Gold: daily aggregation over fct_port_calls. vessels_waiting stays at 0 for
  the same single-geofence limitation as is_anchorage in fct_port_calls.
#}

with calls as (

    select * from {{ ref('fct_port_calls') }}

),

date_spine as (

    select unnest(generate_series(
        (select min(arrival_ts)::date from calls),
        (select max(departure_ts)::date from calls),
        interval 1 day
    )) as date

),

daily as (

    select
        d.date,
        count(distinct c.mmsi) filter (
            where c.arrival_ts::date <= d.date and c.departure_ts::date >= d.date
        ) as vessels_in_port,
        avg(c.dwell_hours) filter (where c.arrival_ts::date = d.date) as avg_dwell_hours,
        quantile_cont(c.dwell_hours, 0.9) filter (where c.arrival_ts::date = d.date) as dwell_hours_p90
    from date_spine d
    left join calls c on true
    group by d.date

),

with_trend as (

    select
        date,
        vessels_in_port,
        avg_dwell_hours,
        dwell_hours_p90,
        avg(vessels_in_port) over (
            order by date rows between 7 preceding and 1 preceding
        ) as avg_vessels_prev_7d
    from daily

)

select
    'DKAAR' as port_id,
    date,
    vessels_in_port,
    0 as vessels_waiting,
    avg_dwell_hours,
    dwell_hours_p90,
    case
        when avg_vessels_prev_7d is null or avg_vessels_prev_7d = 0 then null
        else round((vessels_in_port - avg_vessels_prev_7d) / avg_vessels_prev_7d, 4)
    end as trend_7d
from with_trend
order by date
