#!/usr/bin/env python3
"""Plan or apply Developer ID signing; notarize and staple only with configured credentials.

Never changes the input app: --apply requires a new output path. A plan is not
evidence that a distribution signature, notarization or signed-runtime test passed.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess

MAGIC = {bytes.fromhex(x) for x in ("cffaedfe", "feedfacf", "cafebabe", "bebafeca", "cefaedfe", "feedface")}


def binary_paths(app):
    paths = []
    for p in app.rglob("*"):
        if p.is_symlink() or not p.is_file() or p.suffix == ".class":
            continue
        with p.open("rb") as stream:
            if stream.read(4) in MAGIC:
                paths.append(p.relative_to(app))
    return sorted(paths, key=lambda p: (-len(p.parts), p.as_posix()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--identity", help="Full Developer ID Application identity name; never a private key.")
    parser.add_argument("--notary-profile", help="Existing notarytool Keychain profile name.")
    parser.add_argument("--apply", action="store_true", help="Sign a separate copy and submit it to Apple.")
    args = parser.parse_args()
    source = args.app.resolve()
    info = plistlib.loads((source / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != "org.rdatacraft.desktop":
        parser.error("Expected an RDataCraft application bundle.")
    paths = binary_paths(source)
    if not args.apply:
        print(json.dumps(dict(mode="plan only", version=info["CFBundleShortVersionString"],
                              binaries=[p.as_posix() for p in paths],
                              required=["Developer ID Application identity", "notarytool Keychain profile",
                                        "native workflow tests of the signed copy"],
                              signed=False, notarized=False), indent=2))
        return
    if not args.identity or not args.identity.startswith("Developer ID Application:") or not args.notary_profile:
        parser.error("--apply requires a Developer ID Application identity and --notary-profile.")
    identities = subprocess.check_output(["security", "find-identity", "-v", "-p", "codesigning"], text=True)
    if f'"{args.identity}"' not in identities:
        parser.error("The requested valid signing identity is not available in the Keychain.")
    if not args.output:
        parser.error("Choose a new --output app; the input app is preserved.")
    output = args.output.resolve()
    if output.suffix != ".app" or output.exists() or source in output.parents:
        parser.error("Choose a new, separate .app output path.")
    output.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(source, output, symlinks=True)
    # Only R processes need external R-package loading and the local DYLD path.
    # The native UI host gets no hardened-runtime exceptions.
    entitlements = output.parent / (output.stem + "-R-entitlements.plist")
    entitlements.write_bytes(plistlib.dumps({
        "com.apple.security.cs.disable-library-validation": True,
        "com.apple.security.cs.allow-dyld-environment-variables": True,
    }))
    def run(*command):
        subprocess.run(list(map(str, command)), check=True)
    def sign(path, r_process=False):
        command = ["codesign", "--force", "--sign", args.identity, "--timestamp", "--options", "runtime"]
        if r_process:
            command += ["--entitlements", str(entitlements)]
        run(*command, path)
    for relative in paths:
        sign(output / relative, relative.name in {"R", "Rscript"})
    # Seal framework containers after their nested Mach-O files, then the app.
    frameworks = sorted((p for p in output.rglob("*.framework") if not p.is_symlink()),
                        key=lambda p: len(p.parts), reverse=True)
    for framework in frameworks:
        sign(framework)
    sign(output)
    run("codesign", "--verify", "--deep", "--strict", output)
    archive = output.parent / (output.stem + "-notary.zip")
    if archive.exists():
        raise SystemExit("Notary ZIP already exists; inspect it before retrying.")
    run("ditto", "-c", "-k", "--keepParent", output, archive)
    result = subprocess.check_output(["xcrun", "notarytool", "submit", str(archive),
                                     "--keychain-profile", args.notary_profile, "--wait", "--output-format", "json"], text=True)
    report = json.loads(result)
    report_path = output.parent / (output.stem + "-notarization.json")
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    if report.get("status") != "Accepted":
        raise SystemExit("Apple did not accept this submission; inspect the notary log. No success report generated.")
    run("xcrun", "stapler", "staple", output)
    run("xcrun", "stapler", "validate", output)
    run("codesign", "--verify", "--deep", "--strict", output)
    run("spctl", "--assess", "--type", "execute", "--verbose=2", output)
    report.update(version=info["CFBundleShortVersionString"], stapled=True,
                  gatekeeper_assessment="passed", signed_runtime_tests="required after signing",
                  host_sha256=hashlib.sha256((output / "Contents/MacOS/RDataCraft").read_bytes()).hexdigest())
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    print("Notarized copy:", output)


if __name__ == "__main__":
    main()
