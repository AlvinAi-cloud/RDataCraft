#!/usr/bin/env python3
"""Create/update a draft release from this workflow's verified three installers."""
import json
import os
from pathlib import Path
import re
import subprocess
from release_assets import VERSION, digest, PLATFORMS


def api(path, payload=None):
    args = ['gh', 'api', path]
    if payload is not None:
        args += ['--method', 'PATCH', '--input', '-']
    return json.loads(subprocess.check_output(args, input=json.dumps(payload) if payload else None, text=True))


def main():
    if os.environ.get('GITHUB_REF') != 'refs/heads/main' or os.environ.get('GITHUB_EVENT_NAME') not in ('push', 'workflow_dispatch'):
        raise SystemExit('Draft releases can only be prepared from main.')
    repo = os.environ['GITHUB_REPOSITORY']
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo):
        raise ValueError('Invalid repository.')
    sha = os.environ['GITHUB_SHA']
    output = Path('dist/release')
    validation = json.loads((output / f'RDataCraft-{VERSION}-validation.json').read_text())
    if validation['status'] != 'passed' or validation['commit'] != sha or validation['run_id'] != os.environ['GITHUB_RUN_ID']:
        raise ValueError('Release validation differs from this workflow.')
    expected = {f'RDataCraft-{VERSION}-{p}' + ('-setup.exe' if p == 'windows-x64' else '.dmg') for p in PLATFORMS}
    if {p.name for p in output.iterdir() if p.suffix in ('.exe', '.dmg')} != expected:
        raise ValueError('Expected precisely the three native installers.')
    for line in (output / f'RDataCraft-{VERSION}-SHA256SUMS.txt').read_text().splitlines():
        value, name = line.split('  ', 1)
        if Path(name).name != name or digest(output / name) != value:
            raise ValueError('Release checksum verification failed.')
    tag = 'v' + VERSION
    probe = subprocess.run(['gh', 'api', f'repos/{repo}/releases/tags/{tag}'], capture_output=True, text=True)
    if probe.returncode:
        if '404' not in probe.stderr:
            raise RuntimeError('Cannot inspect the existing release: ' + probe.stderr)
        existing = None
    else:
        existing = json.loads(probe.stdout)
        if not existing['draft']:
            raise ValueError('This version is already published. Published releases are never overwritten.')
        ref = api(f'repos/{repo}/git/ref/tags/{tag}')['object']
        if ref['type'] != 'commit':
            raise ValueError('A manually annotated release tag requires review before updating.')
        if ref['sha'] != sha:
            comparison = api(f'repos/{repo}/compare/{ref["sha"]}...{sha}')
            if comparison['status'] != 'ahead':
                raise ValueError('Refusing to move the draft tag to a divergent commit.')
            api(f'repos/{repo}/git/refs/tags/{tag}', dict(sha=sha, force=False))
    notes = Path('artifacts/release-notes.md')
    notes.write_text(
        f'RDataCraft {tag}\n\n'
        'R-powered scientific plotting and statistics for Mac and Windows.\n\n'
        'This update adds continuous worksheets, clearer analysis menus, independent XY fits on scatter and mean/error graphs, '
        'separate connection/curve controls, the corrected Intel Dock icon and aligned transform controls.\n\n'
        'Download the installer for your computer:\n\n'
        f'- [Intel Mac](https://github.com/{repo}/releases/download/{tag}/RDataCraft-{VERSION}-macos-x86_64.dmg)\n'
        f'- [Apple Silicon Mac](https://github.com/{repo}/releases/download/{tag}/RDataCraft-{VERSION}-macos-arm64.dmg)\n'
        f'- [Windows x64](https://github.com/{repo}/releases/download/{tag}/RDataCraft-{VERSION}-windows-x64-setup.exe)\n\n'
        'All three installers were built and tested in this GitHub Actions run. R and required packages are bundled; '
        'Windows uses its own desktop window, not an external browser. Mac builds are ad-hoc signed and not notarized; '
        'Windows setup is unsigned. GitHub does not provide trusted signing credentials.\n\n'
        'Studies using the new XY display options require v0.32 or later. Corresponding source, dependency notices, '
        'SHA-256 checksums and the matching validation report accompany these installers. '
        'Live AI-provider account access and vector paste into external design apps are not certified by these automated tests.\n\n'
        f'Built from `{sha}`.\n')
    if existing is None:
        subprocess.run(['gh', 'release', 'create', tag, '--repo', repo, '--draft', '--target', sha,
                        '--title', 'RDataCraft ' + tag, '--notes-file', str(notes)], check=True)
    else:
        subprocess.run(['gh', 'release', 'edit', tag, '--repo', repo, '--draft', '--target', sha,
                        '--title', 'RDataCraft ' + tag, '--notes-file', str(notes)], check=True)
    subprocess.run(['gh', 'release', 'upload', tag, '--repo', repo, '--clobber',
                    *[str(p) for p in sorted(output.iterdir()) if p.is_file()]], check=True)
    print(f'Draft ready: https://github.com/{repo}/releases (not published)')


if __name__ == '__main__':
    main()
