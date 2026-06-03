from __future__ import annotations

import logging
import sys
from pathlib import Path

import pandas as pd
import requests


CDC_BASE = "https://ftp.cdc.gov/pub/health_statistics/nchs/datalinkage/linked_mortality"
CYCLES = {
    "2007-2008": "NHANES_2007_2008_MORT_2019_PUBLIC.dat",
    "2009-2010": "NHANES_2009_2010_MORT_2019_PUBLIC.dat",
    "2011-2012": "NHANES_2011_2012_MORT_2019_PUBLIC.dat",
}
LMF_COLUMNS = {
    "SEQN": (0, 6),
    "ELIGSTAT": (14, 15),
    "MORTSTAT": (15, 16),
    "UCOD_LEADING": (16, 19),
    "DIABETES_MCOD": (19, 20),
    "HYPERTEN_MCOD": (20, 21),
    "PERMTH_INT": (42, 45),
    "PERMTH_EXM": (45, 48),
}


def find_project_root(start: Path | None = None) -> Path:
    current = (start or Path(__file__)).resolve()
    if current.is_file():
        current = current.parent
    for candidate in (current, *current.parents):
        if (candidate / "config" / "analysis_plan.yaml").exists():
            return candidate
    raise FileNotFoundError("Could not find project root containing config/analysis_plan.yaml.")


def setup_logger(root: Path) -> logging.Logger:
    log_dir = root / "outputs" / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / "07_build_mortality_linkage.log"

    logger = logging.getLogger("07_build_mortality_linkage")
    logger.setLevel(logging.INFO)
    logger.handlers.clear()
    logger.propagate = False
    formatter = logging.Formatter("%(asctime)s | %(levelname)s | %(message)s")
    for handler in (logging.FileHandler(log_path, mode="w", encoding="utf-8"), logging.StreamHandler(sys.stdout)):
        handler.setFormatter(formatter)
        logger.addHandler(handler)
    logger.info("Logging to %s", log_path)
    return logger


def download_file(url: str, path: Path, logger: logging.Logger) -> None:
    if path.exists() and path.stat().st_size > 0:
        logger.info("Using existing mortality file: %s", path)
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    logger.info("Downloading %s", url)
    with requests.get(url, timeout=120, stream=True) as response:
        response.raise_for_status()
        with path.open("wb") as handle:
            for chunk in response.iter_content(chunk_size=1024 * 1024):
                if chunk:
                    handle.write(chunk)
    logger.info("Downloaded %s (%s bytes)", path, path.stat().st_size)


def read_lmf(path: Path, cycle: str, logger: logging.Logger) -> pd.DataFrame:
    colspecs = list(LMF_COLUMNS.values())
    names = list(LMF_COLUMNS)
    frame = pd.read_fwf(path, colspecs=colspecs, names=names, dtype=str, header=None)
    for column in names:
        frame[column] = pd.to_numeric(frame[column].astype(str).str.strip(), errors="coerce")
    frame["CYCLE"] = cycle
    logger.info("Read %s mortality rows for %s", len(frame), cycle)
    return frame


def main() -> None:
    root = find_project_root()
    logger = setup_logger(root)
    raw_dir = root / "data" / "raw" / "linked_mortality_2019"
    processed_path = root / "data" / "processed" / "discovery_nhanes_2007_2012_mortality.csv"
    flow_path = root / "outputs" / "tables" / "mortality_linkage_flow.csv"
    discovery_path = root / "data" / "processed" / "discovery_nhanes_2007_2012.csv"

    if not discovery_path.exists():
        raise FileNotFoundError(f"Discovery cohort not found: {discovery_path}")
    raw_dir.mkdir(parents=True, exist_ok=True)
    processed_path.parent.mkdir(parents=True, exist_ok=True)
    flow_path.parent.mkdir(parents=True, exist_ok=True)

    mortality_parts: list[pd.DataFrame] = []
    for cycle, filename in CYCLES.items():
        path = raw_dir / filename
        download_file(f"{CDC_BASE}/{filename}", path, logger)
        mortality_parts.append(read_lmf(path, cycle, logger))
    mortality = pd.concat(mortality_parts, ignore_index=True)

    discovery = pd.read_csv(discovery_path, low_memory=False)
    discovery["SEQN"] = pd.to_numeric(discovery["SEQN"], errors="coerce")
    mortality["SEQN"] = pd.to_numeric(mortality["SEQN"], errors="coerce")
    merged = discovery.merge(mortality, on="SEQN", how="left", suffixes=("", "_LMF"), validate="one_to_one")

    merged["MORTALITY_ELIGIBLE"] = merged["ELIGSTAT"].eq(1)
    merged["ALL_CAUSE_DEATH"] = merged["MORTSTAT"].eq(1).astype("Int64")
    merged["CVD_DEATH"] = (merged["MORTSTAT"].eq(1) & merged["UCOD_LEADING"].isin([1, 5])).astype("Int64")
    merged.loc[~merged["MORTALITY_ELIGIBLE"], ["ALL_CAUSE_DEATH", "CVD_DEATH"]] = pd.NA

    flow = pd.DataFrame(
        [
            {"step": "Discovery analytic cohort", "n": len(discovery), "note": ""},
            {"step": "Matched to public-use LMF", "n": int(merged["ELIGSTAT"].notna().sum()), "note": "SEQN linkage"},
            {"step": "Eligible for mortality follow-up", "n": int(merged["MORTALITY_ELIGIBLE"].sum()), "note": "ELIGSTAT == 1"},
            {
                "step": "Eligible with follow-up months from MEC examination",
                "n": int((merged["MORTALITY_ELIGIBLE"] & merged["PERMTH_EXM"].notna()).sum()),
                "note": "PERMTH_EXM nonmissing",
            },
            {
                "step": "All-cause deaths",
                "n": int((merged["ALL_CAUSE_DEATH"] == 1).sum()),
                "note": "MORTSTAT == 1",
            },
            {
                "step": "Cardiovascular deaths",
                "n": int((merged["CVD_DEATH"] == 1).sum()),
                "note": "UCOD_LEADING in {1 heart disease, 5 cerebrovascular disease}",
            },
        ]
    )

    merged.to_csv(processed_path, index=False)
    flow.to_csv(flow_path, index=False)
    logger.info("Wrote linked mortality cohort to %s", processed_path)
    logger.info("Wrote mortality linkage flow to %s", flow_path)
    for row in flow.itertuples(index=False):
        logger.info("%s: n=%s", row.step, row.n)


if __name__ == "__main__":
    main()
