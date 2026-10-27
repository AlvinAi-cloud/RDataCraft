#!/usr/bin/env python3
"""Assemble a draft, or publish verified installers when explicitly requested."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
from release_assets import VERSION, digest, PLATFORMS


def api(path, payload=None, method="PATCH"):
    args = ['gh', 'api', path]
    if payload is not None:
        args += ['--method', method, '--input', '-']
    return json.loads(subprocess.check_output(args, input=json.dumps(payload) if payload else None, text=True))


def main(publish=False):
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
    # Draft releases do not have a published tag URL yet. Find them through
    # the authenticated collection and retain the numeric release identity.
    page = 1
    existing = None
    while True:
        releases = api(f'repos/{repo}/releases?per_page=100&page={page}')
        existing = next((r for r in releases if r['tag_name'] == tag), None)
        if existing is not None or len(releases) < 100:
            break
        page += 1
    if existing is not None and not existing['draft']:
        raise ValueError('This version is already published. Published releases are never overwritten.')
    probe = subprocess.run(['gh', 'api', f'repos/{repo}/git/ref/tags/{tag}'], capture_output=True, text=True)
    if probe.returncode:
        if '404' not in probe.stderr:
            raise RuntimeError('Cannot inspect the release tag: ' + probe.stderr)
        ref = None
    else:
        ref = json.loads(probe.stdout)['object']
        if ref['type'] != 'commit':
            raise ValueError('A manually annotated release tag requires review before updating.')
        if ref['sha'] != sha:
            if existing is None:
                raise ValueError('Existing tag differs from the tested commit.')
            comparison = api(f'repos/{repo}/compare/{ref["sha"]}...{sha}')
            if comparison['status'] != 'ahead':
                raise ValueError('Refusing to move the draft tag to a divergent commit.')
            api(f'repos/{repo}/git/refs/tags/{tag}', dict(sha=sha, force=False))
    notes = Path('artifacts/release-notes.md')
    notes.write_text(
        f'RDataCraft {tag}\n\n'
        'R-powered scientific plotting and statistics for Mac and Windows.\n\n'
        'This update simplifies Advanced R access: it is the final Analysis method option for every table type, '
        'and remains available in the top toolbar. Opening it preserves the current preset and never executes a script. '
        'XY analysis guidance now distinguishes correlation, regression, AUC and comparisons requiring a suitable repeated-measures design. '
        'The recent extended paste/layout and pilot-planning UI checks no longer run in GitHub; '
        'numerical, source, installer and core installed-app checks remain required.\n\n'
        'Download the installer for your computer:\n\n'
        f'- [Intel Mac](https://github.com/{repo}/releases/download/{tag}/RDataCraft-{VERSION}-macos-x86_64.dmg)\n'
        f'- [Apple Silicon Mac](https://github.com/{repo}/releases/download/{tag}/RDataCraft-{VERSION}-macos-arm64.dmg)\n'
        f'- [Windows x64](https://github.com/{repo}/releases/download/{tag}/RDataCraft-{VERSION}-windows-x64-setup.exe)\n\n'
        'All three installers passed required build, source and installed-app checks in this GitHub Actions run. R and required packages are bundled; '
        'Windows uses its own desktop window, not an external browser. Mac builds are ad-hoc signed and not notarized; '
        'Windows setup is unsigned. GitHub does not provide trusted signing credentials.\n\n'
        'Studies using the XY display options introduced in v0.32 require v0.32 or later. Corresponding source, dependency notices, '
        'SHA-256 checksums and the matching validation report accompany these installers. '
        'Live AI-provider account access and vector paste into external design apps are not certified by these automated tests.\n\n'
        f'Built from `{sha}`.\n')
    payload = dict(tag_name=tag, target_commitish=sha, name='RDataCraft ' + tag,
                   body=notes.read_text(), draft=True)
    if existing is None:
        release = api(f'repos/{repo}/releases', payload, method='POST')
    else:
        release = api(f'repos/{repo}/releases/{existing["id"]}', payload)
    release_path = f'repos/{repo}/releases/{release["id"]}'
    subprocess.run(['gh', 'release', 'upload', tag, '--repo', repo, '--clobber',
                    *[str(p) for p in sorted(output.iterdir()) if p.is_file()]], check=True)
    if publish:
        release = api(release_path)
        if not release['draft'] or release['tag_name'] != tag or release['target_commitish'] != sha:
            raise ValueError('Expected an unpublished draft before final verification.')
        assets = api(f'repos/{repo}/releases/{release["id"]}/assets?per_page=100')
        files = {p.name: p for p in output.iterdir() if p.is_file()}
        if len(assets) != len(files) or {a['name'] for a in assets} != set(files):
            raise ValueError('Uploaded release assets differ from the verified release folder.')
        for asset in assets:
            path = files[asset['name']]
            if asset.get('state') != 'uploaded' or asset['size'] != path.stat().st_size or asset.get('digest') != 'sha256:' + digest(path):
                raise ValueError('Uploaded asset size/checksum mismatch: ' + asset['name'])
        if ref is None:
            api(f'repos/{repo}/git/refs', dict(ref='refs/tags/' + tag, sha=sha), method='POST')
        verified_ref = api(f'repos/{repo}/git/ref/tags/{tag}')['object']
        if verified_ref['type'] != 'commit' or verified_ref['sha'] != sha:
            raise ValueError('Release tag differs from the tested commit.')
        api(release_path, dict(draft=False, make_latest='true'))
        if api(release_path)['draft']:
            raise ValueError('GitHub did not publish the release.')
        print(f'Published: https://github.com/{repo}/releases/tag/{tag}')
    else:
        print(f'Draft ready: https://github.com/{repo}/releases (not published)')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--publish', action='store_true', help='Publish after verifying all uploaded assets and the tested release tag.')
    main(publish=parser.parse_args().publish)
