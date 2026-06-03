from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd

from path_utils import ensure_project_dirs, find_project_root, load_project_configs, setup_logging


def read_xpt(path: Path) -> pd.DataFrame:
    return pd.read_sas(path, format="xport", encoding="utf-8")


def load_cycle(root: Path, cycle: dict, components: list[str], id_col: str) -> pd.DataFrame | None:
    suffix = cycle["suffix"]
    cycle_dir = root / "data" / "raw" / "discovery" / cycle["cycle"]
    merged: pd.DataFrame | None = None

    for component in components:
        path = cycle_dir / f"{component}_{suffix}.xpt"
        if not path.exists():
            continue
        frame = read_xpt(path)
        frame["NHANES_CYCLE"] = cycle["cycle"]
        if merged is None:
            merged = frame
        else:
            frame = frame.drop(columns=[column for column in ["NHANES_CYCLE"] if column in frame.columns])
            merged = merged.merge(frame, on=id_col, how="left")

    return merged


def derive_uacr(frame: pd.DataFrame, config: dict) -> pd.DataFrame:
    exposure = config["exposure"]
    albumin_mg_l = exposure["albumin_mg_l"]
    albumin_ug_ml = exposure["albumin_ug_ml"]
    creatinine = exposure["creatinine_mg_dl"]
    uacr = exposure["derived_uacr_mg_g"]
    log_uacr = exposure["derived_log_uacr"]

    frame = frame.copy()
    if albumin_mg_l in frame.columns:
        albumin = frame[albumin_mg_l]
    elif albumin_ug_ml in frame.columns:
        albumin = frame[albumin_ug_ml]
    else:
        frame[uacr] = np.nan
        frame[log_uacr] = np.nan
        return frame

    valid = frame[creatinine].notna() & (frame[creatinine] > 0)
    frame[uacr] = np.nan
    frame.loc[valid, uacr] = 100 * albumin.loc[valid] / frame.loc[valid, creatinine]
    frame[log_uacr] = np.log(frame[uacr])
    return frame


def add_combined_weight(frame: pd.DataFrame, config: dict) -> pd.DataFrame:
    survey = config["survey_design"]
    two_year = survey["two_year_weight"]
    combined = survey["combined_weight"]
    frame = frame.copy()
    if two_year in frame.columns:
        frame[combined] = frame[two_year] / len(config["source"]["cycles"])
    return frame


def main() -> None:
    root = find_project_root(Path(__file__))
    configs = load_project_configs(root)
    ensure_project_dirs(root, configs["analysis"])
    logger = setup_logging(root, "02_build_discovery_dataset")

    discovery = configs["discovery"]
    id_col = discovery["ids"]["participant_id"]
    components = list(discovery["source"]["components"].keys())
    frames = []

    for cycle in discovery["source"]["cycles"]:
        merged = load_cycle(root, cycle, components, id_col)
        if merged is None:
            logger.warning("No source XPT files found for %s", cycle["cycle"])
            continue
        logger.info("%s merged shape: %s rows x %s columns", cycle["cycle"], merged.shape[0], merged.shape[1])
        frames.append(merged)

    report_path = root / "outputs" / "reports" / "02_build_discovery_dataset_report.md"
    if not frames:
        report_path.write_text(
            "# Discovery Dataset Build\n\n"
            "Status: waiting for raw NHANES 2007-2012 XPT files.\n\n"
            "Run `python scripts/01_download_source_files.py` first.\n",
            encoding="utf-8",
        )
        logger.warning("No discovery files found. Wrote %s", report_path)
        return

    data = pd.concat(frames, ignore_index=True, sort=False)
    data = derive_uacr(data, discovery)
    data = add_combined_weight(data, discovery)

    age_col = discovery["covariates_core"]["age_years"]
    min_age = discovery["cohort"]["age_filter_years"]
    if age_col in data.columns:
        before = len(data)
        data = data.loc[data[age_col] >= min_age].copy()
        logger.info("Applied age >= %s years: %s -> %s rows", min_age, before, len(data))

    output_path = root / configs["analysis"]["outputs"]["discovery_dataset"]
    output_path.parent.mkdir(parents=True, exist_ok=True)
    data.to_csv(output_path, index=False)

    report_path.write_text(
        "# Discovery Dataset Build\n\n"
        "Status: completed skeleton data assembly.\n\n"
        f"Rows: {data.shape[0]}\n\n"
        f"Columns: {data.shape[1]}\n\n"
        f"Output: `{output_path}`\n",
        encoding="utf-8",
    )
    logger.info("Wrote dataset to %s", output_path)
    logger.info("Wrote report to %s", report_path)


if __name__ == "__main__":
    main()
