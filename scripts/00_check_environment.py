from __future__ import annotations

import importlib.util
import platform
import subprocess
import sys
from pathlib import Path

from path_utils import ensure_project_dirs, find_project_root, load_project_configs, setup_logging


REQUIRED_PYTHON_PACKAGES = ["pandas", "numpy", "requests", "yaml", "tqdm"]
OPTIONAL_PYTHON_PACKAGES = ["pyreadstat"]


def has_package(name: str) -> bool:
    return importlib.util.find_spec(name) is not None


def rscript_version() -> str:
    try:
        result = subprocess.run(["Rscript", "--version"], capture_output=True, text=True, check=False)
    except FileNotFoundError:
        return "Rscript not found on PATH"
    return (result.stderr or result.stdout).strip() or "Rscript found"


def main() -> None:
    root = find_project_root(Path(__file__))
    configs = load_project_configs(root)
    ensure_project_dirs(root, configs["analysis"])
    logger = setup_logging(root, "00_check_environment")

    logger.info("Project root: %s", root)
    logger.info("Python: %s", sys.version.replace("\n", " "))
    logger.info("Platform: %s", platform.platform())
    logger.info("R: %s", rscript_version())

    missing = []
    for package in REQUIRED_PYTHON_PACKAGES:
        ok = has_package(package)
        logger.info("Python package %-10s : %s", package, "OK" if ok else "MISSING")
        if not ok:
            missing.append(package)

    for package in OPTIONAL_PYTHON_PACKAGES:
        ok = has_package(package)
        logger.info("Optional package %-9s : %s", package, "OK" if ok else "MISSING")

    if missing:
        logger.warning("Missing Python packages: %s", ", ".join(missing))
        logger.warning("Install with: python -m pip install -r requirements.txt")
    else:
        logger.info("Python dependency check completed.")


if __name__ == "__main__":
    main()
