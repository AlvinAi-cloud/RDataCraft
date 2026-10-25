#!/usr/bin/env python3
"""Exercise the native app from a read-only installer; never touches user studies."""
import argparse
import json
from pathlib import Path
import plistlib
import subprocess
import time


def main():
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dmg", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--advisory-paste", action="store_true", help="Run the extended paste/layout UI checks as advisory diagnostics, not a release gate.")
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists():
        parser.error("Choose a new test-output directory.")
    output.mkdir(parents=True)
    mount = output / "mounted"
    mount.mkdir()
    subprocess.run(["hdiutil", "verify", str(args.dmg.resolve())], check=True)
    attached = False
    reports = {}
    advisory = {"paste": {"status": "not_run", "required": False}}
    try:
        subprocess.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", str(mount), str(args.dmg.resolve())], check=True)
        attached = True
        apps = list(mount.glob("*.app"))
        if len(apps) != 1:
            raise ValueError("Expected one app in the installer.")
        app = apps[0]
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        expected = json.loads((root / "config/release.json").read_text())["version"]
        if info.get("CFBundleShortVersionString") != expected:
            raise ValueError("Installer version differs from the source checkout.")
        modes = ("studio", "multiwindow", "graph") + (("paste",) if args.advisory_paste else ())
        for mode in modes:
            directory = output / mode
            log = output / (mode + ".log")
            with log.open("w") as stream:
                process = subprocess.Popen([str(app / "Contents/MacOS/RDataCraft"), f"--{mode}-test={directory}"],
                                           stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
                start = time.monotonic()
                while process.poll() is None and time.monotonic() - start < 600:
                    print(f"Native {mode} workflow running ({int(time.monotonic()-start)} seconds)", flush=True)
                    time.sleep(15)
                if process.poll() is None:
                    # Terminate only this test's process group, including its workers.
                    import os
                    import signal
                    os.killpg(process.pid, signal.SIGTERM)
                    process.wait(timeout=20)
                    if mode != "paste":
                        raise TimeoutError(f"Native {mode} workflow exceeded ten minutes.")
                if process.returncode:
                    for diagnostic in (directory / "FAILURE.txt", directory / "current-check.txt", directory / "engine.log"):
                        if diagnostic.exists():
                            print(f"{diagnostic.name}:\n{diagnostic.read_text(errors='replace')[-20000:]}", flush=True)
                    if mode == "paste":
                        advisory[mode] = dict(status="failed", required=False, log=log.name)
                        print("::warning::Extended paste/layout UI validation failed. This advisory check does not block release; see its diagnostics.", flush=True)
                        continue
                    raise RuntimeError(f"Native {mode} workflow failed; see {log.name}.")
            try:
                report = json.loads((directory / "report.json").read_text())
                if report.get("status") != "passed" or not report.get("checks"):
                    raise ValueError(f"Native {mode} did not produce a passing test report.")
            except (OSError, ValueError) as error:
                if mode != "paste":
                    raise
                advisory[mode] = dict(status="failed", required=False, error=str(error))
                print(f"::warning::Extended paste/layout UI report failed: {error}", flush=True)
                continue
            result = dict(status="passed", checks=len(report["checks"]))
            if mode == "paste":
                advisory[mode] = dict(**result, required=False)
            else:
                reports[mode] = result
        summary = dict(version=expected, status="passed", read_only_installer=True,
                       workflows=reports, advisory_workflows=advisory, checks=sum(x["checks"] for x in reports.values()))
        (output / "validation.json").write_text(json.dumps(summary, indent=2) + "\n")
    finally:
        if attached:
            subprocess.run(["hdiutil", "detach", str(mount)], check=True)


if __name__ == "__main__":
    main()
