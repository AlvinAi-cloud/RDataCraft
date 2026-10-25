#!/usr/bin/env python3
"""Collect matching source material and assemble tested GitHub release assets."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile

ROOT = Path(__file__).resolve().parent.parent
VERSION = json.loads((ROOT / 'config/release.json').read_text())['version']
PLATFORMS = ('macos-x86_64', 'macos-arm64', 'windows-x64')


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def provenance():
    sha = os.environ['GITHUB_SHA']
    if not re.fullmatch('[0-9a-f]{40}', sha):
        raise ValueError('Expected the checked-out GitHub commit.')
    return dict(version=VERSION, commit=sha, run_id=os.environ['GITHUB_RUN_ID'])


def native():
    """Preserve the source pins and recipes reviewed for the bundled R toolchain."""
    for script in ('download_native.py', 'fetch_mxe.py'):
        subprocess.run([sys.executable, str(ROOT / 'scripts/release_native' / script)], check=True)
    material = ROOT / 'artifacts/release-native'
    vendor = material / 'rust-vendor'
    subprocess.run(['cargo', 'vendor', '--locked', '--versioned-dirs', '--manifest-path',
                    str(ROOT / 'desktop/ai-helper/Cargo.toml'), str(vendor)], check=True,
                   stdout=subprocess.DEVNULL)
    (material / 'cargo-vendor-config.toml').write_text(
        '[source.crates-io]\nreplace-with = "vendored-sources"\n'
        '[source.vendored-sources]\ndirectory = "rust-vendor"\n')
    licenses = ROOT / 'licenses'
    notices = licenses / 'RELEASE-NATIVE-NOTICES.txt'
    with notices.open('w', encoding='utf-8') as output:
        output.write('Bundled native and Rust dependency notices. Individual licenses remain in force.\n')
        for path in sorted((material / 'archives').iterdir()):
            process = None
            try:
                if path.name.endswith('.tar.lz'):
                    process = subprocess.Popen(['lzip', '-dc', str(path)], stdout=subprocess.PIPE)
                    archive = tarfile.open(fileobj=process.stdout, mode='r|')
                else:
                    archive = tarfile.open(path, 'r:*')
                with archive:
                    for item in archive:
                        name = Path(item.name).name
                        is_notice = re.match(r'^(copying|licen[cs]e|notice|copyright|exception)([._-].*)?$', name, re.I) or any(part.lower() in ('licenses', 'licences') for part in Path(item.name).parts[:-1])
                        if not item.isfile() or item.size > 2_000_000 or not is_notice:
                            continue
                        data = archive.extractfile(item).read()
                        if b'\0' not in data:
                            output.write('\n' + '=' * 72 + '\n' + path.name + ' :: ' + item.name + '\n')
                            output.write(data.decode('utf-8', 'replace') + '\n')
            finally:
                if process:
                    process.stdout.close()
                    if process.wait() != 0:
                        raise RuntimeError('Unable to read native source notices.')
        for path in sorted(vendor.rglob('*')):
            if path.is_file() and re.match(r'^(license|licence|copying|notice|copyright)', path.name, re.I):
                output.write('\n' + str(path.relative_to(material)) + '\n')
                output.write(path.read_text(encoding='utf-8', errors='replace') + '\n')
    (licenses / 'SOURCE-ACCESS.txt').write_text(
        f'RDataCraft v{VERSION}: source, build instructions, licenses and validation reports\n'
        f'https://github.com/AlvinAi-cloud/RDataCraft/releases/tag/v{VERSION}\n'
        'Application: GPL-3.0. Dependency licenses remain in force.\n'
        'The release source bundle includes native recipes, Rust dependencies and R/package sources.\n')
    output = ROOT / 'artifacts/release-native-assets'
    output.mkdir(parents=True, exist_ok=True)
    archive = output / f'RDataCraft-{VERSION}-native-sources.tar.gz'
    with tarfile.open(archive, 'w:gz') as stream:
        stream.add(material, arcname='native')
    write_json(output / 'native-source-record.json', dict(**provenance(), archive=archive.name, sha256=digest(archive)))


def platform_assets(platform, installer):
    """Record the bytes tested by this platform job, together with their sources."""
    installer = installer.resolve()
    suffix = '-setup.exe' if platform == 'windows-x64' else '.dmg'
    if installer.name != f'RDataCraft-{VERSION}-{platform}{suffix}' or not installer.is_file():
        raise ValueError('Installer name/version differs from this release.')
    output = ROOT / 'artifacts/release-ready' / platform
    output.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(installer, output / installer.name)
    if platform.startswith('macos-'):
        report = ROOT / 'artifacts/installed-mac/validation.json'
        source_report = ROOT / f'artifacts/validation-{VERSION}.json'
    else:
        report = ROOT / 'artifacts/installed-windows-native/validation-windows-desktop.json'
        source_report = ROOT / f'artifacts/validation-installed-windows-{VERSION}.json'
    reports = {}
    extra = [('installer', ROOT / f'artifacts/validation-windows-installer-{VERSION}.json')] if platform == 'windows-x64' else []
    for name, path in [('native', report), ('source', source_report)] + extra:
        data = json.loads(path.read_text())
        if data.get('status') != 'passed' or data.get('version') != VERSION:
            raise ValueError('Missing passing validation for the current installer: ' + str(path))
        reports[name] = data
    write_json(output / (platform + '-validation.json'), dict(
        **provenance(), platform=platform, status='passed', installer=installer.name,
        sha256=digest(installer), size=installer.stat().st_size, reports=reports,
        signing='ad-hoc, not notarized' if platform.startswith('macos-') else 'unsigned'))
    parts = ROOT / 'artifacts/release-source-parts'
    parts.mkdir(parents=True, exist_ok=True)
    archive = parts / f'RDataCraft-{VERSION}-{platform}-sources.tar.gz'
    with tarfile.open(archive, 'w:gz') as stream:
        for relative in ('downloads/sources', 'downloads/native-sources', 'dependencies.lock.json',
                         'source-manifest.json', 'licenses'):
            source = ROOT / relative
            if source.exists():
                stream.add(source, arcname=platform + '/' + relative)
    write_json(output / (platform + '-source-record.json'), dict(
        **provenance(), platform=platform, archive=archive.name, sha256=digest(archive)))


def assemble(inputs, output):
    current = provenance()
    output.mkdir(parents=True, exist_ok=False)
    records = []
    for platform in PLATFORMS:
        matches = list(inputs.rglob(platform + '-validation.json'))
        if len(matches) != 1:
            raise ValueError('Expected exactly one report for ' + platform)
        record = json.loads(matches[0].read_text())
        if record.get('status') != 'passed' or any(record.get(k) != v for k, v in current.items()):
            raise ValueError('Validation does not match this commit/run: ' + platform)
        expected_name = f'RDataCraft-{VERSION}-{platform}' + ('-setup.exe' if platform == 'windows-x64' else '.dmg')
        if record.get('platform') != platform or record.get('installer') != expected_name:
            raise ValueError('Installer/platform identity does not match.')
        installer = matches[0].parent / record['installer']
        if Path(record['installer']).name != record['installer'] or digest(installer) != record['sha256']:
            raise ValueError('Installer checksum differs from its platform report.')
        shutil.copyfile(installer, output / installer.name)
        records.append(record)
    # Verify each source archive against the same job's recorded hash before release.
    source_records = [*inputs.rglob('*-source-record.json'), *inputs.rglob('native-source-record.json')]
    source_records = sorted(set(source_records))
    if len(source_records) != 4:
        raise ValueError('Expected native and three platform source records.')
    archives = []
    for path in source_records:
        record = json.loads(path.read_text())
        if any(record.get(k) != v for k, v in current.items()):
            raise ValueError('Source provenance differs from this commit/run.')
        if Path(record['archive']).name != record['archive']:
            raise ValueError('Invalid source archive path.')
        matches = list(inputs.rglob(record['archive']))
        if len(matches) != 1 or digest(matches[0]) != record['sha256']:
            raise ValueError('Source archive checksum mismatch.')
        archives.append(matches[0])
    expected_archives = {f'RDataCraft-{VERSION}-{p}-sources.tar.gz' for p in (*PLATFORMS, 'native')}
    if {p.name for p in archives} != expected_archives:
        raise ValueError('Expected matching sources for every platform and native dependencies.')
    app_source = ROOT / 'artifacts/application-source.tar'
    subprocess.run(['git', 'archive', '--format=tar', '--prefix=application/',
                    '--output=' + str(app_source), current['commit']], cwd=ROOT, check=True)
    source_bundle = output / f'RDataCraft-{VERSION}-sources.tar.gz'
    with tarfile.open(source_bundle, 'w:gz') as stream:
        stream.add(app_source, arcname='application-source.tar')
        for path in archives:
            stream.add(path, arcname=path.name)
        text = output / 'SOURCE-README.txt'
        text.write_text(
            f'RDataCraft v{VERSION} corresponding source and build material\n\n'
            'Extract application-source.tar for this exact application commit. Each platform source archive\n'
            'contains its R/package archives, dependency inventory and license records. The native source\n'
            'archive contains pinned native inputs, Rtools45 MXE r6768 recipes and vendored Rust dependencies.\n'
            'Native R Mac recipes/compiler sources are included with those pinned archives.\n'
            'Use upstream R build instructions and the included recipes to rebuild native dependencies.\n'
            'Build/test/package the app using application/scripts and application/.github/workflows.\n'
            'Build provenance is not a claim of bit-for-bit reproduction of upstream R binaries.\n')
        stream.add(text, arcname=text.name)
    if source_bundle.stat().st_size >= 2 * 1024**3:
        raise ValueError('Source asset exceeds GitHub release size limit.')
    write_json(output / f'RDataCraft-{VERSION}-validation.json', dict(**current, status='passed', platforms=records))
    checksums = output / f'RDataCraft-{VERSION}-SHA256SUMS.txt'
    checksums.write_text(''.join(digest(p) + '  ' + p.name + '\n' for p in sorted(output.iterdir()) if p.is_file()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('native')
    platform = commands.add_parser('platform')
    platform.add_argument('--platform', choices=PLATFORMS, required=True)
    platform.add_argument('--installer', type=Path, required=True)
    final = commands.add_parser('assemble')
    final.add_argument('--inputs', type=Path, required=True)
    final.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.command == 'native':
        native()
    elif args.command == 'platform':
        platform_assets(args.platform, args.installer)
    else:
        assemble(args.inputs, args.output)


if __name__ == '__main__':
    main()
