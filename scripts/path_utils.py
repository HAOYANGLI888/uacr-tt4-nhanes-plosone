from __future__ import annotations

import logging
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

import yaml


ROOT_MARKERS = (
    Path("config") / "analysis_plan.yaml",
    Path("config") / "variables_discovery.yaml",
    Path("config") / "variables_validation_nhanes3.yaml",
)


def find_project_root(start: Path | None = None) -> Path:
    if start is None:
        start = Path(__file__).resolve()
    start = start.resolve()
    if start.is_file():
        start = start.parent

    for candidate in (start, *start.parents):
        if all((candidate / marker).exists() for marker in ROOT_MARKERS):
            return candidate
    raise FileNotFoundError("Could not find thyroid_uacr_routeB project root.")


def load_yaml(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def load_project_configs(root: Path) -> dict[str, dict[str, Any]]:
    return {
        "analysis": load_yaml(root / "config" / "analysis_plan.yaml"),
        "discovery": load_yaml(root / "config" / "variables_discovery.yaml"),
        "validation": load_yaml(root / "config" / "variables_validation_nhanes3.yaml"),
    }


def project_path(root: Path, value: str) -> Path:
    path = Path(value)
    return path if path.is_absolute() else root / path


def ensure_project_dirs(root: Path, analysis_config: dict[str, Any]) -> None:
    for value in analysis_config.get("paths", {}).values():
        project_path(root, value).mkdir(parents=True, exist_ok=True)


def setup_logging(root: Path, script_stem: str) -> logging.Logger:
    log_dir = root / "outputs" / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_file = log_dir / f"{script_stem}_{timestamp}.log"

    logger = logging.getLogger(script_stem)
    logger.setLevel(logging.INFO)
    logger.handlers.clear()
    logger.propagate = False

    formatter = logging.Formatter("%(asctime)s | %(levelname)s | %(message)s")
    file_handler = logging.FileHandler(log_file, encoding="utf-8")
    file_handler.setFormatter(formatter)
    stream_handler = logging.StreamHandler(sys.stdout)
    stream_handler.setFormatter(formatter)

    logger.addHandler(file_handler)
    logger.addHandler(stream_handler)
    logger.info("Logging to %s", log_file)
    return logger
