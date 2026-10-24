#!/usr/bin/env python3
"""Prepare an allowlisted, source-only GitHub upload folder without publishing."""
import hashlib
import argparse
import json
from pathlib import Path
import shutil
import zipfile
from preflight import audit

ROOT = Path(__file__).resolve().parent.parent
VERSION = "0.3"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="Prepare a separate source folder while preserving an earlier upload copy.")
    args = parser.parse_args()
    destination = args.output.resolve() if args.output else ROOT / "dist" / f"RDataCraft-{VERSION}-GitHub"
    if destination.exists():
        raise SystemExit("Choose a clean GitHub destination; existing files are not overwritten.")
    for folder in ["R", "www", "config", "desktop", "scripts", "tests", "examples", "licenses", ".github"]:
        if any(p.is_symlink() for p in (ROOT/folder).rglob("*")):
            raise SystemExit("Review and remove symbolic links from public source directories before preparing an upload.")
    destination.mkdir(parents=True)
    for name in ["app.R", "README.md", "CHANGELOG.md", "LICENSE", "PLATFORM_SUPPORT.md",
                 "WORKFLOWS.md", "RELEASE.md", "dependencies.csv", "dependencies.lock.json", "source-manifest.json",
                 "Launch RDataCraft.command", "Launch RDataCraft.cmd", "Launch RDataCraft.ps1",
                 "Launch RDataCraft portable.command", "Validate RDataCraft.cmd"]:
        shutil.copy2(ROOT / name, destination / name)
    for name in ["R", "www", "config", "desktop", "scripts", "tests", "examples", "licenses", ".github"]:
        shutil.copytree(ROOT / name, destination / name, symlinks=True,
                        ignore=shutil.ignore_patterns(".DS_Store", "__pycache__", "*.pyc", "cache"))
    (destination / ".gitignore").write_text(
        ".DS_Store\n__pycache__/\n*.pyc\n.Rhistory\n.RData\nRplots.pdf\n"
        "/runtime*/\n/downloads/\n/dist/\n/artifacts/\n/Codex handoff/\n"
        "*.app/\n*.dmg\n*.exe\n*.zip\n.env\n.env.*\n"
        "*.rdatacraft\n!examples/*.rdatacraft\n*.prism\n*.pzfx\n*.pzf\n!tests/fixtures/*.prism\n!tests/fixtures/*.pzfx\n")
    (destination / "GITHUB_UPLOAD.md").write_text(f"""# RDataCraft v{VERSION}: GitHub upload

Upload the contents of this folder to your repository. This is the application
source, examples, tests, build scripts and third-party notices. It excludes local
R binaries, installers, caches, private studies, personal paths and chat handoffs.
The original MIT attribution in the third-party notices must remain intact.
See `RELEASE.md` for the app description, GitHub Desktop steps, signing setup and
remaining release gates.

## Installers

Create a draft GitHub release tagged `v{VERSION}` and attach these files from the
original project's `dist/` folder as **release assets**, rather than source commits:

- `RDataCraft-{VERSION}-macos-x86_64.dmg`
- `RDataCraft-{VERSION}-macos-arm64.dmg`
- `RDataCraft-{VERSION}-windows-x64-setup.exe`
- `RDataCraft-{VERSION}-SHA256SUMS.txt`
- `RDataCraft-{VERSION}-validation.json`

The installers are larger than GitHub's ordinary file-upload/commit limits.
They contain bundled R and packages. Current packages are development builds:
Mac apps are ad-hoc signed, not notarized, and Apple Silicon/Windows execution
requires checks on those platforms. Complete the corresponding-source and native
library audit in `licenses/REDISTRIBUTION.md` before publicly distributing binaries.
No repository or release has been created by this preparation script.

## Build and check

On Mac, use `python3 scripts/bootstrap.py` to prepare a matching local R runtime,
then `python3 scripts/test.py` and `python3 scripts/build_desktop.py --zip`.
On Windows, install R, run `Rscript --vanilla scripts/install.R`, then
`python scripts/test.py` and `python scripts/package_portable.py`.
Python and Node are build/test tools; the installed application uses bundled R.
See `PLATFORM_SUPPORT.md` for architecture flags, packaging and validation limits.
`source-manifest.json` records dependency source provenance; run
`scripts/fetch_sources.py` to collect missing matching archives for a release.
""")
    files = [p for p in destination.rglob("*") if p.is_file()]
    privacy = audit(destination)
    if privacy["findings"]:
        raise SystemExit("Source preflight failed:\n" + "\n".join(privacy["findings"]))
    # Keep the upload free of runtime binaries and oversized files by construction.
    if any(p.stat().st_size > 90 * 1024**2 or p.suffix.lower() in
           [".pzf", ".exe", ".dll", ".so", ".dmg"] for p in files):
        raise SystemExit("Unexpected binary or oversized file in the source upload.")
    assert all(p.relative_to(destination).parts[:2] == ("tests", "fixtures")
               for p in files if p.suffix.lower() == ".prism")
    manifest = {str(p.relative_to(destination)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in files}
    (ROOT / "artifacts").mkdir(exist_ok=True)
    (ROOT / "artifacts" / f"github-source-audit-{VERSION}.json").write_text(
        json.dumps(dict(version=VERSION, files=manifest, published=False), indent=2) + "\n")
    # Normalize transferred owner-only permissions for other users cloning the source.
    for p in destination.rglob("*"):
        if not p.is_symlink():
            p.chmod(0o755 if p.is_dir() or p.stat().st_mode & 0o111 else 0o644)
    archive = Path(str(destination) + ".zip")
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as z:
        for p in destination.rglob("*"):
            if p.is_file():
                z.write(p, Path(destination.name) / p.relative_to(destination))
    archive.with_suffix(".zip.sha256").write_text(
        hashlib.sha256(archive.read_bytes()).hexdigest() + "  " + archive.name + "\n")
    print(f"Prepared {destination}: {len(files)} source files; nothing published.")


if __name__ == "__main__":
    main()
