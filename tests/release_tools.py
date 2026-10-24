"""Exercise release privacy and package inventories with synthetic files."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
from preflight import audit
from runtime_inventory import manifest
from sign_windows import signing_command
from sign_macos import binary_paths
from unittest.mock import patch
import package_installers

checks = 0
def check(value, label):
    global checks
    if not value:
        raise AssertionError(label)
    checks += 1
    print("PASS:", label)

with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    for name in ["app.R", "README.md", "LICENSE", ".gitignore", "R/help.R",
                 "scripts/test.py", ".github/workflows/platform-builds.yml"]:
        file = root / name
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text("Original synthetic fixture\n")
    check(audit(root)["status"] == "passed", "minimal synthetic public source passes privacy checks")
    private = root / "study.rdatacraft"
    private.write_text('{"format":"rdatacraft"}')
    check(any("Unreviewed study" in x for x in audit(root)["findings"]), "private studies outside curated examples are rejected")
    private.unlink()
    credential = root / "configuration.txt"
    credential.write_text("gh" + "p_" + "a" * 36)
    check(any("token" in x for x in audit(root)["findings"]), "credentials are detected without printing their values")
    credential.unlink()
    target = root / "README.md"
    target.write_text("[broken](does-not-exist.md)")
    check(any("Broken local link" in x for x in audit(root)["findings"]), "broken repository documentation links are detected")
    target.write_text("Fixture")
    # Package inventory covers recommended packages and respects app precedence.
    home, library = root / "engine", root / "packages"
    for folder, name, version, priority in [
        (home/"library", "base", "4.6.1", "base"),
        (home/"library", "stats", "4.6.1", "base"),
        (home/"library", "translations", "4.6.1", ""),
        (home/"library", "survival", "3.8-6", "recommended"),
        (home/"library", "MASS", "7.3-65", "recommended"),
        (library, "survival", "3.8-12", "")]:
        file = folder/name/"DESCRIPTION"
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(f"Package: {name}\nVersion: {version}\nPriority: {priority}\nLicense: " +
                        ("Part of R 4.6.1" if name == "translations" else "GPL-3") + "\n")
    data = manifest(home, library, "fixture-platform")
    versions = {p["package"]: p["version"] for p in data["packages"]}
    check(set(versions) == {"MASS", "survival"}, "runtime inventory includes recommended packages and excludes R core components")
    check(versions["survival"] == "3.8-12", "runtime inventory records the package actually selected by the app library")

    # Bad signing configuration must fail before any installer mutation.
    for certificate, timestamp in [("not-a-thumbprint", "https://timestamp.example.com"),
                                   ("a"*40, "http://timestamp.example.com"),
                                   ("a"*40, "https://user:secret@timestamp.example.com")]:
        try:
            signing_command("signtool.exe", certificate, timestamp, Path("setup.exe"))
        except ValueError:
            check(True, "invalid signing identity or timestamp origin is rejected")
        else:
            raise AssertionError("Invalid signing configuration was accepted")
    command = signing_command("signtool.exe", "a"*40, "https://timestamp.example.com", Path("setup.exe"))
    check(command[command.index('/fd')+1] == 'SHA256' and command[command.index('/td')+1] == 'SHA256',
          "Windows signing requests SHA-256 for both file and timestamp")
    app = root / "fixture.app"
    (app / "Contents/MacOS").mkdir(parents=True)
    (app / "Contents/MacOS/fixture").write_bytes(bytes.fromhex('cffaedfe') + b'synthetic')
    (app / "Contents/Example.class").write_bytes(bytes.fromhex('cafebabe') + b'synthetic')
    check(binary_paths(app) == [Path('Contents/MacOS/fixture')], "Mac signing inventory excludes Java class files")
    with patch.object(package_installers.subprocess, 'run'), patch.object(package_installers.subprocess, 'check_output',
             return_value='Signature=adhoc\nCodeDirectory flags=0x0(none)'):
        try:
            package_installers.mac(app, 'x86_64', distribution=True)
        except SystemExit as error:
            check('Developer ID' in str(error), "distribution packaging refuses an ad-hoc Mac signature")
        else:
            raise AssertionError('Ad-hoc signature passed the distribution gate')

release = json.loads((ROOT/'config/release.json').read_text())
version = release['version']
check(all(f'v{version}' in (ROOT/name).read_text() for name in ['R/ui.R','desktop/RDataCraft.swift','app.R']) and
      f'app_version = "{version}"' in (ROOT/'R/project.R').read_text(),
      "UI, native About and new study metadata agree with the release version")

print(checks, "release-tool checks passed.")
