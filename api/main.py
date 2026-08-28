"""Phase 3 FastAPI app (domain/08-phases.md): exposes the agent over HTTP and
simulates the enterprise integration the Maersk posting mentions with a mock
SAP OData endpoint.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

import duckdb
from dotenv import load_dotenv
from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from pydantic import BaseModel, Field
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

import agent.tracing  # noqa: F401  (import side effect: initializes the TracerProvider)

REPO_ROOT = Path(__file__).resolve().parent.parent
load_dotenv(REPO_ROOT / ".env")

import os  # noqa: E402  (deliberately after load_dotenv)

from agent.runner import ask  # noqa: E402
from agent.tools import WAREHOUSE_PATH, get_call_log, reset_call_log  # noqa: E402

API_KEY = os.environ.get("API_KEY")
if not API_KEY:
    raise RuntimeError(
        "Missing API_KEY in the environment (.env) -- see domain/06-security.md. "
        "Without this the API would run with no authentication, which isn't "
        "acceptable even for a PoC."
    )


def _rate_limit_key(request: Request) -> str:
    # Rate limit by API key, not by IP -- several clients can share a NAT egress.
    return request.headers.get("x-api-key") or get_remote_address(request)


limiter = Limiter(key_func=_rate_limit_key)

app = FastAPI(
    title="Port Intelligence Agent API",
    description=(
        "Backend for the Maersk R193814 PoC (domain/01-problem.md). "
        "POST /query talks to the agent; /sap/PortCallSet simulates a read-only "
        "SAP OData integration over the same data."
    ),
    version="0.1.0",
)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# Phase 4 (domain/08-phases.md): one span per HTTP request, parent of "agent.run"
# and of the "tool.*" spans emitted by agent/tools.py -- the context propagates
# on its own, even across the threadpool where the synchronous endpoints run
# (see domain/09-theoretical-foundations.md, contextvars section).
FastAPIInstrumentor.instrument_app(app)


def verify_api_key(x_api_key: str | None = Header(default=None, alias="X-API-Key")) -> None:
    if x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="invalid or missing API key")


class QueryRequest(BaseModel):
    question: str = Field(..., min_length=1, max_length=2000)


class ToolCallRecord(BaseModel):
    tool: str
    input: dict[str, Any]
    output: Any


class QueryResponse(BaseModel):
    answer: str
    tool_calls: list[ToolCallRecord]


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/query", response_model=QueryResponse, dependencies=[Depends(verify_api_key)])
@limiter.limit("10/minute")
def query(request: Request, body: QueryRequest) -> QueryResponse:
    """Natural-language question -> agent answer + invoked tools.

    The tool_calls field exists so whoever consumes the API can audit where
    each number came from -- consistent with domain/06-security.md: never
    "trust" the text answer without being able to trace its origin.
    """
    reset_call_log()
    try:
        answer, _messages = ask(body.question)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=502, detail=f"agent error: {exc}") from exc

    tool_calls = [ToolCallRecord(**c) for c in get_call_log()]
    return QueryResponse(answer=answer, tool_calls=tool_calls)


# --- Mock SAP OData (domain/02-architecture.md, "Simulated enterprise integration") ---
#
# Not a real SAP system or a generic OData connector -- it's a read-only
# endpoint shaped like an OData v4 entity set ("value": [...] envelope),
# enough to demonstrate the integration pattern the posting mentions without
# depending on a real SAP system. $top is supported; $filter/$orderby are not
# (out of scope for the minimal cut, domain/07-scope-cutlines.md).


class SapPortCall(BaseModel):
    MMSI: str
    VesselName: str | None
    PortId: str
    PortName: str
    ArrivalDateTime: str
    DepartureDateTime: str | None
    DwellHours: float | None


@app.get(
    "/sap/PortCallSet",
    dependencies=[Depends(verify_api_key)],
)
@limiter.limit("30/minute")
def sap_port_call_set(
    request: Request,
    top: int = Query(default=50, alias="$top", ge=1, le=500),
) -> dict[str, Any]:
    con = duckdb.connect(str(WAREHOUSE_PATH), read_only=True)
    try:
        rows = con.execute(
            """
            select p.mmsi, v.name, p.port_id, pt.name, p.arrival_ts, p.departure_ts, p.dwell_hours
            from fct_port_calls p
            join dim_vessel v on p.mmsi = v.mmsi
            join dim_port pt on p.port_id = pt.port_id
            order by p.arrival_ts desc
            limit ?
            """,
            [top],
        ).fetchall()
    finally:
        con.close()

    results = [
        SapPortCall(
            MMSI=str(r[0]),
            VesselName=r[1],
            PortId=r[2],
            PortName=r[3],
            ArrivalDateTime=str(r[4]),
            DepartureDateTime=str(r[5]) if r[5] is not None else None,
            DwellHours=r[6],
        ).model_dump()
        for r in rows
    ]
    return {"@odata.context": "$metadata#PortCallSet", "value": results}
