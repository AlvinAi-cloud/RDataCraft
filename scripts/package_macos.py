#!/usr/bin/env python3
"""Compatibility entry point for the native RDataCraft.app development bundle."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--development", action="store_true", help="Acknowledge that this bundle is a development preview.")
    args = parser.parse_args()
    if not args.development:
        parser.error("Public binaries need the native-library source audit, signing checks, and clean-machine verification in licenses/REDISTRIBUTION.md. Use --development for a local preview.")
    sources = json.loads((ROOT / "source-manifest.json").read_text())
    if sources["missing"]:
        raise SystemExit("Some matching source archives are missing.")
    subprocess.run([sys.executable, str(ROOT / "scripts/build_desktop.py"), "--zip"], check=True)
