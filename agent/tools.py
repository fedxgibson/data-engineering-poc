"""Typed agent tools. Contracts documented in domain/05-agent-tools-eval.md.

Design principle (domain/06-security.md): the agent never generates SQL. Each tool
runs a fixed, parameterized query against the gold layer, validates its input before
touching the database, and returns a typed Pydantic model -- never a hand-built free
string. The LLM can't inject anything that doesn't pass the tool's input schema.
"""

from __future__ import annotations

import contextvars
import functools
import json
import os
import re
from pathlib import Path

import duckdb
from anthropic import beta_tool
from opentelemetry.trace import Status, StatusCode
from pydantic import BaseModel

from agent.tracing import get_tracer

REPO_ROOT = Path(__file__).resolve().parent.parent
_tracer = get_tracer(__name__)


def _traced(tool_name: str):
    """Wraps a tool's raw function in an OpenTelemetry span -- Phase 4
    (domain/08-phases.md). Applied BETWEEN @beta_tool and the def, so beta_tool
    still sees the original signature/docstring via __wrapped__ (functools.wraps).

    Duration comes automatically from the span (start/end); input/output content
    is covered by CALL_LOG (_log, below) for the eval harness -- two mechanisms
    with different purposes, not a duplication.
    """

    def decorator(func):
        @functools.wraps(func)
        def wrapper(**kwargs):
            with _tracer.start_as_current_span(f"tool.{tool_name}") as span:
                span.set_attribute("tool.name", tool_name)
                span.set_attribute("tool.input", json.dumps(kwargs, default=str))
                try:
                    result = func(**kwargs)
                except Exception as exc:  # noqa: BLE001
                    span.record_exception(exc)
                    span.set_status(Status(StatusCode.ERROR, str(exc)))
                    raise
                span.set_attribute("tool.output_bytes", len(result) if isinstance(result, str) else 0)
                return result

        return wrapper

    return decorator

# AGENT_WAREHOUSE_PATH lets the eval harness (eval/run_eval.py) point at a
# warehouse with synthetic fixtures without touching the real Phase 1 warehouse.
WAREHOUSE_PATH = Path(
    os.environ.get("AGENT_WAREHOUSE_PATH", REPO_ROOT / "data" / "warehouse.duckdb")
)

MMSI_RE = re.compile(r"^\d{9}$")

# Call log for the eval harness (domain/05-agent-tools-eval.md) and for the
# Phase 3 /query endpoint (domain/08-phases.md) -- reports which tools were
# called alongside the natural-language answer. In production that role is
# played by OpenTelemetry (domain/02-architecture.md); this is deliberately
# simpler because only the eval harness and the API read it.
#
# It's a ContextVar, not a global list: under FastAPI the same process serves
# concurrent requests (even with a single worker), and a global list would get
# corrupted across simultaneous requests. contextvars isolates the log per
# async task/thread, both in the eval's sequential loop and in parallel HTTP
# requests.
_call_log_var: contextvars.ContextVar[list[dict]] = contextvars.ContextVar("call_log")


def reset_call_log() -> list[dict]:
    log: list[dict] = []
    _call_log_var.set(log)
    return log


def get_call_log() -> list[dict]:
    try:
        return _call_log_var.get()
    except LookupError:
        return reset_call_log()


def _connect() -> duckdb.DuckDBPyConnection:
    return duckdb.connect(str(WAREHOUSE_PATH), read_only=True)


def _log(tool: str, input_: dict, output: object) -> None:
    get_call_log().append({"tool": tool, "input": input_, "output": output})


class Port(BaseModel):
    port_id: str
    name: str
    country: str


class CongestionMetrics(BaseModel):
    port_id: str
    date_from: str
    date_to: str
    avg_dwell_hours: float | None
    dwell_hours_p90: float | None
    avg_vessels_in_port: float | None
    trend_7d: float | None


class PortCall(BaseModel):
    port_id: str
    port_name: str
    arrival_ts: str
    departure_ts: str | None
    dwell_hours: float | None


@beta_tool
@_traced("port_lookup")
def port_lookup(query: str) -> str:
    """Look up a port by name (partial match, case-insensitive) and return its
    port_id -- use the result as input to port_congestion.

    Args:
        query: port name or part of it, e.g. "Aarhus" or "arhus".
    """
    con = _connect()
    try:
        rows = con.execute(
            "select port_id, name, country from dim_port where lower(name) like lower(?)",
            [f"%{query}%"],
        ).fetchall()
    finally:
        con.close()

    result = [Port(port_id=r[0], name=r[1], country=r[2]).model_dump() for r in rows]
    _log("port_lookup", {"query": query}, result)
    # @beta_tool requires returning str or a list of content blocks -- never a
    # raw Python dict/list (see eval/run_eval.py, Phase 2 finding).
    return json.dumps(result)


@beta_tool
@_traced("port_congestion")
def port_congestion(port_id: str, date_from: str, date_to: str) -> str:
    """Congestion at a port over a date range: average and p90 dwell time,
    average vessels in port, and trend vs. the 7 days prior to the range's last
    day. Use port_lookup first to get the port_id.

    Args:
        port_id: port identifier (e.g. "DKAAR"), obtained via port_lookup.
        date_from: range start date, format YYYY-MM-DD.
        date_to: range end date, format YYYY-MM-DD.
    """
    input_ = {"port_id": port_id, "date_from": date_from, "date_to": date_to}
    con = _connect()
    try:
        exists = con.execute(
            "select 1 from dim_port where port_id = ?", [port_id]
        ).fetchone()
        if not exists:
            result = {"error": f"unknown port_id: {port_id!r}. Use port_lookup first."}
            _log("port_congestion", input_, result)
            return json.dumps(result)

        row = con.execute(
            """
            select
                avg(avg_dwell_hours)    as avg_dwell_hours,
                avg(dwell_hours_p90)    as dwell_hours_p90,
                avg(vessels_in_port)    as avg_vessels_in_port,
                arg_max(trend_7d, date) as trend_7d
            from fct_port_congestion_daily
            where port_id = ? and date between ?::date and ?::date
            """,
            [port_id, date_from, date_to],
        ).fetchone()
    finally:
        con.close()

    result = CongestionMetrics(
        port_id=port_id,
        date_from=date_from,
        date_to=date_to,
        avg_dwell_hours=row[0],
        dwell_hours_p90=row[1],
        avg_vessels_in_port=row[2],
        trend_7d=row[3],
    ).model_dump()
    _log("port_congestion", input_, result)
    return json.dumps(result)


@beta_tool
@_traced("vessel_history")
def vessel_history(mmsi: str, lookback_days: int = 30) -> str:
    """Call history of a commercial vessel over the last N days of available
    data (the window is counted from the dataset's most recent date, not from
    today -- this PoC operates on a fixed historical dataset).

    Args:
        mmsi: 9-digit vessel identifier (MMSI).
        lookback_days: how many days back to consider, default 30.
    """
    input_ = {"mmsi": mmsi, "lookback_days": lookback_days}

    if not MMSI_RE.fullmatch(mmsi):
        result = {"error": f"invalid mmsi, expected 9 numeric digits: {mmsi!r}"}
        _log("vessel_history", input_, result)
        return json.dumps(result)

    con = _connect()
    try:
        reference_date = con.execute(
            "select max(departure_ts) from fct_port_calls"
        ).fetchone()[0]

        vessel_row = con.execute(
            "select name from dim_vessel where mmsi = ?", [mmsi]
        ).fetchone()

        rows = con.execute(
            """
            select v.port_id, p.name as port_name, v.arrival_ts, v.departure_ts,
                   date_diff('second', v.arrival_ts, v.departure_ts) / 3600.0 as dwell_hours
            from fct_vessel_voyage_history v
            join dim_port p on v.port_id = p.port_id
            where v.mmsi = ?
              and v.arrival_ts >= ?::timestamp - (? || ' days')::interval
            order by v.arrival_ts
            """,
            [mmsi, reference_date, lookback_days],
        ).fetchall()
    finally:
        con.close()

    if vessel_row is None and not rows:
        result = {"error": f"mmsi not found among commercial vessels: {mmsi!r}"}
        _log("vessel_history", input_, result)
        return json.dumps(result)

    # vessel_name travels as the VALUE of a data field -- domain/06-security.md.
    # The agent's system prompt (agent/runner.py) instructs treating it as
    # literal text to cite, never as an instruction, regardless of its content.
    calls = [
        PortCall(
            port_id=r[0],
            port_name=r[1],
            arrival_ts=str(r[2]),
            departure_ts=str(r[3]) if r[3] is not None else None,
            dwell_hours=r[4],
        ).model_dump()
        for r in rows
    ]
    result = {
        "mmsi": mmsi,
        "vessel_name": vessel_row[0] if vessel_row else None,
        "calls": calls,
    }
    _log("vessel_history", input_, result)
    return json.dumps(result)


ALL_TOOLS = [port_lookup, port_congestion, vessel_history]
