from __future__ import annotations

from pathlib import Path

import pandas as pd

from path_utils import ensure_project_dirs, find_project_root, load_project_configs, setup_logging


def main() -> None:
    root = find_project_root(Path(__file__))
    configs = load_project_configs(root)
    ensure_project_dirs(root, configs["analysis"])
    logger = setup_logging(root, "03_prepare_validation_nhanes3")

    validation = configs["validation"]
    raw_root = root / "data" / "raw" / "validation_nhanes3"
    report_path = root / "outputs" / "reports" / "03_prepare_validation_nhanes3_report.md"
    table_path = root / "outputs" / "tables" / "03_validation_nhanes3_file_manifest.csv"

    expected = []
    for section in ("laboratory_1a", "laboratory_2a"):
        for field in ("dat_url", "sas_url", "documentation_url"):
            url = validation["source"][section][field]
            path = raw_root / section / Path(url).name
            expected.append(
                {
                    "section": section,
                    "source_field": field,
                    "file": str(path),
                    "exists": path.exists(),
                    "source_url": url,
                }
            )

    manifest = pd.DataFrame(expected)
    manifest.to_csv(table_path, index=False)

    present = int(manifest["exists"].sum())
    total = len(manifest)
    report_path.write_text(
        "# NHANES III Validation Preparation\n\n"
        f"Status: {present}/{total} expected source files detected.\n\n"
        "This skeleton does not yet parse fixed-width NHANES III DAT files. "
        "The next step is to translate the official SAS INPUT layouts into a reproducible parser, "
        "then harmonize UACR, TSH, total T4, antimicrosomal antibody, and thyroglobulin antibody.\n\n"
        f"Manifest: `{table_path}`\n",
        encoding="utf-8",
    )

    logger.info("Wrote manifest to %s", table_path)
    logger.info("Wrote report to %s", report_path)


if __name__ == "__main__":
    main()
