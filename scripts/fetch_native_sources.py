#!/usr/bin/env python3
"""Collect the pinned native-source subset; does not certify complete binary coverage."""
import hashlib
import json
from pathlib import Path
import subprocess


def main():
    root = Path(__file__).resolve().parent.parent
    manifest = json.loads((root / "licenses/native-source-manifest.json").read_text())
    output = root / "downloads/native-sources"
    output.mkdir(parents=True, exist_ok=True)
    for entry in manifest["archives"]:
        name = entry["archive"]
        if Path(name).name != name or not entry["source"].startswith("https://mac.r-project.org/openmp/src/"):
            raise ValueError("Review unexpected native-source filename or origin before downloading.")
        target = output / name
        if not target.exists():
            partial = output / (name + ".part")
            subprocess.run(["curl", "--fail", "--silent", "--show-error", "--location", "--connect-timeout", "20",
                            "--max-time", "180", "--retry", "2", "--output", str(partial), entry["source"]], check=True)
            if hashlib.sha256(partial.read_bytes()).hexdigest() != entry["sha256"]:
                raise ValueError("Native source hash changed; retained partial file for review: " + name)
            partial.replace(target)
        if hashlib.sha256(target.read_bytes()).hexdigest() != entry["sha256"]:
            raise ValueError("Native source hash differs from the reviewed manifest: " + name)
        print("Verified pinned native source:", name, flush=True)
    print("Native coverage remains partial; see licenses/NATIVE_SOURCE_REVIEW.md.")


if __name__ == "__main__":
    main()
