from __future__ import annotations

import argparse
from pathlib import Path

import requests
from tqdm import tqdm

from path_utils import ensure_project_dirs, find_project_root, load_project_configs, setup_logging


def download_file(url: str, destination: Path, force: bool = False) -> str:
    if destination.exists() and not force:
        return "skipped"

    destination.parent.mkdir(parents=True, exist_ok=True)
    partial = destination.with_suffix(destination.suffix + ".part")
    with requests.get(url, stream=True, timeout=90) as response:
        response.raise_for_status()
        total = int(response.headers.get("content-length", 0))
        with partial.open("wb") as handle:
            progress = tqdm(total=total, unit="B", unit_scale=True, desc=destination.name)
            for chunk in response.iter_content(chunk_size=1024 * 256):
                if chunk:
                    handle.write(chunk)
                    progress.update(len(chunk))
            progress.close()
    partial.replace(destination)
    return "downloaded"


def discovery_downloads(config: dict) -> list[tuple[str, Path]]:
    base = config["source"]["base_url_template"]
    downloads = []
    for cycle in config["source"]["cycles"]:
        for component in config["source"]["components"].keys():
            suffix = cycle["suffix"]
            url = base.format(year=cycle["year"], component=component, suffix=suffix)
            destination = Path("data/raw/discovery") / cycle["cycle"] / f"{component}_{suffix}.xpt"
            downloads.append((url, destination))
    return downloads


def validation_downloads(config: dict) -> list[tuple[str, Path]]:
    downloads = []
    for key in ("laboratory_1a", "laboratory_2a"):
        source = config["source"][key]
        subdir = Path("data/raw/validation_nhanes3") / key
        for field in ("dat_url", "sas_url", "documentation_url"):
            url = source[field]
            downloads.append((url, subdir / Path(url).name))
    return downloads


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Download source files for thyroid_uacr_routeB.")
    parser.add_argument("--dry-run", action="store_true", help="Log download URLs without downloading.")
    parser.add_argument("--force", action="store_true", help="Overwrite existing files.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    root = find_project_root(Path(__file__))
    configs = load_project_configs(root)
    ensure_project_dirs(root, configs["analysis"])
    logger = setup_logging(root, "01_download_source_files")

    downloads = discovery_downloads(configs["discovery"]) + validation_downloads(configs["validation"])
    logger.info("Files in download manifest: %s", len(downloads))

    for url, relative_destination in downloads:
        destination = root / relative_destination
        if args.dry_run:
            logger.info("DRY RUN | %s -> %s", url, destination)
            continue
        status = download_file(url, destination, force=args.force)
        logger.info("%s | %s", status.upper(), destination)

    logger.info("Download step completed.")


if __name__ == "__main__":
    main()
