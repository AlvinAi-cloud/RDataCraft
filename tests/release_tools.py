"""Exercise release privacy and package inventories with synthetic files."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import hashlib
import io
import subprocess
import tarfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
from preflight import audit
from runtime_inventory import manifest
from sign_windows import signing_command, powershell_environment
import fetch_windows_components
from sign_macos import binary_paths
from unittest.mock import patch
import package_installers
from fetch_sources import download
from package_portable import verify_windows_runtime
import struct

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

    # The official R installer leaves a 32-bit maintenance utility beside its
    # x64 runtime. Exclude that utility, while rejecting actual x86 engine code.
    winhome, winlib = root/'win-R', root/'win-library'
    engine=winhome/'bin/x64/Rscript.exe'; engine.parent.mkdir(parents=True)
    def pe(machine):
        data=bytearray(128);data[:2]=b'MZ';struct.pack_into('<I',data,0x3c,64)
        data[64:68]=b'PE\0\0';struct.pack_into('<H',data,68,machine);return data
    engine.write_bytes(pe(0x8664))
    (winhome/'unins000.exe').write_bytes(pe(0x14c))
    desc=winlib/'Fixture/DESCRIPTION';desc.parent.mkdir(parents=True)
    desc.write_text('Package: Fixture\nBuilt: R 4.6.1; x86_64-w64-mingw32; 2026-10-01; windows\n')
    check(verify_windows_runtime(winhome,winlib)['x64_pe_files']==1,
          'R installer maintenance utilities do not invalidate the x64 engine audit')
    engine.write_bytes(pe(0x14c))
    try:verify_windows_runtime(winhome,winlib)
    except ValueError:check(True,'Windows packaging still rejects a 32-bit R engine')
    else:raise AssertionError('A 32-bit R engine passed the x64 audit')

    with patch.dict('os.environ',{'PSMODULEPATH':'fixture-incompatible-modules'}):
        check(not any(k.upper()=='PSMODULEPATH' for k in powershell_environment()),
              'Windows signature checks do not inherit modules from a different PowerShell version')
    component=root/'vendor-installer.exe';component.write_bytes(b'original synthetic component')
    pin={'webview2':{'sha256':hashlib.sha256(component.read_bytes()).hexdigest()}}
    with patch.object(fetch_windows_components,'PIN',pin), patch.object(fetch_windows_components.os,'name','nt'), patch('sign_windows.shutil.which',return_value='pwsh.exe'), patch.object(fetch_windows_components.subprocess,'run',side_effect=subprocess.CalledProcessError(1,['fixture'])):
        try:fetch_windows_components.verify(component)
        except subprocess.CalledProcessError:check(True,'a failed Microsoft signature check rejects the runtime')
        else:raise AssertionError('A failed signature was accepted')
    component.write_bytes(b'tampered component')
    with patch.object(fetch_windows_components,'PIN',pin):
        try:fetch_windows_components.verify(component)
        except ValueError:check(True,'Windows component checksum rejects a changed installer before execution')
        else:raise AssertionError('A changed component was accepted')

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

    # Recover from a mirror outage without weakening corresponding-source pins.
    archive = io.BytesIO()
    description = b'Package: FixturePackage\nVersion: 1.0\n'
    with tarfile.open(fileobj=archive, mode='w:gz') as tar:
        entry = tarfile.TarInfo('FixturePackage/DESCRIPTION')
        entry.size = len(description)
        tar.addfile(entry, io.BytesIO(description))
    data = archive.getvalue()
    sources = root/'source-downloads'
    sources.mkdir()
    pin = {'FixturePackage_1.0.tar.gz': {'sha256': hashlib.sha256(data).hexdigest()}}
    def mirror(command, **kwargs):
        if 'https://cran.r-project.org/' in ' '.join(command):
            return subprocess.CompletedProcess(command, 22, b'', b'fixture mirror unavailable')
        Path(command[command.index('--output')+1]).write_bytes(data)
        return subprocess.CompletedProcess(command, 0, b'', b'')
    with patch('fetch_sources.subprocess.run', side_effect=mirror):
        downloaded = download('FixturePackage', '1.0', sources, pin)
    check(downloaded['source'].startswith('https://cloud.r-project.org/') and downloaded['sha256'] == pin[downloaded['archive']]['sha256'],
          'source collection recovers through the CRAN mirror while retaining the pinned checksum')
    try:
        download('FixturePackage', '1.0', sources, {'FixturePackage_1.0.tar.gz': {'sha256': '0'*64}})
    except RuntimeError:
        check(True, 'source collection still rejects archives that differ from the pinned checksum')
    else:
        raise AssertionError('Source pin validation was bypassed')

release = json.loads((ROOT/'config/release.json').read_text(encoding='utf-8'))
version = release['version']
check(all(f'v{version}' in (ROOT/name).read_text(encoding='utf-8') for name in ['R/ui.R','desktop/RDataCraft.swift','app.R']) and
      f'app_version = "{version}"' in (ROOT/'R/project.R').read_text(encoding='utf-8'),
      "UI, native About and new study metadata agree with the release version")

print(checks, "release-tool checks passed.")
