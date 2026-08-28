"""Downloads and filters days of AIS data from the Danish Maritime Authority to
a bounding box.

Reused by notebooks/00 and notebooks/01 during Phase 0, and by the Phase 1
batch ingestion (see domain/08-phases.md). Each day is cached in data/raw/
(raw zip) and data/interim/ (already-filtered parquet) to avoid
re-downloading/re-scanning.
"""

from __future__ import annotations

import sys
import urllib.request
import zipfile
from dataclasses import dataclass
from datetime import date, timedelta
from pathlib import Path

import pandas as pd

REPO_ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = REPO_ROOT / "data" / "raw"
INTERIM_DIR = REPO_ROOT / "data" / "interim"


@dataclass(frozen=True)
class BoundingBox:
    lat_min: float
    lat_max: float
    lon_min: float
    lon_max: float


AARHUS_BBOX = BoundingBox(lat_min=56.05, lat_max=56.25, lon_min=10.05, lon_max=10.40)


def date_range(start: str, end: str) -> list[str]:
    d0, d1 = date.fromisoformat(start), date.fromisoformat(end)
    days = (d1 - d0).days
    return [(d0 + timedelta(days=i)).isoformat() for i in range(days + 1)]


def _source_url(day: str) -> str:
    year = day[:4]
    return f"http://aisdata.ais.dk.s3.eu-central-1.amazonaws.com/{year}/aisdk-{day}.zip"


def download_day(day: str, raw_dir: Path = RAW_DIR) -> Path | None:
    raw_dir.mkdir(parents=True, exist_ok=True)
    zip_path = raw_dir / f"aisdk-{day}.zip"
    if zip_path.exists():
        return zip_path
    url = _source_url(day)
    try:
        print(f"[{day}] downloading {url}", flush=True)
        urllib.request.urlretrieve(url, zip_path)
        return zip_path
    except Exception as exc:  # noqa: BLE001 - report and keep going with the rest of the range
        print(f"[{day}] not available ({exc}) — skipping", flush=True)
        return None


def filter_day_to_bbox(
    day: str,
    bbox: BoundingBox = AARHUS_BBOX,
    raw_dir: Path = RAW_DIR,
    interim_dir: Path = INTERIM_DIR,
    chunksize: int = 500_000,
) -> Path | None:
    interim_dir.mkdir(parents=True, exist_ok=True)
    out_path = interim_dir / f"aarhus-{day}.parquet"
    if out_path.exists():
        return out_path

    zip_path = download_day(day, raw_dir=raw_dir)
    if zip_path is None:
        return None

    csv_name = f"aisdk-{day}.csv"
    matched = []
    with zipfile.ZipFile(zip_path) as zf, zf.open(csv_name) as f:
        for chunk in pd.read_csv(f, chunksize=chunksize, low_memory=False):
            chunk = chunk.rename(columns={"# Timestamp": "Timestamp"})
            mask = chunk["Latitude"].between(bbox.lat_min, bbox.lat_max) & chunk[
                "Longitude"
            ].between(bbox.lon_min, bbox.lon_max)
            hit = chunk[mask]
            if len(hit):
                matched.append(hit)

    if not matched:
        print(f"[{day}] 0 rows in the bounding box", flush=True)
        day_df = pd.DataFrame()
    else:
        day_df = pd.concat(matched, ignore_index=True)

    day_df.to_parquet(out_path, index=False)
    print(f"[{day}] {len(day_df):,} rows -> {out_path.name}", flush=True)
    return out_path


def fetch_range(start: str, end: str, bbox: BoundingBox = AARHUS_BBOX) -> list[Path]:
    paths = []
    for day in date_range(start, end):
        path = filter_day_to_bbox(day, bbox=bbox)
        if path is not None:
            paths.append(path)
    return paths


if __name__ == "__main__":
    start_arg = sys.argv[1] if len(sys.argv) > 1 else "2025-02-13"
    end_arg = sys.argv[2] if len(sys.argv) > 2 else "2025-02-26"
    fetch_range(start_arg, end_arg)
