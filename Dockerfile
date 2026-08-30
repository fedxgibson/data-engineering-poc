# Runtime image for the Phase 3 API (api/main.py), deployed via the Phase 5
# Terraform/Terragrunt setup in infra/ (see infra/live/dev/container-app).
#
# The DuckDB warehouse is baked in at build time rather than mounted or
# fetched at startup -- consistent with the "batch, already-processed data"
# minimal cut (domain/07-scope-cutlines.md): this PoC serves a fixed
# historical dataset, not a live feed, so there's no runtime dependency on
# Blob Storage or a database server.
FROM python:3.11-slim

RUN useradd --create-home --uid 1000 appuser
WORKDIR /app

COPY requirements-api.txt .
RUN pip install --no-cache-dir -r requirements-api.txt

COPY agent/ agent/
COPY api/ api/
COPY data/warehouse.duckdb data/warehouse.duckdb

RUN mkdir -p /app/logs && chown -R appuser:appuser /app
USER appuser

ENV AGENT_WAREHOUSE_PATH=/app/data/warehouse.duckdb

EXPOSE 8000

CMD ["uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8000"]
