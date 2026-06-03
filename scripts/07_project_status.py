from __future__ import annotations

from pathlib import Path

from path_utils import ensure_project_dirs, find_project_root, load_project_configs, setup_logging


def exists_line(root: Path, relative: str) -> str:
    path = root / relative
    status = "present" if path.exists() else "missing"
    return f"- `{relative}`: {status}"


def main() -> None:
    root = find_project_root(Path(__file__))
    configs = load_project_configs(root)
    ensure_project_dirs(root, configs["analysis"])
    logger = setup_logging(root, "07_project_status")

    checks = [
        "config/variables_discovery.yaml",
        "config/variables_validation_nhanes3.yaml",
        "config/analysis_plan.yaml",
        "data/processed/discovery_nhanes_2007_2012.csv",
        "data/processed/validation_nhanes3_harmonized.csv",
        "data/external_gwas/exposure_sumstats_template.csv",
        "data/external_gwas/outcome_sumstats_template.csv",
    ]

    report_path = root / "outputs" / "reports" / "07_project_status.md"
    report_path.write_text(
        "# Project Status\n\n"
        "Skeleton status for `thyroid_uacr_routeB`.\n\n"
        + "\n".join(exists_line(root, item) for item in checks)
        + "\n",
        encoding="utf-8",
    )
    logger.info("Wrote %s", report_path)


if __name__ == "__main__":
    main()
