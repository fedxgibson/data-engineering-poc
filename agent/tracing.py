"""OpenTelemetry setup -- Phase 4 (domain/08-phases.md).

Two exporters in parallel, not one or the other:

1. `ConsoleSpanExporter` to a file (`logs/traces.jsonl`) -- domain/07-scope-cutlines.md
   explicitly accepts "structured console" as a valid scope cut, and it serves
   as reproducible evidence without depending on Jaeger running (e.g. in CI).
2. `OTLPSpanExporter` to a local Jaeger (`docker run jaegertracing/all-in-one`,
   port 4318 OTLP/HTTP, UI at :16686) -- the optional upgrade
   domain/07-scope-cutlines.md had left noted ("local Jaeger if time allows").
   Runs on a `BatchSpanProcessor` so it doesn't block each tool call if Jaeger
   isn't running -- retries/drops in the background, never fails the request.
"""

from __future__ import annotations

from pathlib import Path

from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import SERVICE_NAME, Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import (
    BatchSpanProcessor,
    ConsoleSpanExporter,
    SimpleSpanProcessor,
)

REPO_ROOT = Path(__file__).resolve().parent.parent
LOG_DIR = REPO_ROOT / "logs"
LOG_DIR.mkdir(exist_ok=True)
TRACES_PATH = LOG_DIR / "traces.jsonl"

_initialized = False


def _setup() -> None:
    global _initialized
    if _initialized:
        return
    resource = Resource.create({SERVICE_NAME: "port-intelligence-agent"})
    provider = TracerProvider(resource=resource)

    file_exporter = ConsoleSpanExporter(out=open(TRACES_PATH, "a", encoding="utf-8"))
    provider.add_span_processor(SimpleSpanProcessor(file_exporter))

    # OTLPSpanExporter() default with no args: http://localhost:4318/v1/traces
    # (the standard OTLP/HTTP endpoint exposed by Jaeger all-in-one).
    provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))

    trace.set_tracer_provider(provider)
    _initialized = True


_setup()


def get_tracer(name: str) -> trace.Tracer:
    return trace.get_tracer(name)
