#!/usr/bin/env python3
"""Check a source upload for private files, credentials, binaries and broken local links."""
import argparse
import hashlib
import json
from pathlib import Path
import re
from urllib.parse import unquote
import zipfile

PATTERNS = {
    "private key": rb"-----BEGIN (?:RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----",
    "GitHub token": rb"gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}",
    "API key": rb"sk-(?:proj-)?[A-Za-z0-9_-]{40,}",
    "personal Mac path": rb"/Users/(?!username(?:/|\b)|yourname(?:/|\b)|example(?:/|\b)|Shared(?:/|\b))[A-Za-z0-9_.-]+/",
    "personal Windows path": rb"[A-Za-z]:[\\/]+Users[\\/]+[A-Za-z0-9_. -]+[\\/]",
}
EXAMPLES = {
    "Advanced R analysis guide.html", "Advanced R count example.csv",
    "Advanced R teaching example.rdatacraft", "Figure studio.rdatacraft",
    "PCA analysis guide.html", "PCA teaching data.csv", "PCA teaching example.rdatacraft",
    "Prism workflow improvements.rdatacraft", "RDataCraft examples.rdatacraft",
    "Regression model gallery.rdatacraft", "XY replicates example.rdatacraft",
    "dose-response.csv", "treatment.csv", "xy.csv", "RDataCraft help.html",
    "XY curve fitting review.rdatacraft",
}


def audit(source):
    source = source.resolve()
    findings, hashes = [], {}
    for file in sorted(source.rglob("*")):
        relative = file.relative_to(source)
        label = relative.as_posix()
        if file.is_symlink():
            findings.append(f"Symbolic link: {label}")
            continue
        if file.is_dir():
            if file.name in {".git", "runtime", "dist", "artifacts", "downloads", "Codex handoff"}:
                findings.append(f"Non-source directory: {label}")
            continue
        data = file.read_bytes()
        hashes[label] = hashlib.sha256(data).hexdigest()
        if file.name.startswith(".env") or file.name in {".Rhistory", ".RData", ".DS_Store"}:
            findings.append(f"Private/cache file: {label}")
        if file.suffix.lower() in {".exe", ".dll", ".so", ".dylib", ".dmg", ".pzf", ".rds", ".rdata", ".zip", ".pkg"} or len(data) > 90 * 1024**2:
            findings.append(f"Binary/oversized file: {label}")
        if relative.parts[0] == "examples" and relative.name not in EXAMPLES:
            findings.append(f"Unreviewed example: {label}")
        if file.suffix.lower() == ".prism" and relative.parts[:2] != ("tests", "fixtures"):
            findings.append(f"Non-fixture Prism study: {label}")
        if file.suffix.lower() == ".rdatacraft":
            if relative.parts[0] != "examples" or relative.name not in EXAMPLES:
                findings.append(f"Unreviewed study: {label}")
            if json.loads(data).get("prism_sources"):
                findings.append(f"Original-file attachment in public example: {label}")
        contents = [data]
        if file.suffix.lower() == ".prism" and zipfile.is_zipfile(file):
            with zipfile.ZipFile(file) as archive:
                if sum(x.file_size for x in archive.infolist()) > 10_000_000:
                    findings.append(f"Oversized fixture archive: {label}")
                else:
                    contents += [archive.read(x) for x in archive.infolist() if not x.is_dir()]
        for name, pattern in PATTERNS.items():
            if any(re.search(pattern, text) for text in contents):
                findings.append(f"Possible {name}: {label}")
        if file.suffix.lower() == ".md":
            for target in re.findall(r"\[[^\]]+\]\(([^)\s]+)\)", data.decode("utf-8")):
                if ":" in target or target.startswith(("#", "/")):
                    continue
                target = unquote(target.split("#", 1)[0])
                if target and not (file.parent / target).exists():
                    findings.append(f"Broken local link: {label} → {target}")
    for required in ["app.R", "README.md", "LICENSE", ".gitignore", "R/help.R",
                     "R/power.R", "R/power_pilot.R", "www/dropdowns.js", "tests/power_pilot.R",
                     "scripts/test.py", ".github/workflows/platform-builds.yml"]:
        if not (source / required).is_file():
            findings.append(f"Required source missing: {required}")
    return dict(status="passed" if not findings else "failed", files=len(hashes), findings=findings,
                sha256=hashes, scope="source only; no binary redistribution certification", published=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    if not args.source.is_dir():
        raise SystemExit("Source folder does not exist.")
    result = audit(args.source)
    if args.report:
        args.report.write_text(json.dumps(result, indent=2) + "\n")
    print(f"Source preflight: {result['status']} ({result['files']} files)")
    for finding in result["findings"]:
        print(finding)
    raise SystemExit(result["status"] != "passed")


if __name__ == "__main__":
    main()
