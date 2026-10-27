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
                 "R/power.R", "R/power_pilot.R", "www/dropdowns.js", "tests/power_pilot.R",
                 "scripts/test.py", ".github/workflows/platform-builds.yml"]:
        file = root / name
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text("Original synthetic fixture\n")
    check(audit(root)["status"] == "passed", "minimal synthetic public source passes privacy checks")
    (root / "R/power_pilot.R").unlink()
    check(any("Required source missing: R/power_pilot.R" in x for x in audit(root)["findings"]), "upload rejects a missing pilot-analysis implementation")
    (root / "R/power_pilot.R").write_text("Original synthetic fixture\n")
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

import release_assets
import publish_release
import os

with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    inputs = root / 'inputs'
    inputs.mkdir()
    (root / 'artifacts').mkdir()
    env = dict(GITHUB_SHA='a' * 40, GITHUB_RUN_ID='42', GITHUB_REF='refs/heads/main',
               GITHUB_EVENT_NAME='push', GITHUB_REPOSITORY='example/RDataCraft')
    base = dict(version=version, commit=env['GITHUB_SHA'], run_id='42')
    installers = []
    for platform in release_assets.PLATFORMS:
        name = f'RDataCraft-{version}-{platform}' + ('-setup.exe' if platform == 'windows-x64' else '.dmg')
        installer = inputs / name
        installer.write_bytes(('synthetic installer ' + platform).encode())
        installers.append(installer)
        release_assets.write_json(inputs / (platform + '-validation.json'), dict(
            **base, status='passed', platform=platform, installer=name, sha256=release_assets.digest(installer)))
    for platform in (*release_assets.PLATFORMS, 'native'):
        archive = inputs / f'RDataCraft-{version}-{platform}-sources.tar.gz'
        with tarfile.open(archive, 'w:gz'):
            pass
        release_assets.write_json(inputs / (platform + '-source-record.json'), dict(
            **base, archive=archive.name, sha256=release_assets.digest(archive)))
    def application_archive(command, **kwargs):
        destination = next(v.split('=', 1)[1] for v in command if v.startswith('--output='))
        with tarfile.open(destination, 'w'):
            pass
    with patch.dict(os.environ, env), patch.object(release_assets, 'ROOT', root), patch.object(release_assets.subprocess, 'run', side_effect=application_archive):
        output = root / 'release'
        release_assets.assemble(inputs, output)
        check(len(list(output.glob('*.dmg'))) == 2 and len(list(output.glob('*-setup.exe'))) == 1,
              'release assembly retains precisely three tested platform installers')
        report = json.loads((output / f'RDataCraft-{version}-validation.json').read_text())
        check(report['commit'] == env['GITHUB_SHA'] and len(report['platforms']) == 3,
              'release validation binds all three installers to one commit and Actions run')
        with tarfile.open(output / f'RDataCraft-{version}-sources.tar.gz') as archive:
            check(len([n for n in archive.getnames() if n.endswith('-sources.tar.gz')]) == 4 and 'application-source.tar' in archive.getnames(),
                  'release source bundle includes the current application and four dependency source parts')
        original = installers[0].read_bytes()
        installers[0].write_bytes(b'tampered fixture')
        try:
            release_assets.assemble(inputs, root / 'tampered')
        except ValueError:
            check(True, 'release assembly rejects installer bytes changed after validation')
        else:
            raise AssertionError('Changed installer passed release assembly')
        installers[0].write_bytes(original)
        first = inputs / (release_assets.PLATFORMS[0] + '-validation.json')
        record = json.loads(first.read_text())
        record['commit'] = 'b' * 40
        release_assets.write_json(first, record)
        try:
            release_assets.assemble(inputs, root / 'wrong-commit')
        except ValueError:
            check(True, 'release assembly rejects a passing report from a different commit')
        else:
            raise AssertionError('Wrong commit passed release assembly')
        record['commit'] = env['GITHUB_SHA']
        release_assets.write_json(first, record)
        source_record = inputs / 'native-source-record.json'
        source_record.unlink()
        try:
            release_assets.assemble(inputs, root / 'missing-source')
        except ValueError:
            check(True, 'release assembly refuses installers without matching native source material')
        else:
            raise AssertionError('Missing sources passed release assembly')

    # A published release cannot be replaced by a later main-branch build.
    previous = Path.cwd()
    try:
        os.chdir(root)
        (root / 'dist').mkdir()
        shutil = __import__('shutil')
        shutil.copytree(output, root / 'dist/release')
        with patch.dict(os.environ, env), patch.object(publish_release.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, '{"draft":false}', '')) as command:
            try:
                publish_release.main()
            except ValueError:
                check(command.call_count == 1, 'release publication refuses to modify an already published version')
            else:
                raise AssertionError('Published release was overwritten')
        # Explicit publication follows verification of the bytes GitHub received.
        def publication_fixture(publish, problem=None):
            state = dict(published=False)
            def command(args, **kwargs):
                if args[:2] == ['gh', 'api']:
                    return subprocess.CompletedProcess(args, 1, '', 'HTTP 404')
                if '--draft=false' in args:
                    state['published'] = True
                return subprocess.CompletedProcess(args, 0, '', '')
            def remote(path, payload=None):
                if '/assets?' in path:
                    values = [dict(name=f.name, size=f.stat().st_size, state='uploaded', digest='sha256:' + release_assets.digest(f)) for f in (root/'dist/release').iterdir() if f.is_file()]
                    if problem == 'digest': values[0]['digest'] = 'sha256:' + '0'*64
                    if problem == 'missing': values.pop()
                    return values
                if '/git/ref/' in path:
                    return dict(object=dict(type='commit', sha=('b'*40 if problem == 'tag' else env['GITHUB_SHA'])))
                return dict(id=7, draft=not state['published'])
            with patch.dict(os.environ, env), patch.object(publish_release, 'api', side_effect=remote), patch.object(publish_release.subprocess, 'run', side_effect=command):
                try: publish_release.main(publish=publish)
                except ValueError:
                    if not problem: raise
                else:
                    if problem: raise AssertionError('Invalid remote release passed publication')
            return state['published']
        check(not publication_fixture(False), 'default release preparation leaves a draft unpublished')
        check(publication_fixture(True), 'explicit publication verifies uploaded assets and publishes the tested tag')
        for problem in ('digest','missing','tag'):
            check(not publication_fixture(True, problem), 'publication rejects remote ' + problem + ' mismatch')
    finally:
        os.chdir(previous)

print(checks, "release-tool checks passed.")

# Release gating retains core failures and does not run extended UI sequences.
import plistlib
spec = importlib.util.spec_from_file_location('mac_bundle_validation', ROOT/'scripts/test_macos_bundle.py')
mac_validation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mac_validation)
for failing in ('studio', None):
    with tempfile.TemporaryDirectory() as temporary:
        output = Path(temporary)/'native'
        def fake_run(command, **kwargs):
            if command[1] == 'attach':
                app = output/'mounted/Fixture.app/Contents'
                app.mkdir(parents=True)
                (app/'Info.plist').write_bytes(plistlib.dumps({'CFBundleShortVersionString':json.loads((ROOT/'config/release.json').read_text())['version']}))
        class FakeProcess:
            def __init__(self, command, **kwargs):
                mode = command[1].split('-test=')[0][2:]
                directory = Path(command[1].split('=',1)[1]);directory.mkdir()
                (directory/'report.json').write_text(json.dumps({'status':'passed','checks':['fixture check']}))
                self.returncode = 1 if mode == failing else 0
            def poll(self):
                return self.returncode
        with patch.object(sys,'argv',['test','--dmg','fixture.dmg','--output',str(output)]), patch.object(mac_validation.subprocess,'run',fake_run), patch.object(mac_validation.subprocess,'Popen',FakeProcess):
            blocked = False
            try:
                mac_validation.main()
            except RuntimeError:
                blocked = True
            if failing == 'studio':
                check(blocked,'required core native failure still blocks release')
            else:
                summary = json.loads((output/'validation.json').read_text())
                check(not blocked and all(v['status']=='not_run' for v in summary['advisory_workflows'].values()) and set(summary['workflows'])=={'studio','multiwindow','graph'},'default installer validation runs core checks without extended UI sequences')
print(checks, 'total release-tool checks passed.')
