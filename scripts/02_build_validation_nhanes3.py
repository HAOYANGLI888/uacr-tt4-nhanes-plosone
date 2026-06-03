from __future__ import annotations

import logging
import math
import re
import sys
from pathlib import Path
from typing import Iterable

import numpy as np
import pandas as pd
import requests


NHANES3_SAS_URLS = {
    "adult": "https://wwwn.cdc.gov/nchs/data/nhanes3/1a/adult.sas",
    "exam": "https://wwwn.cdc.gov/nchs/data/nhanes3/1a/exam.sas",
    "lab": "https://wwwn.cdc.gov/nchs/data/nhanes3/1a/lab.sas",
    "lab2": "https://wwwn.cdc.gov/nchs/data/nhanes3/2a/lab2.sas",
}

NHANES3_DATA_URLS = {
    "adult": "https://wwwn.cdc.gov/nchs/data/nhanes3/1a/adult.dat",
    "exam": "https://wwwn.cdc.gov/nchs/data/nhanes3/1a/exam.dat",
    "lab": "https://wwwn.cdc.gov/nchs/data/nhanes3/1a/lab.dat",
    "lab2": "https://wwwn.cdc.gov/nchs/data/nhanes3/2a/lab2.dat",
}

TABLE_SPECS = {
    "adult": {
        "stems": ["adult"],
        "needed": [
            "SEQN",
            "HSAGEIR",
            "HSSEX",
            "DMARETHN",
            "DMARACER",
            "HFA8R",
            "DMPPIR",
            "HAR1",
            "HAR3",
            "HAN6HS",
            "HAN6IS",
            "HAN6JS",
            "HAD1",
            "HAD3",
            "HAD4",
            "HAE2",
            "HAE5A",
            "HAC1J",
            "HAC1K",
            "HAC2J",
            "HAC2K",
        ],
    },
    "exam": {
        "stems": ["exam"],
        "needed": [
            "SEQN",
            "SDPPSU6",
            "SDPSTRA6",
            "WTPFEX6",
            "BMPBMI",
            "PEPMNK1R",
            "PEPMNK5R",
            "PEP6G1",
            "PEP6H1",
            "PEP6I1",
            "PEP6G3",
            "PEP6H3",
            "PEP6I3",
            "PEPPREG",
            "MYPC17",
            "MAPF12",
            "MAPF12R",
        ],
    },
    "lab": {
        "stems": ["lab"],
        "needed": ["SEQN", "SDPPSU6", "SDPSTRA6", "WTPFEX6", "UBP", "URP", "CEP"],
    },
    "lab2": {
        "stems": ["lab2"],
        "needed": ["SEQN", "SDPPSU6", "SDPSTRA6", "WTPFEX6", "THP", "T4P", "TMP", "TAP"],
    },
}

COMMON_THYROID_MAP = {
    "TSH": {"validation_source": "THP", "discovery_source": "LBXTSH1"},
    "TT4": {"validation_source": "T4P", "discovery_source": "LBXTT4"},
    "TGAB": {"validation_source": "TAP", "discovery_source": "LBXATG"},
    "TPOAB": {"validation_source": "TMP", "discovery_source": "LBXTPO"},
}

THYROID_MEDICATION_KEYWORDS = [
    "LEVOTHYROXINE",
    "SYNTHROID",
    "LEVOXYL",
    "UNITHROID",
    "LEVOTHROID",
    "LIOTHYRONINE",
    "CYTOMEL",
    "THYROID",
    "ARMOUR",
    "METHIMAZOLE",
    "TAPAZOLE",
    "PROPYLTHIOURACIL",
    "PTU",
]

OUTPUT_COLUMNS = [
    "SEQN",
    "AGE",
    "AGE_YEARS",
    "AGE_GROUP",
    "SEX",
    "RACE",
    "RACE_ETHNICITY",
    "EDUCATION",
    "PIR",
    "BMI",
    "SMOKE",
    "SMOKING_STATUS",
    "DRINK",
    "ALCOHOL_STATUS",
    "DIABETES",
    "DIABETES_STATUS",
    "HYPERTENSION",
    "HYPERTENSION_STATUS",
    "MEAN_SBP",
    "MEAN_DBP",
    "URINE_ALBUMIN_UG_ML",
    "URINE_CREATININE_MG_DL",
    "SERUM_CREATININE_MG_DL",
    "EGFR",
    "EGFR_CKD_EPI_2021",
    "UACR",
    "UACR_MG_G",
    "LOG_UACR",
    "UACR_QUARTILE",
    "UACR_CLINICAL_CATEGORY",
    "TSH",
    "TT4",
    "TGAB",
    "TPOAB",
    "WTPFEX6",
    "SDPPSU6",
    "SDPSTRA6",
    "PREGNANT_FLAG",
    "THYROID_DISEASE_FLAG",
    "THYROID_MED_USE",
    "THYROID_EXCLUSION_FLAG",
]

KEY_COVARIATES = [
    "AGE_YEARS",
    "SEX",
    "RACE_ETHNICITY",
    "EDUCATION",
    "PIR",
    "BMI",
    "SMOKING_STATUS",
    "ALCOHOL_STATUS",
    "DIABETES_STATUS",
    "HYPERTENSION_STATUS",
    "WTPFEX6",
    "SDPPSU6",
    "SDPSTRA6",
]


def find_project_root(start: Path | None = None) -> Path:
    if start is None:
        start = Path(__file__).resolve()
    start = start.resolve()
    if start.is_file():
        start = start.parent

    for candidate in (start, *start.parents):
        if (candidate / "config" / "analysis_plan.yaml").exists():
            return candidate

    raise FileNotFoundError("Could not find project root containing config/analysis_plan.yaml.")


def setup_logger(root: Path) -> logging.Logger:
    log_dir = root / "outputs" / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / "02_build_validation_nhanes3.log"

    logger = logging.getLogger("02_build_validation_nhanes3")
    logger.setLevel(logging.INFO)
    logger.handlers.clear()
    logger.propagate = False

    formatter = logging.Formatter("%(asctime)s | %(levelname)s | %(message)s")
    file_handler = logging.FileHandler(log_path, mode="w", encoding="utf-8")
    file_handler.setFormatter(formatter)
    stream_handler = logging.StreamHandler(sys.stdout)
    stream_handler.setFormatter(formatter)

    logger.addHandler(file_handler)
    logger.addHandler(stream_handler)
    logger.info("Logging to %s", log_path)
    return logger


def ensure_output_dirs(root: Path) -> None:
    for relative in [
        "data/raw/nhanes3",
        "data/processed",
        "outputs/tables",
        "outputs/logs",
        "outputs/reports",
    ]:
        (root / relative).mkdir(parents=True, exist_ok=True)


def choose_raw_dir(root: Path, logger: logging.Logger) -> Path:
    primary = root / "data" / "raw" / "nhanes3"
    fallback = root / "data" / "raw" / "validation_nhanes3"
    primary.mkdir(parents=True, exist_ok=True)

    if list_data_files(primary):
        return primary
    if list_data_files(fallback):
        logger.warning("No files found in %s; using fallback raw directory %s", primary, fallback)
        return fallback
    return primary


def list_data_files(raw_dir: Path) -> list[Path]:
    if not raw_dir.exists():
        return []
    allowed = {".dat", ".txt", ".csv", ".xpt", ".sas7bdat", ".sas7bdat7"}
    return sorted(path for path in raw_dir.rglob("*") if path.is_file() and path.suffix.lower() in allowed)


def download_file(url: str, path: Path, logger: logging.Logger) -> bool:
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        logger.info("Downloading %s to %s", url, path)
        with requests.get(url, timeout=120, stream=True) as response:
            response.raise_for_status()
            with path.open("wb") as handle:
                for chunk in response.iter_content(chunk_size=1024 * 1024):
                    if chunk:
                        handle.write(chunk)
        logger.info("Downloaded %s (%s bytes)", path, path.stat().st_size)
        return True
    except Exception as exc:
        logger.warning("Could not download %s: %s", url, exc)
        if path.exists() and path.stat().st_size == 0:
            path.unlink()
        return False


def ensure_nhanes3_sources(raw_dir: Path, logger: logging.Logger) -> None:
    for table_name in ["adult", "exam", "lab", "lab2"]:
        spec = TABLE_SPECS[table_name]
        data_exists = find_file_by_stem(
            raw_dir,
            spec["stems"],
            [".csv", ".xpt", ".sas7bdat", ".sas7bdat7", ".dat", ".txt"],
        )
        if data_exists is None:
            url = NHANES3_DATA_URLS[table_name]
            download_file(url, raw_dir / f"{table_name}.dat", logger)
        else:
            logger.info("Using existing NHANES III %s data file: %s", table_name, data_exists)

        sas_exists = find_file_by_stem(raw_dir, spec["stems"], [".sas"])
        if sas_exists is None:
            download_file(NHANES3_SAS_URLS[table_name], raw_dir / f"{table_name}.sas", logger)
        else:
            logger.info("Using existing NHANES III %s SAS layout: %s", table_name, sas_exists)


def normalize_columns(frame: pd.DataFrame) -> pd.DataFrame:
    out = frame.copy()
    out.columns = [str(column).strip().upper() for column in out.columns]
    return out


def find_file_by_stem(raw_dir: Path, stems: Iterable[str], exts: Iterable[str]) -> Path | None:
    stems_upper = {stem.upper() for stem in stems}
    exts_lower = {ext.lower() for ext in exts}
    matches = [
        path
        for path in raw_dir.rglob("*")
        if path.is_file() and path.stem.upper() in stems_upper and path.suffix.lower() in exts_lower
    ]
    return sorted(matches)[0] if matches else None


def read_text(path: Path) -> str:
    return path.read_text(encoding="latin1", errors="ignore")


def sas_content_for_table(raw_dir: Path, table_name: str, logger: logging.Logger) -> str | None:
    local_sas = find_file_by_stem(raw_dir, TABLE_SPECS[table_name]["stems"], [".sas"])
    if local_sas is not None:
        logger.info("Using local SAS layout for %s: %s", table_name, local_sas)
        return read_text(local_sas)

    url = NHANES3_SAS_URLS.get(table_name)
    if not url:
        return None
    try:
        response = requests.get(url, timeout=45)
        response.raise_for_status()
        logger.info("Using official CDC SAS layout for %s: %s", table_name, url)
        return response.text
    except Exception as exc:
        logger.warning("Could not fetch SAS layout for %s from %s: %s", table_name, url, exc)
        return None


def parse_sas_input_layout(sas_text: str) -> dict[str, tuple[int, int]]:
    layout: dict[str, tuple[int, int]] = {}
    in_input = False
    saw_position = False
    position_pattern = re.compile(r"^\s*([A-Za-z][A-Za-z0-9_]{0,31})\s+\$?\s*(\d+)(?:\s*-\s*(\d+))?\s*(?:/\*.*)?$")

    for raw_line in sas_text.splitlines():
        line = raw_line.strip()
        if not in_input:
            if re.match(r"^INPUT\b", line, flags=re.IGNORECASE):
                in_input = True
            continue

        if saw_position and ("=" in line or line.startswith(";")):
            break
        if line.startswith(";"):
            break

        match = position_pattern.match(line)
        if not match:
            continue

        name = match.group(1).upper()
        start = int(match.group(2))
        end = int(match.group(3) or match.group(2))
        layout[name] = (start - 1, end)
        saw_position = True

    return layout


def read_fixed_width_table(
    data_path: Path,
    sas_text: str,
    needed_columns: list[str],
    table_name: str,
    logger: logging.Logger,
) -> pd.DataFrame:
    layout = parse_sas_input_layout(sas_text)
    needed = [column.upper() for column in needed_columns]
    available_needed = [column for column in needed if column in layout]
    missing_needed = sorted(set(needed) - set(available_needed))

    if missing_needed:
        logger.warning("%s SAS layout unavailable variables: %s", table_name, ", ".join(missing_needed))
    if "SEQN" not in available_needed:
        logger.warning("%s has no SEQN in the SAS layout and will be skipped", table_name)
        return pd.DataFrame()

    colspecs = [layout[column] for column in available_needed]
    frame = pd.read_fwf(
        data_path,
        colspecs=colspecs,
        names=available_needed,
        dtype=str,
        header=None,
        encoding="latin1",
    )
    frame = normalize_columns(frame)
    for column in frame.columns:
        frame[column] = frame[column].astype(str).str.strip().replace({"": np.nan, ".": np.nan})
    return frame


def read_non_fixed_table(path: Path) -> pd.DataFrame:
    suffix = path.suffix.lower()
    if suffix == ".csv":
        return normalize_columns(pd.read_csv(path, low_memory=False))
    if suffix in {".xpt", ".sas7bdat", ".sas7bdat7"}:
        return normalize_columns(pd.read_sas(path, encoding="latin1"))
    raise ValueError(f"Unsupported file type: {path}")


def first_by_seqn(frame: pd.DataFrame) -> pd.DataFrame:
    if "SEQN" not in frame.columns or frame.empty:
        return frame
    return frame.sort_values("SEQN").groupby("SEQN", as_index=False).first()


def load_table(raw_dir: Path, table_name: str, logger: logging.Logger) -> pd.DataFrame | None:
    spec = TABLE_SPECS[table_name]
    data_path = find_file_by_stem(raw_dir, spec["stems"], [".csv", ".xpt", ".sas7bdat", ".sas7bdat7", ".dat", ".txt"])
    if data_path is None:
        logger.warning("NHANES III %s data file unavailable", table_name)
        return None

    logger.info("Reading %s data from %s", table_name, data_path)
    if data_path.suffix.lower() in {".dat", ".txt"}:
        sas_text = sas_content_for_table(raw_dir, table_name, logger)
        if sas_text is None:
            logger.warning("Skipping %s because no SAS layout is available", table_name)
            return None
        frame = read_fixed_width_table(data_path, sas_text, spec["needed"], table_name, logger)
    else:
        frame = read_non_fixed_table(data_path)
        keep = [column for column in spec["needed"] if column in frame.columns]
        missing = sorted(set(spec["needed"]) - set(keep))
        if missing:
            logger.warning("%s data unavailable variables: %s", table_name, ", ".join(missing))
        frame = frame[keep].copy() if keep else pd.DataFrame()

    if frame.empty or "SEQN" not in frame.columns:
        logger.warning("%s did not yield a usable participant-level table", table_name)
        return None

    frame = first_by_seqn(frame)
    logger.info("Loaded %s: %s rows x %s columns", table_name, frame.shape[0], frame.shape[1])
    return frame


def merge_tables(tables: dict[str, pd.DataFrame], logger: logging.Logger) -> pd.DataFrame:
    merged: pd.DataFrame | None = None
    for table_name in ["adult", "exam", "lab", "lab2"]:
        frame = tables.get(table_name)
        if frame is None:
            continue
        if merged is None:
            merged = frame.copy()
            continue

        rename_map = {
            column: f"{column}_{table_name.upper()}"
            for column in frame.columns
            if column != "SEQN" and column in merged.columns
        }
        frame = frame.rename(columns=rename_map)
        merged = merged.merge(frame, on="SEQN", how="outer")

    if merged is None:
        logger.warning("No usable NHANES III tables were loaded")
        return pd.DataFrame()

    logger.info("Merged NHANES III source tables: %s rows x %s columns", merged.shape[0], merged.shape[1])
    return merged


def numeric_series(frame: pd.DataFrame, column: str) -> pd.Series:
    if column not in frame.columns:
        return pd.Series(np.nan, index=frame.index, dtype="float64")
    series = frame[column]
    if isinstance(series, pd.DataFrame):
        series = series.iloc[:, 0]
    cleaned = series.astype(str).str.strip().replace({"": np.nan, ".": np.nan, "nan": np.nan, "NaN": np.nan})
    return pd.to_numeric(cleaned, errors="coerce")


def coalesce_numeric(frame: pd.DataFrame, base_name: str) -> pd.Series:
    candidates = [column for column in frame.columns if column == base_name or column.startswith(f"{base_name}_")]
    result = pd.Series(np.nan, index=frame.index, dtype="float64")
    for column in candidates:
        result = result.combine_first(clean_continuous(numeric_series(frame, column)))
    return result


def clean_code(series: pd.Series) -> pd.Series:
    out = pd.to_numeric(series, errors="coerce")
    return out.mask(out.isin([7, 8, 9, 77, 88, 99, 777, 888, 999, 7777, 8888, 9999]))


def clean_continuous(series: pd.Series) -> pd.Series:
    out = pd.to_numeric(series, errors="coerce")
    missing_values = [
        777,
        888,
        999,
        7777,
        8888,
        9999,
        77777,
        88888,
        99999,
        777777,
        888888,
        999999,
        7777777,
        8888888,
        9999999,
    ]
    return out.mask(out.isin(missing_values))


def row_mean(frame: pd.DataFrame, columns: list[str]) -> pd.Series:
    existing = [column for column in columns if column in frame.columns]
    if not existing:
        return pd.Series(np.nan, index=frame.index, dtype="float64")
    values = frame[existing].apply(lambda col: clean_continuous(pd.to_numeric(col, errors="coerce")))
    values = values.mask(values <= 0)
    return values.mean(axis=1, skipna=True)


def derive_smoking(data: pd.DataFrame) -> pd.Series:
    har1 = clean_code(numeric_series(data, "HAR1"))
    har3 = clean_code(numeric_series(data, "HAR3"))
    status = pd.Series(np.nan, index=data.index, dtype="float64")
    status = status.mask(har1 == 2, 0)  # never smoker
    status = status.mask((har1 == 1) & (har3 == 2), 1)  # former smoker
    status = status.mask((har1 == 1) & (har3 == 1), 2)  # current smoker
    return status


def derive_alcohol(data: pd.DataFrame) -> pd.Series:
    beer = clean_continuous(numeric_series(data, "HAN6HS"))
    wine = clean_continuous(numeric_series(data, "HAN6IS"))
    liquor = clean_continuous(numeric_series(data, "HAN6JS"))
    drinks = pd.concat([beer, wine, liquor], axis=1)
    any_valid = drinks.notna().any(axis=1)
    any_drinking = drinks.fillna(0).gt(0).any(axis=1)

    status = pd.Series(np.nan, index=data.index, dtype="float64")
    status = status.mask(any_valid & ~any_drinking, 0)
    status = status.mask(any_drinking, 1)
    return status


def derive_diabetes(data: pd.DataFrame) -> pd.Series:
    had1 = clean_code(numeric_series(data, "HAD1"))
    had3 = clean_code(numeric_series(data, "HAD3"))
    had4 = clean_code(numeric_series(data, "HAD4"))
    status = pd.Series(np.nan, index=data.index, dtype="float64")

    status = status.mask((had1 == 2) | (had4 == 2), 0)
    status = status.mask((had4 == 1) | ((had1 == 1) & (had3 != 1)), 1)
    return status


def derive_hypertension(data: pd.DataFrame) -> pd.Series:
    hae2 = clean_code(numeric_series(data, "HAE2"))
    hae5a = clean_code(numeric_series(data, "HAE5A"))
    sbp = data["MEAN_SBP"]
    dbp = data["MEAN_DBP"]

    positive = (hae2 == 1) | (hae5a == 1) | (sbp >= 140) | (dbp >= 90)
    negative = (hae2 == 2) | ((sbp.notna() | dbp.notna()) & (sbp < 140) & (dbp < 90))
    status = pd.Series(np.nan, index=data.index, dtype="float64")
    status = status.mask(negative, 0)
    status = status.mask(positive, 1)
    return status


def ckd_epi_2021_egfr(scr: pd.Series, age: pd.Series, sex: pd.Series) -> pd.Series:
    scr = pd.to_numeric(scr, errors="coerce")
    age = pd.to_numeric(age, errors="coerce")
    sex = pd.to_numeric(sex, errors="coerce")
    female = sex == 2
    kappa = pd.Series(np.where(female, 0.7, 0.9), index=scr.index, dtype="float64")
    alpha = pd.Series(np.where(female, -0.241, -0.302), index=scr.index, dtype="float64")
    ratio = scr / kappa
    egfr = 142 * np.minimum(ratio, 1) ** alpha * np.maximum(ratio, 1) ** (-1.200) * (0.9938 ** age)
    egfr = egfr * np.where(female, 1.012, 1.0)
    egfr = pd.Series(egfr, index=scr.index, dtype="float64")
    egfr = egfr.mask(scr.le(0) | scr.isna() | age.isna() | sex.isna())
    return egfr


def derive_pregnancy(data: pd.DataFrame, logger: logging.Logger) -> pd.Series:
    candidates = ["MAPF12R", "MAPF12", "MYPC17", "PEPPREG"]
    available = [column for column in candidates if column in data.columns]
    if not available:
        logger.warning("Pregnancy variables unavailable; pregnancy exclusion will not remove anyone")
        return pd.Series(0, index=data.index, dtype="int64")

    values = pd.concat([clean_code(numeric_series(data, column)) for column in available], axis=1)
    return values.eq(1).any(axis=1).astype("int64")


def derive_thyroid_disease(data: pd.DataFrame, logger: logging.Logger) -> pd.Series:
    candidates = ["HAC1J", "HAC1K", "HAC2J", "HAC2K"]
    available = [column for column in candidates if column in data.columns]
    if not available:
        logger.warning("Known thyroid disease/goiter variables unavailable")
        return pd.Series(np.nan, index=data.index, dtype="float64")

    values = pd.concat([clean_code(numeric_series(data, column)) for column in available], axis=1)
    disease = values.eq(1).any(axis=1)
    valid = values.notna().any(axis=1)
    out = pd.Series(np.nan, index=data.index, dtype="float64")
    out = out.mask(valid & ~disease, 0)
    out = out.mask(disease, 1)
    return out


def detect_optional_thyroid_medication(raw_dir: Path, logger: logging.Logger) -> pd.DataFrame | None:
    skipped_stems = {"ADULT", "EXAM", "LAB", "LAB2"}
    candidate_files = [
        path
        for path in list_data_files(raw_dir)
        if path.stem.upper() not in skipped_stems and re.search(r"(RX|MED|DRUG)", path.stem, flags=re.IGNORECASE)
    ]
    if not candidate_files:
        logger.warning("Thyroid medication file unavailable; medication exclusion uses known thyroid disease only")
        return None

    pattern = re.compile("|".join(re.escape(keyword) for keyword in THYROID_MEDICATION_KEYWORDS), flags=re.IGNORECASE)
    for path in candidate_files:
        try:
            frame = read_non_fixed_table(path)
        except Exception as exc:
            logger.warning("Could not read optional medication file %s: %s", path, exc)
            continue
        if "SEQN" not in frame.columns:
            continue

        text_columns = [
            column
            for column in frame.columns
            if re.search(r"(DRUG|MED|NAME|RX|GENERIC)", column, flags=re.IGNORECASE)
        ]
        if not text_columns:
            continue

        text = frame[text_columns].fillna("").astype(str).agg(" ".join, axis=1)
        med = pd.DataFrame(
            {
                "SEQN": frame["SEQN"],
                "THYROID_MED_USE": text.str.contains(pattern, na=False).astype("int64"),
            }
        )
        logger.info("Detected thyroid medication text fields in %s", path)
        return med.groupby("SEQN", as_index=False)["THYROID_MED_USE"].max()

    logger.warning("Medication-like files were present, but no readable thyroid medication text fields were detected")
    return None


def derive_variables(merged: pd.DataFrame, logger: logging.Logger) -> pd.DataFrame:
    data = merged.copy()

    data["AGE_YEARS"] = clean_continuous(numeric_series(data, "HSAGEIR"))
    data["AGE_GROUP"] = pd.cut(
        data["AGE_YEARS"],
        bins=[17, 39, 64, math.inf],
        labels=["18-39", "40-64", ">=65"],
        right=True,
    )
    data["SEX"] = clean_code(numeric_series(data, "HSSEX"))
    data["RACE_ETHNICITY"] = clean_code(numeric_series(data, "DMARETHN")).combine_first(
        clean_code(numeric_series(data, "DMARACER"))
    )
    data["EDUCATION"] = clean_code(numeric_series(data, "HFA8R"))
    data["PIR"] = clean_continuous(numeric_series(data, "DMPPIR"))
    data["BMI"] = clean_continuous(numeric_series(data, "BMPBMI"))

    data["MEAN_SBP"] = clean_continuous(numeric_series(data, "PEPMNK1R")).combine_first(
        row_mean(data, ["PEP6G1", "PEP6H1", "PEP6I1"])
    )
    data["MEAN_DBP"] = clean_continuous(numeric_series(data, "PEPMNK5R")).combine_first(
        row_mean(data, ["PEP6G3", "PEP6H3", "PEP6I3"])
    )

    data["SMOKING_STATUS"] = derive_smoking(data)
    data["ALCOHOL_STATUS"] = derive_alcohol(data)
    data["DIABETES_STATUS"] = derive_diabetes(data)
    data["HYPERTENSION_STATUS"] = derive_hypertension(data)

    data["PREGNANT_FLAG"] = derive_pregnancy(data, logger)
    data["THYROID_DISEASE_FLAG"] = derive_thyroid_disease(data, logger)
    if "THYROID_MED_USE" not in data.columns:
        data["THYROID_MED_USE"] = np.nan

    data["URINE_ALBUMIN_UG_ML"] = clean_continuous(numeric_series(data, "UBP"))
    data["URINE_CREATININE_MG_DL"] = clean_continuous(numeric_series(data, "URP"))
    data["SERUM_CREATININE_MG_DL"] = clean_continuous(numeric_series(data, "CEP"))
    data["EGFR"] = ckd_epi_2021_egfr(data["SERUM_CREATININE_MG_DL"], data["AGE_YEARS"], data["SEX"])
    data["EGFR_CKD_EPI_2021"] = data["EGFR"]
    valid_uacr = data["URINE_ALBUMIN_UG_ML"].notna() & data["URINE_CREATININE_MG_DL"].gt(0)
    data["UACR_MG_G"] = np.nan
    data.loc[valid_uacr, "UACR_MG_G"] = (
        100 * data.loc[valid_uacr, "URINE_ALBUMIN_UG_ML"] / data.loc[valid_uacr, "URINE_CREATININE_MG_DL"]
    )
    data["LOG_UACR"] = np.where(data["UACR_MG_G"].gt(0), np.log(data["UACR_MG_G"]), np.nan)
    valid_uacr_values = data.loc[data["UACR_MG_G"].notna() & data["UACR_MG_G"].gt(0), "UACR_MG_G"]
    if len(valid_uacr_values) >= 4:
        breaks = np.unique(np.nanquantile(valid_uacr_values, [0, 0.25, 0.5, 0.75, 1.0]))
        if len(breaks) == 5:
            data["UACR_QUARTILE"] = pd.cut(
                data["UACR_MG_G"],
                bins=breaks,
                include_lowest=True,
                labels=["Q1", "Q2", "Q3", "Q4"],
            )
        else:
            logger.warning("UACR quartiles unavailable because quantile breaks are not unique")
            data["UACR_QUARTILE"] = np.nan
    else:
        logger.warning("UACR quartiles unavailable because valid UACR values are sparse")
        data["UACR_QUARTILE"] = np.nan
    data["UACR_CLINICAL_CATEGORY"] = pd.cut(
        data["UACR_MG_G"],
        bins=[-np.inf, 30, 300, np.inf],
        right=False,
        labels=["<30", "30-300", ">=300"],
    )

    data["TSH"] = clean_continuous(numeric_series(data, "THP"))
    data["TT4"] = clean_continuous(numeric_series(data, "T4P"))
    data["TGAB"] = clean_continuous(numeric_series(data, "TAP"))
    data["TPOAB"] = clean_continuous(numeric_series(data, "TMP"))

    data["WTPFEX6"] = coalesce_numeric(data, "WTPFEX6")
    data["SDPPSU6"] = coalesce_numeric(data, "SDPPSU6")
    data["SDPSTRA6"] = coalesce_numeric(data, "SDPSTRA6")

    data["AGE"] = data["AGE_YEARS"]
    data["RACE"] = data["RACE_ETHNICITY"]
    data["SMOKE"] = data["SMOKING_STATUS"]
    data["DRINK"] = data["ALCOHOL_STATUS"]
    data["DIABETES"] = data["DIABETES_STATUS"]
    data["HYPERTENSION"] = data["HYPERTENSION_STATUS"]
    data["UACR"] = data["UACR_MG_G"]

    thyroid_med = clean_code(pd.to_numeric(data["THYROID_MED_USE"], errors="coerce"))
    thyroid_disease = clean_code(pd.to_numeric(data["THYROID_DISEASE_FLAG"], errors="coerce"))
    data["THYROID_EXCLUSION_FLAG"] = np.where((thyroid_med == 1) | (thyroid_disease == 1), 1, 0)
    return data


def available_thyroid_table(data: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for output_name, mapping in COMMON_THYROID_MAP.items():
        source = mapping["validation_source"]
        derived = data[output_name] if output_name in data.columns else pd.Series(dtype="float64")
        available = source in data.columns or output_name in data.columns
        rows.append(
            {
                "indicator": output_name,
                "nhanes3_source_variable": source,
                "available": bool(available and derived.notna().any()),
                "nonmissing_n": int(derived.notna().sum()) if len(derived) else 0,
            }
        )
    return pd.DataFrame(rows)


def add_flow_row(
    rows: list[dict[str, object]],
    step: str,
    before: int,
    after: int,
    note: str = "",
) -> None:
    rows.append(
        {
            "step": step,
            "n_before": before,
            "n_excluded": before - after,
            "n_after": after,
            "note": note,
        }
    )


def apply_keep(
    data: pd.DataFrame,
    rows: list[dict[str, object]],
    step: str,
    keep_mask: pd.Series,
    note: str = "",
) -> pd.DataFrame:
    before = len(data)
    keep_mask = keep_mask.fillna(False).astype(bool)
    out = data.loc[keep_mask].copy()
    add_flow_row(rows, step, before, len(out), note)
    return out


def apply_exclusions(data: pd.DataFrame, thyroid_availability: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    rows: list[dict[str, object]] = []
    add_flow_row(rows, "Merged NHANES III records", len(data), len(data), "Before validation exclusions")

    data = apply_keep(data, rows, "Age >= 18 years", data["AGE_YEARS"] >= 18)
    data = apply_keep(data, rows, "Exclude pregnant participants", data["PREGNANT_FLAG"] != 1)

    thyroid_exclusion_available = data["THYROID_DISEASE_FLAG"].notna().any() or data["THYROID_MED_USE"].notna().any()
    if thyroid_exclusion_available:
        data = apply_keep(
            data,
            rows,
            "Exclude known thyroid disease or thyroid medication use",
            data["THYROID_EXCLUSION_FLAG"] != 1,
        )
    else:
        add_flow_row(
            rows,
            "Known thyroid disease / medication exclusion unavailable",
            len(data),
            len(data),
            "No available thyroid disease or medication variable detected",
        )

    data = apply_keep(data, rows, "Valid UACR > 0", data["UACR_MG_G"].notna() & data["UACR_MG_G"].gt(0))

    if "TT4" in data.columns and data["TT4"].notna().any():
        data = apply_keep(data, rows, "Nonmissing TT4 validation outcome", data["TT4"].notna())
    else:
        before = len(data)
        data = data.iloc[0:0].copy()
        add_flow_row(
            rows,
            "No available TT4 validation outcome",
            before,
            0,
            "TT4 is required for validation; TSH, TGAb, and TPOAb are exploratory indicators",
        )

    data = apply_keep(
        data,
        rows,
        "Nonmissing key covariates",
        data[KEY_COVARIATES].notna().all(axis=1),
        ", ".join(KEY_COVARIATES),
    )
    return data, pd.DataFrame(rows)


def recompute_final_uacr_categories(data: pd.DataFrame, logger: logging.Logger) -> pd.DataFrame:
    out = data.copy()
    valid = out["UACR_MG_G"].notna() & out["UACR_MG_G"].gt(0)
    if int(valid.sum()) >= 4:
        breaks = np.unique(np.nanquantile(out.loc[valid, "UACR_MG_G"], [0, 0.25, 0.5, 0.75, 1.0]))
        if len(breaks) == 5:
            out["UACR_QUARTILE"] = pd.cut(
                out["UACR_MG_G"],
                bins=breaks,
                include_lowest=True,
                labels=["Q1", "Q2", "Q3", "Q4"],
            )
            counts = out["UACR_QUARTILE"].value_counts(dropna=False).sort_index()
            logger.info(
                "Final validation UACR quartile counts: %s",
                "; ".join(f"{idx}={int(value)}" for idx, value in counts.items()),
            )
        else:
            logger.warning("Final validation UACR quartiles unavailable because quantile breaks are not unique")
            out["UACR_QUARTILE"] = np.nan
    else:
        logger.warning("Final validation UACR quartiles unavailable because fewer than 4 valid UACR values remain")
        out["UACR_QUARTILE"] = np.nan

    out["UACR_CLINICAL_CATEGORY"] = pd.cut(
        out["UACR_MG_G"],
        bins=[-np.inf, 30, 300, np.inf],
        right=False,
        labels=["<30", "30-300", ">=300"],
    )
    out["UACR"] = out["UACR_MG_G"]
    return out


def write_empty_outputs(root: Path, message: str, logger: logging.Logger) -> None:
    output_path = root / "data" / "processed" / "validation_nhanes3.csv"
    flow_path = root / "outputs" / "tables" / "validation_exclusion_flow.csv"
    thyroid_path = root / "outputs" / "tables" / "validation_available_thyroid_indicators.csv"

    pd.DataFrame(columns=OUTPUT_COLUMNS).to_csv(output_path, index=False)
    pd.DataFrame(
        [
            {
                "step": "No source data",
                "n_before": 0,
                "n_excluded": 0,
                "n_after": 0,
                "note": message,
            }
        ]
    ).to_csv(flow_path, index=False)
    pd.DataFrame(
        [
            {
                "indicator": indicator,
                "nhanes3_source_variable": mapping["validation_source"],
                "available": False,
                "nonmissing_n": 0,
            }
            for indicator, mapping in COMMON_THYROID_MAP.items()
        ]
    ).to_csv(thyroid_path, index=False)
    write_harmonized_map(pd.DataFrame(), root, logger)
    logger.warning(message)
    logger.warning("Wrote empty validation outputs")


def write_harmonized_map(data: pd.DataFrame, root: Path, logger: logging.Logger) -> None:
    map_path = root / "outputs" / "tables" / "harmonized_variable_map.csv"
    variable_rows = [
        ("participant_id", "SEQN", "SEQN", "SEQN", "Participant identifier"),
        ("age", "RIDAGEYR", "HSAGEIR", "AGE_YEARS", "Age in years"),
        ("sex", "RIAGENDR", "HSSEX", "SEX", "Sex"),
        ("race_ethnicity", "RIDRETH1", "DMARETHN / DMARACER", "RACE_ETHNICITY", "Race/ethnicity"),
        ("education", "DMDEDUC2", "HFA8R", "EDUCATION", "Education"),
        ("poverty_income_ratio", "INDFMPIR", "DMPPIR", "PIR", "Poverty income ratio"),
        ("bmi", "BMXBMI", "BMPBMI", "BMI", "Body mass index"),
        ("smoking", "SMQ020 / SMQ040", "HAR1 / HAR3", "SMOKING_STATUS", "Never/former/current smoking"),
        ("alcohol", "ALQ101 / ALQ110", "HAN6HS / HAN6IS / HAN6JS", "ALCOHOL_STATUS", "Any alcohol intake marker"),
        ("diabetes", "DIQ010", "HAD1 / HAD3 / HAD4", "DIABETES_STATUS", "Self-reported diabetes"),
        ("hypertension", "BPQ020 / BPQ050A / BPX", "HAE2 / HAE5A / PEP", "HYPERTENSION_STATUS", "Self-report, medication, or BP"),
        ("urine_albumin", "URXUMA / URXUMS", "UBP", "URINE_ALBUMIN_UG_ML", "Urinary albumin"),
        ("urine_creatinine", "URXUCR", "URP", "URINE_CREATININE_MG_DL", "Urinary creatinine"),
        ("uacr", "UACR_MG_G", "100 * UBP / URP", "UACR_MG_G", "Urine albumin-to-creatinine ratio"),
        ("log_uacr", "LOG_UACR", "log(UACR_MG_G)", "LOG_UACR", "Natural log UACR"),
        ("tsh", "LBXTSH1", "THP", "TSH", "Common thyroid indicator"),
        ("tt4", "LBXTT4", "T4P", "TT4", "Common thyroid indicator"),
        ("tgab", "LBXATG", "TAP", "TGAB", "Common thyroid autoimmunity indicator"),
        ("tpoab", "LBXTPO", "TMP", "TPOAB", "Common thyroid autoimmunity indicator"),
        ("survey_weight", "WTSA6YR / WTMEC6YR", "WTPFEX6", "WTPFEX6", "NHANES III MEC-examined weight"),
        ("psu", "SDMVPSU", "SDPPSU6", "SDPPSU6", "Pseudo-PSU"),
        ("strata", "SDMVSTRA", "SDPSTRA6", "SDPSTRA6", "Pseudo-stratum"),
    ]
    rows = []
    for concept, discovery, validation, harmonized, note in variable_rows:
        status = "available" if (not data.empty and harmonized in data.columns and data[harmonized].notna().any()) else "unavailable_or_not_loaded"
        rows.append(
            {
                "concept": concept,
                "discovery_variable": discovery,
                "validation_nhanes3_variable": validation,
                "harmonized_output_variable": harmonized,
                "validation_status": status,
                "note": note,
            }
        )
    pd.DataFrame(rows).to_csv(map_path, index=False)
    logger.info("Wrote harmonized variable map to %s", map_path)


def write_qc_report(data: pd.DataFrame, thyroid_availability: pd.DataFrame, root: Path, logger: logging.Logger) -> None:
    report_path = root / "outputs" / "reports" / "validation_nhanes3_qc_report.md"
    lines = [
        "# NHANES III Validation Cohort QC",
        "",
        f"Final analytic sample size: {len(data)}",
        "",
        "Available common thyroid indicators:",
        "",
    ]
    for row in thyroid_availability.itertuples(index=False):
        status = "available" if row.available else "unavailable"
        lines.append(f"- {row.indicator} ({row.nhanes3_source_variable}): {status}, nonmissing n={row.nonmissing_n}")
        if not row.available:
            logger.warning("Common thyroid indicator unavailable: %s (%s)", row.indicator, row.nhanes3_source_variable)

    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    logger.info("Wrote QC report to %s", report_path)


def main() -> None:
    root = find_project_root(Path(__file__))
    ensure_output_dirs(root)
    logger = setup_logger(root)
    raw_dir = choose_raw_dir(root, logger)

    logger.info("Project root: %s", root)
    logger.info("Raw NHANES III directory: %s", raw_dir)
    ensure_nhanes3_sources(raw_dir, logger)

    data_files = list_data_files(raw_dir)
    logger.info("Detected %s data files under raw directory", len(data_files))
    if not data_files:
        write_empty_outputs(
            root,
            "No NHANES III data files found. Place ADULT/EXAM/LAB/LAB2 files under data/raw/nhanes3/ and rerun.",
            logger,
        )
        return

    tables = {name: load_table(raw_dir, name, logger) for name in ["adult", "exam", "lab", "lab2"]}
    merged = merge_tables(tables, logger)
    if merged.empty:
        write_empty_outputs(root, "No usable NHANES III source tables were loaded.", logger)
        return

    med_flags = detect_optional_thyroid_medication(raw_dir, logger)
    if med_flags is not None:
        merged = merged.merge(med_flags, on="SEQN", how="left")
        merged["THYROID_MED_USE"] = merged["THYROID_MED_USE"].fillna(0)

    derived = derive_variables(merged, logger)
    if derived["EGFR"].notna().any():
        logger.info("eGFR available from NHANES III serum creatinine CEP; nonmissing n=%s", int(derived["EGFR"].notna().sum()))
    else:
        logger.warning("eGFR unavailable because serum creatinine CEP is missing or unusable")
    thyroid_availability = available_thyroid_table(derived)

    thyroid_path = root / "outputs" / "tables" / "validation_available_thyroid_indicators.csv"
    thyroid_availability.to_csv(thyroid_path, index=False)
    logger.info("Wrote available thyroid indicator list to %s", thyroid_path)

    final, flow = apply_exclusions(derived, thyroid_availability)
    final = recompute_final_uacr_categories(final, logger)
    for column in OUTPUT_COLUMNS:
        if column not in final.columns:
            final[column] = np.nan

    output_path = root / "data" / "processed" / "validation_nhanes3.csv"
    flow_path = root / "outputs" / "tables" / "validation_exclusion_flow.csv"
    final[OUTPUT_COLUMNS].to_csv(output_path, index=False)
    flow.to_csv(flow_path, index=False)
    write_harmonized_map(derived, root, logger)
    write_qc_report(final, thyroid_availability, root, logger)

    logger.info("Wrote validation cohort to %s", output_path)
    logger.info("Wrote exclusion flow to %s", flow_path)
    logger.info("Final NHANES III validation sample size: %s", len(final))


if __name__ == "__main__":
    main()
