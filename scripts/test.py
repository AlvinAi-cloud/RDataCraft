#!/usr/bin/env python3
"""Run the restored regression suite and save a machine-readable validation report."""
import json
import os
from pathlib import Path
import subprocess
import shutil
import sys
import argparse

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--require-node", action="store_true", help="Fail rather than skip JavaScript checks when Node is missing.")
parser.add_argument("--source-tools-only", action="store_true", help="Run JS/Python checks; the installer job must run the full R suite separately.")
args = parser.parse_args()
node = shutil.which("node")
if args.require_node and not node:
    raise SystemExit("Node.js is required for the complete validation suite.")

root = Path(__file__).resolve().parent.parent
runner = root / "scripts/rscript.sh"
def r_command(script):
    if os.name == "nt":
        bundled=next((p for p in (root/'runtime/R/bin/x64/Rscript.exe',root/'runtime/R/bin/Rscript.exe') if p.is_file()),None)
        exe=os.environ.get('RDATACRAFT_RSCRIPT') or (str(bundled) if bundled else None) or shutil.which('Rscript.exe') or shutil.which('Rscript')
        if not exe:raise SystemExit('Install R and add Rscript to PATH before running Windows validation.')
        return [exe,'--vanilla',script]
    return [str(runner),script]
if os.name == 'nt':os.environ['R_LIBS_USER']=str(root/'runtime/library')
(root / "artifacts").mkdir(exist_ok=True)
if not args.source_tools_only:
    subprocess.run([sys.executable, str(root / "tests/make_prism_fixtures.py")], cwd=root, check=True)
    subprocess.run(r_command("tests/setup.R"), cwd=root, check=True)
results = []
for name in ([] if args.source_tools_only else json.loads((root / 'config/validation-suites.json').read_text(encoding='utf-8'))):
    log = root / "artifacts" / f"v0.33-{name}.log"
    with log.open("w") as output:
        run = subprocess.run(r_command(f"tests/{name}.R"), cwd=root, stdout=output, stderr=subprocess.STDOUT)
    output = log.read_text(encoding='utf-8', errors='replace')
    results.append(dict(test=name, exit_code=run.returncode, checks=output.count("PASS:"), log=str(log)))
    print(f"{name}: {'PASS' if run.returncode == 0 else 'FAIL'} ({results[-1]['checks']} checks)", flush=True)
    if run.returncode:
        print(output[-4000:], flush=True)
if node:
    for name in ["assistant_js", "windows_js"]:
        log = root / f"artifacts/v0.33-{name}.log"
        with log.open("w") as output:
            run = subprocess.run([node, f"tests/{name}.cjs"], cwd=root, stdout=output, stderr=subprocess.STDOUT)
        results.append(dict(test=name, exit_code=run.returncode, checks=log.read_text(encoding='utf-8', errors='replace').count("PASS:"), log=str(log)))
        print(f"{name}: {'PASS' if run.returncode == 0 else 'FAIL'} ({results[-1]['checks']} checks)", flush=True)
else:
    print("assistant_js: not run (Node.js not available)", flush=True)
log = root / "artifacts/v0.33-release_tools.log"
with log.open("w") as output:
    run = subprocess.run([sys.executable, "tests/release_tools.py"], cwd=root, stdout=output, stderr=subprocess.STDOUT)
results.append(dict(test="release_tools", exit_code=run.returncode, checks=log.read_text(encoding='utf-8', errors='replace').count("PASS:"), log=str(log)))
print(f"release_tools: {'PASS' if run.returncode == 0 else 'FAIL'} ({results[-1]['checks']} checks)", flush=True)
if run.returncode:
    print(log.read_text(encoding='utf-8', errors='replace')[-4000:], flush=True)
report = dict(version="0.33", scope='source tools; full R validation required in installed bundle' if args.source_tools_only else 'full source suite', status="passed" if all(r["exit_code"] == 0 for r in results) else "failed",
              javascript_executed=bool(node), skipped=[] if node else ["assistant_js", "windows_js"], tests=results)
(root / ("artifacts/validation-source-tools-0.33.json" if args.source_tools_only else "artifacts/validation-0.33.json")).write_text(json.dumps(report, indent=2) + "\n")
sys.exit(report["status"] != "passed")
