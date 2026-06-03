from __future__ import annotations

import logging
import math
import re
import sys
from pathlib import Path
from typing import Iterable

import numpy as np
import pandas as pd


EXPECTED_FINAL_N = 6357

CYCLES = {
    "E": "2007-2008",
    "F": "2009-2010",
    "G": "2011-2012",
}

COMPONENT_ORDER = [
    "DEMO",
    "BMX",
    "BPX",
    "BPQ",
    "DIQ",
    "SMQ",
    "ALQ",
    "PAQ",
    "BIOPRO",
    "ALB_CR",
    "UIO",
    "THYROD",
]

COMPONENT_SPECS = {
    "DEMO": {
        "keep": [
            "SEQN",
            "RIDAGEYR",
            "RIAGENDR",
            "RIDRETH1",
            "DMDEDUC2",
            "DMDEDUC3",
            "INDFMPIR",
            "RIDEXPRG",
            "WTMEC2YR",
            "SDMVPSU",
            "SDMVSTRA",
        ],
        "rename": {},
    },
    "BMX": {"keep": ["SEQN", "BMXBMI"], "rename": {}},
    "BPX": {
        "keep": [
            "SEQN",
            "BPXSY1",
            "BPXSY2",
            "BPXSY3",
            "BPXSY4",
            "BPXDI1",
            "BPXDI2",
            "BPXDI3",
            "BPXDI4",
        ],
        "rename": {},
    },
    "BPQ": {"keep": ["SEQN", "BPQ020", "BPQ050A"], "rename": {}},
    "DIQ": {"keep": ["SEQN", "DIQ010"], "rename": {}},
    "SMQ": {"keep": ["SEQN", "SMQ020", "SMQ040"], "rename": {}},
    "ALQ": {"keep": ["SEQN", "ALQ101", "ALQ110", "ALQ120Q", "ALQ120U", "ALQ130"], "rename": {}},
    "PAQ": {
        "keep": [
            "SEQN",
            "PAQ605",
            "PAQ620",
            "PAQ635",
            "PAQ650",
            "PAQ665",
            "PAD615",
            "PAD630",
            "PAD645",
            "PAD660",
            "PAD675",
        ],
        "rename": {},
    },
    "BIOPRO": {"keep": ["SEQN", "LBXSCR", "LBDSCRSI"], "rename": {}},
    "ALB_CR": {"keep": ["SEQN", "URXUMA", "URXUMS", "URXUCR", "URXCRS", "URDACT"], "rename": {}},
    "UIO": {
        "keep": ["SEQN", "WTSA2YR", "URXUIO", "URXUCR"],
        "rename": {"WTSA2YR": "WTSA2YR_UIO", "URXUCR": "URXUCR_UIO"},
    },
    "THYROD": {
        "keep": [
            "SEQN",
            "WTSA2YR",
            "LBXTSH1",
            "LBXT3F",
            "LBXT4F",
            "LBXTT3",
            "LBXTT4",
            "LBXTGN",
            "LBXATG",
            "LBXTPO",
        ],
        "rename": {"WTSA2YR": "WTSA2YR_THYROD"},
    },
}

RX_COMPONENT = "RXQ_RX"
RX_KEEP = ["SEQN", "RXDDRUG", "RXDDRGID", "RXDCOUNT", "RXDDAYS"]

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
    "NP THYROID",
    "METHIMAZOLE",
    "TAPAZOLE",
    "PROPYLTHIOURACIL",
    "PTU",
]

CORE_THYROID_COLUMNS = ["TSH", "TT4", "TGAB", "TPOAB"]

KEY_COVARIATES = [
    "AGE",
    "SEX",
    "RACE",
    "EDUCATION",
    "PIR",
    "BMI",
    "SMOKE",
    "DRINK",
    "DIABETES",
    "HYPERTENSION",
    "PHYSICAL_ACTIVITY",
    "UIC_UG_L",
    "EGFR",
    "ANALYTIC_WT6YR",
    "SDMVPSU",
    "SDMVSTRA",
]

REQUIRED_USER_COLUMNS = [
    "SEQN",
    "CYCLE",
    "AGE",
    "SEX",
    "RACE",
    "EDUCATION",
    "PIR",
    "BMI",
    "SMOKE",
    "DRINK",
    "DIABETES",
    "HYPERTENSION",
    "PHYSICAL_ACTIVITY",
    "UIC_UG_L",
    "EGFR",
    "UACR",
    "LOG_UACR",
    "UACR_QUARTILE",
    "UACR_QUARTILE_UNWEIGHTED",
    "UACR_QUARTILE_WEIGHTED",
    "UACR_CLINICAL_CATEGORY",
    "TSH",
    "FT3",
    "FT4",
    "TT3",
    "TT4",
    "TG",
    "TGAB",
    "TPOAB",
    "ANALYTIC_WT2YR",
    "ANALYTIC_WT6YR",
    "WEIGHT_SOURCE",
    "WTSA2YR",
    "WTSA6YR",
    "STRICT_WTSA6YR",
    "WTMEC2YR",
    "SDMVPSU",
    "SDMVSTRA",
]

COMPATIBILITY_COLUMNS_FOR_03 = [
    "NHANES_CYCLE",
    "NHANES_SUFFIX",
    "AGE_YEARS",
    "RACE_ETHNICITY",
    "SMOKING_STATUS",
    "ALCOHOL_STATUS",
    "DIABETES_STATUS",
    "HYPERTENSION_STATUS",
    "PHYSICAL_ACTIVITY_ANY",
    "EGFR_CKD_EPI_2021",
    "UACR_MG_G",
    "WTMEC6YR",
    "WTSA2YR_THYROD",
    "WTSA2YR_UIO",
]

QC_COLUMNS = [
    "AGE_GROUP",
    "MEAN_SBP",
    "MEAN_DBP",
    "URINE_ALBUMIN_UG_ML",
    "URINE_CREATININE_MG_DL",
    "SERUM_CREATININE_MG_DL",
    "PREGNANT_FLAG",
    "THYROID_MED_USE",
    "RXQ_AVAILABLE",
]

OUTPUT_COLUMNS = REQUIRED_USER_COLUMNS + COMPATIBILITY_COLUMNS_FOR_03 + QC_COLUMNS


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
    log_path = log_dir / "01_build_discovery.log"

    logger = logging.getLogger("01_build_discovery")
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
        "data/raw/nhanes_2007_2012",
        "data/processed",
        "outputs/tables",
        "outputs/logs",
        "outputs/reports",
    ]:
        (root / relative).mkdir(parents=True, exist_ok=True)


def list_xpt_files(raw_dir: Path) -> list[Path]:
    if not raw_dir.exists():
        return []
    return sorted(path for path in raw_dir.rglob("*") if path.is_file() and path.suffix.lower() == ".xpt")


def build_xpt_index(raw_dir: Path) -> dict[str, Path]:
    return {path.stem.upper(): path for path in list_xpt_files(raw_dir)}


def find_component_path(xpt_index: dict[str, Path], component: str, suffix: str) -> Path | None:
    exact = f"{component}_{suffix}".upper()
    if exact in xpt_index:
        return xpt_index[exact]

    pattern = re.compile(rf"^{re.escape(component.upper())}.*_{suffix.upper()}$")
    matches = [path for stem, path in xpt_index.items() if pattern.match(stem)]
    return sorted(matches)[0] if matches else None


def read_xpt(path: Path) -> pd.DataFrame:
    frame = pd.read_sas(path, format="xport", encoding="latin1")
    frame.columns = [str(column).upper() for column in frame.columns]
    return frame


def first_by_seqn(frame: pd.DataFrame) -> pd.DataFrame:
    if "SEQN" not in frame.columns:
        return frame
    if not frame["SEQN"].duplicated().any():
        return frame
    return frame.sort_values("SEQN").groupby("SEQN", as_index=False).first()


def load_component(
    xpt_index: dict[str, Path],
    component: str,
    suffix: str,
    logger: logging.Logger,
) -> pd.DataFrame | None:
    path = find_component_path(xpt_index, component, suffix)
    if path is None:
        logger.warning("Missing %s_%s XPT file", component, suffix)
        return None

    spec = COMPONENT_SPECS[component]
    frame = read_xpt(path)
    keep = [column for column in spec["keep"] if column in frame.columns]
    missing = sorted(set(spec["keep"]) - set(keep))

    if "SEQN" not in keep:
        logger.warning("%s has no SEQN column and will be skipped: %s", component, path)
        return None

    if missing:
        logger.warning("%s_%s missing variables: %s", component, suffix, ", ".join(missing))

    out = frame[keep].copy().rename(columns=spec["rename"])
    out = first_by_seqn(out)
    logger.info("Loaded %-7s %s: %s rows x %s columns", component, suffix, out.shape[0], out.shape[1])
    return out


def load_rx_component(
    xpt_index: dict[str, Path],
    suffix: str,
    logger: logging.Logger,
) -> pd.DataFrame | None:
    path = find_component_path(xpt_index, RX_COMPONENT, suffix)
    if path is None:
        logger.warning("Missing %s_%s XPT file; thyroid medication exclusion unavailable for this cycle", RX_COMPONENT, suffix)
        return None

    frame = read_xpt(path)
    keep = [column for column in RX_KEEP if column in frame.columns]
    if "SEQN" not in keep:
        logger.warning("%s has no SEQN column and will be skipped: %s", RX_COMPONENT, path)
        return None

    text_columns = [column for column in keep if column != "SEQN"]
    text = frame[text_columns].fillna("").astype(str).agg(" ".join, axis=1).str.upper()
    pattern = re.compile("|".join(re.escape(keyword) for keyword in THYROID_MEDICATION_KEYWORDS))
    out = pd.DataFrame(
        {
            "SEQN": frame["SEQN"],
            "THYROID_MED_USE": text.str.contains(pattern, na=False).astype("int64"),
        }
    )
    out = out.groupby("SEQN", as_index=False)["THYROID_MED_USE"].max()
    logger.info("Loaded RXQ_RX %s: %s participants with prescription records", suffix, out.shape[0])
    return out


def merge_component(base: pd.DataFrame | None, incoming: pd.DataFrame) -> pd.DataFrame:
    if base is None:
        return incoming.copy()
    duplicate_columns = [column for column in incoming.columns if column != "SEQN" and column in base.columns]
    incoming = incoming.drop(columns=duplicate_columns)
    return base.merge(incoming, on="SEQN", how="left")


def load_cycle(raw_dir: Path, suffix: str, cycle_name: str, logger: logging.Logger) -> pd.DataFrame | None:
    xpt_index = build_xpt_index(raw_dir)
    cycle_frame: pd.DataFrame | None = None

    for component in COMPONENT_ORDER:
        component_frame = load_component(xpt_index, component, suffix, logger)
        if component_frame is not None:
            cycle_frame = merge_component(cycle_frame, component_frame)

    if cycle_frame is None:
        logger.warning("No usable participant-level files found for %s", cycle_name)
        return None

    rx_frame = load_rx_component(xpt_index, suffix, logger)
    cycle_frame["RXQ_AVAILABLE"] = int(rx_frame is not None)
    if rx_frame is not None:
        cycle_frame = cycle_frame.merge(rx_frame, on="SEQN", how="left")
        cycle_frame["THYROID_MED_USE"] = cycle_frame["THYROID_MED_USE"].fillna(0).astype("int64")
    else:
        cycle_frame["THYROID_MED_USE"] = np.nan

    cycle_frame["CYCLE"] = cycle_name
    cycle_frame["NHANES_CYCLE"] = cycle_name
    cycle_frame["NHANES_SUFFIX"] = suffix
    logger.info("%s merged shape: %s rows x %s columns", cycle_name, cycle_frame.shape[0], cycle_frame.shape[1])
    return cycle_frame


def get_numeric(frame: pd.DataFrame, column: str) -> pd.Series:
    if column not in frame.columns:
        return pd.Series(np.nan, index=frame.index, dtype="float64")
    return pd.to_numeric(frame[column], errors="coerce")


def coalesce_columns(frame: pd.DataFrame, columns: Iterable[str]) -> pd.Series:
    result = pd.Series(np.nan, index=frame.index, dtype="float64")
    for column in columns:
        if column in frame.columns:
            result = result.combine_first(get_numeric(frame, column))
    return result


def clean_categorical(series: pd.Series, missing_codes: Iterable[int] = (7, 9, 77, 99, 777, 999)) -> pd.Series:
    out = pd.to_numeric(series, errors="coerce")
    return out.mask(out.isin(list(missing_codes)))


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
    ]
    return out.mask(out.isin(missing_values))


def row_mean_positive(frame: pd.DataFrame, columns: list[str]) -> pd.Series:
    existing = [column for column in columns if column in frame.columns]
    if not existing:
        return pd.Series(np.nan, index=frame.index, dtype="float64")
    values = frame[existing].apply(pd.to_numeric, errors="coerce").mask(lambda x: x <= 0)
    return values.mean(axis=1, skipna=True)


def derive_smoking(frame: pd.DataFrame) -> pd.Series:
    smq020 = clean_categorical(get_numeric(frame, "SMQ020"))
    smq040 = clean_categorical(get_numeric(frame, "SMQ040"))
    status = pd.Series(np.nan, index=frame.index, dtype="float64")
    status = status.mask(smq020 == 2, 0)
    status = status.mask((smq020 == 1) & (smq040 == 3), 1)
    status = status.mask((smq020 == 1) & (smq040.isin([1, 2])), 2)
    return status


def derive_alcohol(frame: pd.DataFrame) -> pd.Series:
    alq101 = clean_categorical(get_numeric(frame, "ALQ101"))
    alq110 = clean_categorical(get_numeric(frame, "ALQ110"))
    alq120q = clean_continuous(get_numeric(frame, "ALQ120Q"))
    alq130 = clean_continuous(get_numeric(frame, "ALQ130"))

    status = pd.Series(np.nan, index=frame.index, dtype="float64")
    status = status.mask(alq101 == 1, 1)
    status = status.mask(alq101 == 2, 0)
    status = status.mask(status.isna() & (alq110 == 1), 1)
    status = status.mask(status.isna() & (alq110 == 2), 0)
    status = status.mask(status.isna() & ((alq120q > 0) | (alq130 > 0)), 1)
    return status


def derive_diabetes(frame: pd.DataFrame) -> pd.Series:
    diq010 = clean_categorical(get_numeric(frame, "DIQ010"))
    status = pd.Series(np.nan, index=frame.index, dtype="float64")
    status = status.mask(diq010 == 1, 1)
    status = status.mask(diq010 == 2, 0)
    status = status.mask(diq010 == 3, 2)
    return status


def derive_physical_activity(frame: pd.DataFrame) -> pd.Series:
    pa_columns = ["PAQ605", "PAQ620", "PAQ635", "PAQ650", "PAQ665"]
    existing = [column for column in pa_columns if column in frame.columns]
    if not existing:
        return pd.Series(np.nan, index=frame.index, dtype="float64")

    values = frame[existing].apply(pd.to_numeric, errors="coerce")
    values = values.mask(values.isin([7, 9, 77, 99]))
    any_yes = (values == 1).any(axis=1)
    any_valid = values.notna().any(axis=1)
    all_no = (values.where(values.notna()) == 2).all(axis=1) & any_valid

    status = pd.Series(np.nan, index=frame.index, dtype="float64")
    status = status.mask(all_no, 0)
    status = status.mask(any_yes, 1)
    return status


def derive_hypertension(frame: pd.DataFrame) -> pd.Series:
    bpq020 = clean_categorical(get_numeric(frame, "BPQ020"))
    bpq050a = clean_categorical(get_numeric(frame, "BPQ050A"))
    sbp = frame["MEAN_SBP"]
    dbp = frame["MEAN_DBP"]

    positive = (bpq020 == 1) | (bpq050a == 1) | (sbp >= 140) | (dbp >= 90)
    negative = (bpq020 == 2) | ((sbp.notna() | dbp.notna()) & (sbp < 140) & (dbp < 90))

    status = pd.Series(np.nan, index=frame.index, dtype="float64")
    status = status.mask(negative, 0)
    status = status.mask(positive, 1)
    return status


def derive_egfr_2021(scr_mg_dl: pd.Series, age: pd.Series, sex: pd.Series) -> pd.Series:
    scr = pd.to_numeric(scr_mg_dl, errors="coerce")
    age = pd.to_numeric(age, errors="coerce")
    sex = pd.to_numeric(sex, errors="coerce")

    female = sex == 2
    kappa = pd.Series(np.where(female, 0.7, 0.9), index=scr.index, dtype="float64")
    alpha = pd.Series(np.where(female, -0.241, -0.302), index=scr.index, dtype="float64")
    sex_multiplier = pd.Series(np.where(female, 1.012, 1.0), index=scr.index, dtype="float64")

    valid = scr.gt(0) & age.notna() & sex.isin([1, 2])
    egfr = pd.Series(np.nan, index=scr.index, dtype="float64")
    scr_k = scr / kappa
    egfr.loc[valid] = (
        142
        * np.minimum(scr_k.loc[valid], 1) ** alpha.loc[valid]
        * np.maximum(scr_k.loc[valid], 1) ** -1.200
        * (0.9938 ** age.loc[valid])
        * sex_multiplier.loc[valid]
    )
    return egfr


def weighted_quantile(values: pd.Series, weights: pd.Series, probs: list[float]) -> np.ndarray:
    valid = values.notna() & weights.notna() & (weights > 0)
    x = values.loc[valid].astype(float).to_numpy()
    w = weights.loc[valid].astype(float).to_numpy()
    if len(x) == 0:
        return np.array([np.nan] * len(probs))
    order = np.argsort(x)
    x = x[order]
    w = w[order]
    cdf = np.cumsum(w) / np.sum(w)
    return np.interp(probs, cdf, x)


def assign_quartiles(values: pd.Series, breaks: Iterable[float], labels: list[str]) -> pd.Series:
    breaks = np.array(list(breaks), dtype="float64")
    if np.any(pd.isna(breaks)) or len(np.unique(breaks)) != len(breaks):
        return pd.Series(pd.NA, index=values.index, dtype="object")
    return pd.cut(values, bins=breaks, include_lowest=True, labels=labels).astype("object")


def derive_analysis_variables(frame: pd.DataFrame, logger: logging.Logger) -> pd.DataFrame:
    data = frame.copy()

    data["AGE"] = clean_continuous(get_numeric(data, "RIDAGEYR"))
    data["AGE_YEARS"] = data["AGE"]
    data["AGE_GROUP"] = pd.cut(data["AGE"], bins=[17, 39, 64, math.inf], labels=["18-39", "40-64", ">=65"], right=True)
    data["SEX"] = clean_categorical(get_numeric(data, "RIAGENDR"))
    data["RACE"] = clean_categorical(get_numeric(data, "RIDRETH1"))
    data["RACE_ETHNICITY"] = data["RACE"]
    data["EDUCATION"] = clean_categorical(get_numeric(data, "DMDEDUC2")).combine_first(
        clean_categorical(get_numeric(data, "DMDEDUC3"))
    )
    data["PIR"] = clean_continuous(get_numeric(data, "INDFMPIR"))
    data["BMI"] = clean_continuous(get_numeric(data, "BMXBMI"))
    data["PREGNANT_FLAG"] = (get_numeric(data, "RIDEXPRG") == 1).astype("int64")

    data["MEAN_SBP"] = row_mean_positive(data, ["BPXSY1", "BPXSY2", "BPXSY3", "BPXSY4"])
    data["MEAN_DBP"] = row_mean_positive(data, ["BPXDI1", "BPXDI2", "BPXDI3", "BPXDI4"])
    data["SMOKE"] = derive_smoking(data)
    data["SMOKING_STATUS"] = data["SMOKE"]
    data["DRINK"] = derive_alcohol(data)
    data["ALCOHOL_STATUS"] = data["DRINK"]
    data["DIABETES"] = derive_diabetes(data)
    data["DIABETES_STATUS"] = data["DIABETES"]
    data["PHYSICAL_ACTIVITY"] = derive_physical_activity(data)
    data["PHYSICAL_ACTIVITY_ANY"] = data["PHYSICAL_ACTIVITY"]
    data["HYPERTENSION"] = derive_hypertension(data)
    data["HYPERTENSION_STATUS"] = data["HYPERTENSION"]

    data["UIC_UG_L"] = clean_continuous(get_numeric(data, "URXUIO"))
    serum_creatinine = clean_continuous(get_numeric(data, "LBXSCR"))
    serum_creatinine = serum_creatinine.combine_first(clean_continuous(get_numeric(data, "LBDSCRSI")) / 88.4)
    data["SERUM_CREATININE_MG_DL"] = serum_creatinine
    data["EGFR"] = derive_egfr_2021(data["SERUM_CREATININE_MG_DL"], data["AGE"], data["SEX"])
    data["EGFR_CKD_EPI_2021"] = data["EGFR"]

    data["WTMEC2YR"] = clean_continuous(get_numeric(data, "WTMEC2YR"))
    data["WTSA2YR"] = coalesce_columns(data, ["WTSA2YR_THYROD", "WTSA2YR_UIO"])
    data["STRICT_WTSA6YR"] = data["WTSA2YR"] / len(CYCLES)
    data["WTMEC6YR"] = data["WTMEC2YR"] / len(CYCLES)

    suffix = data["NHANES_SUFFIX"].astype(str)
    data["ANALYTIC_WT2YR"] = np.nan
    data["WEIGHT_SOURCE"] = pd.NA
    use_mec_2007 = suffix.eq("E") & data["WTMEC2YR"].notna() & data["WTMEC2YR"].gt(0)
    use_wtsa_2009_2012 = suffix.isin(["F", "G"]) & data["WTSA2YR_THYROD"].notna() & data["WTSA2YR_THYROD"].gt(0)
    data.loc[use_mec_2007, "ANALYTIC_WT2YR"] = data.loc[use_mec_2007, "WTMEC2YR"]
    data.loc[use_mec_2007, "WEIGHT_SOURCE"] = "WTMEC2YR_2007_2008"
    data.loc[use_wtsa_2009_2012, "ANALYTIC_WT2YR"] = data.loc[use_wtsa_2009_2012, "WTSA2YR_THYROD"]
    data.loc[use_wtsa_2009_2012, "WEIGHT_SOURCE"] = "WTSA2YR_2009_2012"
    data["ANALYTIC_WT6YR"] = data["ANALYTIC_WT2YR"] / len(CYCLES)

    # Backward-compatible alias for older R scripts; strict subsample weight is STRICT_WTSA6YR.
    data["WTSA6YR"] = data["ANALYTIC_WT6YR"]

    if {"WTSA2YR_THYROD", "WTSA2YR_UIO"}.issubset(data.columns):
        both_weights = data["WTSA2YR_THYROD"].notna() & data["WTSA2YR_UIO"].notna()
        if both_weights.any():
            max_abs_diff = (data.loc[both_weights, "WTSA2YR_THYROD"] - data.loc[both_weights, "WTSA2YR_UIO"]).abs().max()
            if pd.notna(max_abs_diff) and max_abs_diff > 1e-6:
                logger.warning("THYROD and UIO WTSA2YR differ for overlapping rows; max absolute difference = %.6f", max_abs_diff)

    albumin = clean_continuous(get_numeric(data, "URXUMA")).combine_first(clean_continuous(get_numeric(data, "URXUMS")))
    urine_creatinine = clean_continuous(get_numeric(data, "URXUCR"))
    data["URINE_ALBUMIN_UG_ML"] = albumin
    data["URINE_CREATININE_MG_DL"] = urine_creatinine

    computed_uacr = pd.Series(np.nan, index=data.index, dtype="float64")
    valid_uacr = albumin.notna() & urine_creatinine.gt(0)
    computed_uacr.loc[valid_uacr] = 100 * albumin.loc[valid_uacr] / urine_creatinine.loc[valid_uacr]
    urdact = clean_continuous(get_numeric(data, "URDACT"))
    data["UACR"] = urdact.combine_first(computed_uacr)
    data["UACR_MG_G"] = data["UACR"]

    if urdact.notna().any() and computed_uacr.notna().any():
        diff = (urdact - computed_uacr).abs()
        logger.info("URDACT cross-check: median absolute difference versus computed UACR = %.6f", diff.median(skipna=True))
    else:
        logger.info("URDACT unavailable or empty; UACR derived as 100 * urine albumin / urine creatinine.")

    nonpositive_uacr = int(data["UACR"].notna().sum() - data["UACR"].gt(0).sum())
    if nonpositive_uacr > 0:
        logger.warning("Detected %s nonpositive UACR values; setting them to missing before log/quartiles.", nonpositive_uacr)
        data.loc[data["UACR"] <= 0, ["UACR", "UACR_MG_G"]] = np.nan

    data["LOG_UACR"] = np.log(data["UACR"])
    bad_log = int(np.isinf(data["LOG_UACR"]).sum() + np.isnan(data.loc[data["UACR"].notna(), "LOG_UACR"]).sum())
    if bad_log > 0:
        logger.warning("Detected %s Inf/NaN LOG_UACR values after UACR filtering.", bad_log)

    data["TSH"] = clean_continuous(get_numeric(data, "LBXTSH1"))
    data["FT3"] = clean_continuous(get_numeric(data, "LBXT3F"))
    data["FT4"] = clean_continuous(get_numeric(data, "LBXT4F"))
    data["TT3"] = clean_continuous(get_numeric(data, "LBXTT3"))
    data["TT4"] = clean_continuous(get_numeric(data, "LBXTT4"))
    data["TG"] = clean_continuous(get_numeric(data, "LBXTGN"))
    data["TGAB"] = clean_continuous(get_numeric(data, "LBXATG"))
    data["TPOAB"] = clean_continuous(get_numeric(data, "LBXTPO"))

    return data


def add_flow_row(rows: list[dict[str, object]], step: str, before: int, after: int, note: str = "") -> None:
    rows.append({"step": step, "n_before": before, "n_excluded": before - after, "n_after": after, "note": note})


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


def apply_exclusions(data: pd.DataFrame, logger: logging.Logger) -> tuple[pd.DataFrame, pd.DataFrame, dict[str, int], pd.DataFrame]:
    rows: list[dict[str, object]] = []
    milestones: dict[str, int] = {"raw": len(data)}
    add_flow_row(rows, "Merged NHANES 2007-2012 records", len(data), len(data), "Before analytic exclusions")

    data = apply_keep(data, rows, "Age >= 18 years", data["AGE"] >= 18)
    milestones["age_eligible"] = len(data)

    data = apply_keep(data, rows, "Exclude pregnant participants", data["PREGNANT_FLAG"] != 1)
    milestones["nonpregnant_adults"] = len(data)

    data = apply_keep(data, rows, "Valid UACR > 0", data["UACR"].notna() & data["UACR"].gt(0))
    data = apply_keep(
        data,
        rows,
        "Nonmissing core thyroid indicators",
        data[CORE_THYROID_COLUMNS].notna().all(axis=1),
        "Core indicators for discovery-validation comparability: " + ", ".join(CORE_THYROID_COLUMNS),
    )
    milestones["uacr_and_thyroid"] = len(data)

    if data["RXQ_AVAILABLE"].fillna(0).sum() > 0:
        data = apply_keep(data, rows, "Exclude thyroid medication users", data["THYROID_MED_USE"].fillna(0) != 1)
    else:
        add_flow_row(
            rows,
            "Thyroid medication exclusion unavailable",
            len(data),
            len(data),
            "RXQ_RX files were not available; no medication users removed.",
        )

    pre_key_covariate_pool = data.copy()
    data = apply_keep(
        data,
        rows,
        "Nonmissing key covariates",
        data[KEY_COVARIATES].notna().all(axis=1),
        ", ".join(KEY_COVARIATES),
    )
    milestones["final"] = len(data)
    return data, pd.DataFrame(rows), milestones, pre_key_covariate_pool


def add_uacr_categories(final: pd.DataFrame, logger: logging.Logger) -> pd.DataFrame:
    data = final.copy()
    if data.empty:
        data["UACR_QUARTILE"] = pd.Series(dtype="object")
        data["UACR_QUARTILE_UNWEIGHTED"] = pd.Series(dtype="object")
        data["UACR_QUARTILE_WEIGHTED"] = pd.Series(dtype="object")
        data["UACR_CLINICAL_CATEGORY"] = pd.Series(dtype="object")
        return data

    try:
        data["UACR_QUARTILE_UNWEIGHTED"] = pd.qcut(data["UACR"], 4, labels=["Q1", "Q2", "Q3", "Q4"]).astype("object")
    except ValueError as exc:
        logger.warning("Unweighted UACR quartiles could not be created with qcut: %s", exc)
        ranks = data["UACR"].rank(method="first")
        data["UACR_QUARTILE_UNWEIGHTED"] = pd.qcut(ranks, 4, labels=["Q1", "Q2", "Q3", "Q4"]).astype("object")

    weighted_breaks = weighted_quantile(data["UACR"], data["ANALYTIC_WT6YR"], [0, 0.25, 0.50, 0.75, 1.0])
    weighted_breaks[0] = min(weighted_breaks[0], data["UACR"].min())
    weighted_breaks[-1] = max(weighted_breaks[-1], data["UACR"].max())
    data["UACR_QUARTILE_WEIGHTED"] = assign_quartiles(data["UACR"], weighted_breaks, ["Q1", "Q2", "Q3", "Q4"])
    if data["UACR_QUARTILE_WEIGHTED"].isna().all():
        logger.warning("Weighted UACR quartiles unavailable due to missing/duplicate weighted breaks.")

    data["UACR_QUARTILE"] = data["UACR_QUARTILE_UNWEIGHTED"]
    data["UACR_CLINICAL_CATEGORY"] = pd.cut(
        data["UACR"],
        bins=[-np.inf, 30, 300, np.inf],
        labels=["<30", "30-300", ">=300"],
        right=False,
    ).astype("object")
    return data


def write_missingness_table(derived: pd.DataFrame, final: pd.DataFrame, root: Path, logger: logging.Logger) -> None:
    path = root / "outputs" / "tables" / "discovery_variable_missingness.csv"
    variables = list(dict.fromkeys(REQUIRED_USER_COLUMNS + COMPATIBILITY_COLUMNS_FOR_03 + QC_COLUMNS))
    rows = []
    for variable in variables:
        pre_missing = int(derived[variable].isna().sum()) if variable in derived.columns else len(derived)
        final_missing = int(final[variable].isna().sum()) if variable in final.columns else len(final)
        rows.append(
            {
                "variable": variable,
                "pre_exclusion_missing_n": pre_missing,
                "pre_exclusion_missing_pct": pre_missing / len(derived) if len(derived) else np.nan,
                "final_missing_n": final_missing,
                "final_missing_pct": final_missing / len(final) if len(final) else np.nan,
            }
        )
    pd.DataFrame(rows).to_csv(path, index=False)
    logger.info("Wrote variable missingness table to %s", path)


def write_key_covariate_missingness(pre_key_covariate_pool: pd.DataFrame, root: Path, logger: logging.Logger) -> None:
    path = root / "outputs" / "tables" / "discovery_key_covariate_missingness_before_exclusion.csv"
    rows = []
    n = len(pre_key_covariate_pool)
    for variable in KEY_COVARIATES:
        missing = int(pre_key_covariate_pool[variable].isna().sum()) if variable in pre_key_covariate_pool.columns else n
        rows.append(
            {
                "variable": variable,
                "missing_before_key_covariate_exclusion": missing,
                "missing_pct": missing / n if n else np.nan,
            }
        )
    out = pd.DataFrame(rows).sort_values("missing_before_key_covariate_exclusion", ascending=False)
    out.to_csv(path, index=False)
    logger.info("Wrote key covariate missingness diagnostic to %s", path)
    for row in out.head(6).itertuples(index=False):
        logger.info(
            "Key covariate missing before final covariate exclusion: %s missing %s/%s (%.1f%%)",
            row.variable,
            row.missing_before_key_covariate_exclusion,
            n,
            row.missing_pct * 100 if pd.notna(row.missing_pct) else float("nan"),
        )


def write_weight_source_by_cycle(derived: pd.DataFrame, root: Path, logger: logging.Logger) -> None:
    path = root / "outputs" / "tables" / "discovery_weight_source_by_cycle.csv"
    rows = []
    for cycle in CYCLES.values():
        subset = derived.loc[derived["CYCLE"] == cycle].copy()
        has_uacr_thyroid = subset["UACR"].notna() & subset["UACR"].gt(0) & subset[CORE_THYROID_COLUMNS].notna().all(axis=1)
        analytic_positive = subset["ANALYTIC_WT6YR"].notna() & subset["ANALYTIC_WT6YR"].gt(0)
        wtmec_source = subset["WEIGHT_SOURCE"].eq("WTMEC2YR_2007_2008")
        wtsa_source = subset["WEIGHT_SOURCE"].eq("WTSA2YR_2009_2012")
        rows.append(
            {
                "cycle": cycle,
                "raw_n": int(len(subset)),
                "uacr_core_thyroid_n": int(has_uacr_thyroid.sum()),
                "analytic_wt6yr_positive_n": int(analytic_positive.sum()),
                "wtmec2yr_source_n": int(wtmec_source.sum()),
                "wtsa2yr_source_n": int(wtsa_source.sum()),
                "strict_wtsa6yr_positive_n": int((subset["STRICT_WTSA6YR"].notna() & subset["STRICT_WTSA6YR"].gt(0)).sum()),
            }
        )
    out = pd.DataFrame(rows)
    out.to_csv(path, index=False)
    logger.info("Wrote weight source by cycle table to %s", path)
    for row in out.itertuples(index=False):
        logger.info(
            "Cycle %s: raw n=%s; UACR+core thyroid n=%s; ANALYTIC_WT6YR positive n=%s; WTMEC2YR source n=%s; WTSA2YR source n=%s",
            row.cycle,
            row.raw_n,
            row.uacr_core_thyroid_n,
            row.analytic_wt6yr_positive_n,
            row.wtmec2yr_source_n,
            row.wtsa2yr_source_n,
        )
    logger.info("Total using WTMEC2YR source: %s", int(out["wtmec2yr_source_n"].sum()))
    logger.info("Total using WTSA2YR source: %s", int(out["wtsa2yr_source_n"].sum()))


def write_uacr_quartile_counts(final: pd.DataFrame, root: Path, logger: logging.Logger) -> None:
    path = root / "outputs" / "tables" / "discovery_uacr_quartile_counts.csv"
    rows = []
    for variable in ["UACR_QUARTILE_UNWEIGHTED", "UACR_QUARTILE_WEIGHTED"]:
        if variable not in final.columns or final.empty:
            continue
        grouped = (
            final.groupby(variable, observed=False)
            .agg(n=("UACR", "size"), weighted_n=("ANALYTIC_WT6YR", "sum"), uacr_min=("UACR", "min"), uacr_max=("UACR", "max"))
            .reset_index()
            .rename(columns={variable: "quartile"})
        )
        grouped.insert(0, "quartile_type", variable)
        rows.append(grouped)

    if rows:
        out = pd.concat(rows, ignore_index=True)
        out["proportion"] = out.groupby("quartile_type")["n"].transform(lambda x: x / x.sum())
    else:
        out = pd.DataFrame(columns=["quartile_type", "quartile", "n", "weighted_n", "proportion", "uacr_min", "uacr_max"])
    out.to_csv(path, index=False)
    logger.info("Wrote UACR quartile counts to %s", path)

    unweighted = out.loc[out["quartile_type"] == "UACR_QUARTILE_UNWEIGHTED", "n"].tolist()
    if len(unweighted) == 4 and min(unweighted) >= 0.80 * np.mean(unweighted):
        logger.info("Unweighted UACR quartile counts look reasonable: %s", unweighted)
    elif unweighted:
        logger.warning("Unweighted UACR quartile counts may be imbalanced: %s", unweighted)


def run_qc(final: pd.DataFrame, logger: logging.Logger) -> None:
    if final.empty:
        logger.warning("Final cohort is empty; QC checks skipped.")
        return

    if (final["UACR"] <= 0).any():
        logger.warning("Final cohort still contains UACR <= 0 values.")

    bad_log = int(np.isinf(final["LOG_UACR"]).sum() + final["LOG_UACR"].isna().sum())
    if bad_log > 0:
        logger.warning("Final cohort contains %s missing/Inf LOG_UACR values.", bad_log)

    age65_prop = float((final["AGE"] >= 65).mean())
    if age65_prop < 0.08 or age65_prop > 0.35:
        logger.warning("Age >=65 proportion looks unusual: %.3f", age65_prop)
    else:
        logger.info("Age >=65 proportion: %.3f", age65_prop)

    if "ANALYTIC_WT6YR" not in final.columns or final["ANALYTIC_WT6YR"].isna().all() or (final["ANALYTIC_WT6YR"].fillna(0) <= 0).all():
        logger.warning("ANALYTIC_WT6YR is all missing or zero.")
    else:
        logger.info("ANALYTIC_WT6YR nonmissing positive n: %s", int((final["ANALYTIC_WT6YR"] > 0).sum()))

    for design_var in ["SDMVPSU", "SDMVSTRA"]:
        if design_var not in final.columns or final[design_var].isna().all():
            logger.warning("%s is missing or all NA.", design_var)
        else:
            logger.info("%s available with %s unique values.", design_var, final[design_var].nunique(dropna=True))


def log_sample_summary(milestones: dict[str, int], final: pd.DataFrame, flow: pd.DataFrame, logger: logging.Logger) -> None:
    logger.info("Original merged sample size: %s", milestones.get("raw", 0))
    logger.info("Sample size after age >=18: %s", milestones.get("age_eligible", 0))
    logger.info("Nonpregnant adult sample size: %s", milestones.get("nonpregnant_adults", 0))
    logger.info("Sample size with valid UACR and core thyroid data: %s", milestones.get("uacr_and_thyroid", 0))
    logger.info("Final sample size after thyroid medication and covariate exclusions: %s", milestones.get("final", 0))

    final_n = len(final)
    diff = final_n - EXPECTED_FINAL_N
    pct_diff = diff / EXPECTED_FINAL_N if EXPECTED_FINAL_N else np.nan
    if final_n == EXPECTED_FINAL_N:
        logger.info("Final n equals the current flowchart target n=%s.", EXPECTED_FINAL_N)
    else:
        logger.warning("Final n=%s differs from current flowchart target n=%s by %+d (%.1f%%).", final_n, EXPECTED_FINAL_N, diff, pct_diff * 100)
        logger.warning("Difference source by exclusion flow:")
        for row in flow.itertuples(index=False):
            logger.warning("  %s: excluded %s; n_after %s; note=%s", row.step, row.n_excluded, row.n_after, row.note)
        logger.warning(
            "Interpretation: differences usually arise from unavailable raw components, thyroid medication exclusion, "
            "requiring UIC/eGFR/lifestyle covariates, or defining core thyroid indicators as %s.",
            ", ".join(CORE_THYROID_COLUMNS),
        )

    close = abs(pct_diff) <= 0.05 if not pd.isna(pct_diff) else False
    logger.info("Final n close to 6357 within 5%%: %s", close)


def write_no_data_outputs(root: Path, message: str, logger: logging.Logger) -> None:
    output_path = root / "data" / "processed" / "discovery_nhanes_2007_2012.csv"
    flow_path = root / "outputs" / "tables" / "discovery_exclusion_flow.csv"
    missing_path = root / "outputs" / "tables" / "discovery_variable_missingness.csv"
    quartile_path = root / "outputs" / "tables" / "discovery_uacr_quartile_counts.csv"
    weight_source_path = root / "outputs" / "tables" / "discovery_weight_source_by_cycle.csv"

    pd.DataFrame(columns=OUTPUT_COLUMNS).to_csv(output_path, index=False)
    pd.DataFrame(
        [{"step": "No source data", "n_before": 0, "n_excluded": 0, "n_after": 0, "note": message}]
    ).to_csv(flow_path, index=False)
    pd.DataFrame(columns=["variable", "pre_exclusion_missing_n", "pre_exclusion_missing_pct", "final_missing_n", "final_missing_pct"]).to_csv(missing_path, index=False)
    pd.DataFrame(columns=["quartile_type", "quartile", "n", "weighted_n", "proportion", "uacr_min", "uacr_max"]).to_csv(quartile_path, index=False)
    pd.DataFrame(
        columns=[
            "cycle",
            "raw_n",
            "uacr_core_thyroid_n",
            "analytic_wt6yr_positive_n",
            "wtmec2yr_source_n",
            "wtsa2yr_source_n",
            "strict_wtsa6yr_positive_n",
        ]
    ).to_csv(weight_source_path, index=False)
    logger.warning(message)


def main() -> None:
    root = find_project_root(Path(__file__))
    ensure_output_dirs(root)
    logger = setup_logger(root)
    raw_dir = root / "data" / "raw" / "nhanes_2007_2012"

    logger.info("Project root: %s", root)
    logger.info("Raw XPT directory: %s", raw_dir)
    xpt_files = list_xpt_files(raw_dir)
    logger.info("Detected %s XPT files under raw directory", len(xpt_files))
    if not xpt_files:
        write_no_data_outputs(
            root,
            "No XPT files found. Place NHANES 2007-2012 XPT files under data/raw/nhanes_2007_2012/ and rerun.",
            logger,
        )
        return

    cycle_frames = []
    for suffix, cycle_name in CYCLES.items():
        cycle_frame = load_cycle(raw_dir, suffix, cycle_name, logger)
        if cycle_frame is not None:
            cycle_frames.append(cycle_frame)

    if not cycle_frames:
        write_no_data_outputs(root, "No usable cycle data were loaded from XPT files.", logger)
        return

    merged = pd.concat(cycle_frames, ignore_index=True, sort=False)
    logger.info("Merged all cycles: %s rows x %s columns", merged.shape[0], merged.shape[1])

    derived = derive_analysis_variables(merged, logger)
    final, flow, milestones, pre_key_covariate_pool = apply_exclusions(derived, logger)
    final = add_uacr_categories(final, logger)

    for column in OUTPUT_COLUMNS:
        if column not in final.columns:
            final[column] = np.nan

    output_path = root / "data" / "processed" / "discovery_nhanes_2007_2012.csv"
    flow_path = root / "outputs" / "tables" / "discovery_exclusion_flow.csv"
    final[OUTPUT_COLUMNS].to_csv(output_path, index=False)
    flow.to_csv(flow_path, index=False)

    write_missingness_table(derived, final, root, logger)
    write_key_covariate_missingness(pre_key_covariate_pool, root, logger)
    write_weight_source_by_cycle(derived, root, logger)
    write_uacr_quartile_counts(final, root, logger)
    run_qc(final, logger)
    log_sample_summary(milestones, final, flow, logger)

    logger.info("Wrote discovery cohort to %s", output_path)
    logger.info("Wrote exclusion flow to %s", flow_path)


if __name__ == "__main__":
    main()
