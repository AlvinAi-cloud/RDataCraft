#!/usr/bin/env python3
"""Download and extract an official app-local R runtime, then install dependencies.

Run with /usr/bin/python3 scripts/bootstrap.py on macOS. Never installs system-wide.
"""
import argparse
import hashlib
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
VERSION = "4.6.1"
BUILDS = {
    "x86_64": ("big-sur-x86_64", "8d3c9e7a71dcba7602aaaf948b574e2e9d29844e"),
    "arm64": ("sonoma-arm64", "fc9f4ada15589e8e037b9bf05563d21e97181635"),
}


def main():
    if platform.system() != "Darwin" or platform.machine() not in BUILDS:
        sys.exit("This bootstrap currently supports Intel and Apple Silicon macOS. See README.md for using an existing R on other systems.")
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--arch',choices=list(BUILDS),default=platform.machine())
    parser.add_argument('--runtime-root',type=Path,default=ROOT/'runtime')
    args=parser.parse_args()
    runtime=args.runtime_root.resolve();runtime.mkdir(parents=True,exist_ok=True)
    env=dict(os.environ,RDATACRAFT_RUNTIME=str(runtime))
    os.chdir(ROOT)
    for folder in ("downloads",):
        (ROOT / folder).mkdir(parents=True, exist_ok=True)
    destination = runtime / "R.framework"
    if not destination.exists():
        arch = args.arch
        path, expected_sha1 = BUILDS[arch]
        name = f"R-{VERSION}-{arch}.pkg"
        installer = ROOT / "downloads" / name
        url = f"https://cran.r-project.org/bin/macosx/{path}/base/{name}"
        if not installer.exists():
            subprocess.run(["curl", "--fail", "--location", "--retry", "2", "--output", str(installer), url], check=True)
        digest = hashlib.sha1(installer.read_bytes()).hexdigest()
        if digest != expected_sha1:
            sys.exit("R installer checksum differs from the pinned official checksum. Remove the download and investigate before continuing.")
        signature = subprocess.run(["/usr/sbin/pkgutil", "--check-signature", str(installer)], capture_output=True, text=True)
        (ROOT / "downloads/R-signature-check.txt").write_text(signature.stdout + signature.stderr)
        if signature.returncode:
            sys.exit("Apple could not validate the R installer signature. Nothing was extracted. Check the system clock, network and downloads/R-signature-check.txt before retrying with a fresh official download.")
        expanded = ROOT / f"downloads/R-expanded-{arch}"
        if not expanded.exists():
            subprocess.run(["/usr/sbin/pkgutil", "--expand-full", str(installer), str(expanded)], check=True)
        subprocess.run(["ditto", str(expanded / "R-fw.pkg/Payload/R.framework"), str(destination)], check=True)
    binary=destination/'Resources/bin/exec/R'
    arches=subprocess.check_output(['lipo','-archs',str(binary)],text=True).strip().split()
    if args.arch not in arches:sys.exit(f'Runtime architecture mismatch: requested {args.arch}, found {arches}. Choose an empty --runtime-root.')
    subprocess.run([sys.executable, str(ROOT / "scripts/relocate_runtime.py")], check=True,env=env)
    for name in ("scripts/r.sh", "scripts/rscript.sh", "Launch RDataCraft.command"):
        file = ROOT / name
        file.chmod(file.stat().st_mode | 0o111)
    subprocess.run([str(ROOT / "scripts/rscript.sh"), "scripts/install.R"], check=True,env=env)
    print("RDataCraft is ready. Double-click Launch RDataCraft.command.")


if __name__ == "__main__":
    main()
