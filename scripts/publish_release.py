#!/usr/bin/env python3
"""Assemble a draft, or publish verified installers when explicitly requested."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
from release_assets import installer_name, VERSION, digest, PLATFORMS
from release_plan import load_reuse,verify_report


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
    plan=load_reuse(Path.cwd(),VERSION)
    if plan:
        records=validation.get('platforms',[])
        if len(records)!=len(PLATFORMS) or {r.get('platform') for r in records}!=set(PLATFORMS):raise ValueError('Missing preserved platform provenance.')
        current=dict(version=VERSION,commit=sha,run_id=os.environ['GITHUB_RUN_ID'])
        for r in records:
            verify_report(r,current,r['platform'],plan)
            file=output/installer_name(r['platform'])
            if digest(file)!=r.get('sha256') or file.stat().st_size!=r.get('size'):raise ValueError('Preserved installer bytes differ from their original tested report.')
    expected = {installer_name(p) for p in PLATFORMS}
    if {p.name for p in output.iterdir() if p.suffix in ('.exe', '.dmg', '.deb')} != expected:
        raise ValueError('Expected precisely the four platform installers.')
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
    # Binary UTF-8 keeps LF line endings identical on Windows and Unix hosts.
    notes.write_bytes((
        f'RDataCraft {tag}\n\n'
        'R-powered scientific plotting and statistics for Mac, Windows and Ubuntu.\n\n'
        + ('New in v0.6.1: dose-response results and constraints use the standard Hill coefficient. '
           'Fixed-Hill fits retry from the measured dose range if the first fit fails. '
           'Nonlinear regressions report 95% profile-likelihood intervals. '
           'Shared nonlinear fits with more than 12 free parameters use Wald intervals.\n\n'
           if tag == 'v0.6.1' else '')
        + 'New in v0.6: fixed/bounded regression parameters with Defaults and group-specific overrides; '
        'independent curves remain together on one graph. Shared/global fitting is a separate joint least-squares option '
        'with selected shared coefficients, intersected bounds and joint uncertainty. '
        'A three-parameter increasing dose-response model fixes the conventional Hill slope at +1.\n\n'
        'The AI Assistant reliably delivers larger UTF-8 requests, reports timeouts and recovers after service failure. '
        'Repeated account-status lines are removed. Constraint dialogs and AI/Figure settings panels adapt to smaller windows. '
        'AI proposals and Advanced R scripts remain subject to explicit review before execution.\n\n'
        'Installer filenames and the installed app name are now stable across versions. The version remains in About, study metadata, '
        'release tags, checksums and validation reports. Legacy version-named Mac apps may be removed manually after installing RDataCraft.app.\n\n'
        'Figure settings → XY lines & fitted curves and the existing scientific workflows are retained. '
        'New studies use `.rdcraft`; existing `.rdatacraft` studies continue to open.\n\n'
        'The AI panel points to AI → Accounts and Models when disconnected; connection settings stay in the AI menu. '
        'Figure settings and AI tile side by side with independent visibility controls. Check for Updates opens matching public installer downloads. '
        'Ubuntu 24.04 LTS amd64 is available as a native GTK/WebKit .deb; Ubuntu manages its R 4.3 engine while the app carries its R package library. '
        'Ubuntu uses SVG/PDF export for vector transfer; optional package installation in the app is available on Mac and Windows only.\n\n'
        'Download the installer for your computer:\n\n'
        f'- [Intel Mac](https://github.com/{repo}/releases/download/{tag}/RDataCraft-macos-x86_64.dmg)\n'
        f'- [Apple Silicon Mac](https://github.com/{repo}/releases/download/{tag}/RDataCraft-macos-arm64.dmg)\n'
        f'- [Windows x64](https://github.com/{repo}/releases/download/{tag}/RDataCraft-windows-x64-setup.exe)\n\n'
        f'- [Ubuntu 24.04 amd64](https://github.com/{repo}/releases/download/{tag}/RDataCraft-ubuntu-amd64.deb)\n\n'
        'All four installers passed required build, source and installed-app checks in the GitHub Actions runs recorded in validation. Mac and Windows bundle R and required packages; Ubuntu installs R through its package manager; '
        'Windows uses its own desktop window, not an external browser. Mac builds are ad-hoc signed and not notarized; '
        'Windows setup is unsigned. GitHub does not provide trusted signing credentials.\n\n'
        'Studies using the new fitting constraints/global options require v0.6 or later (schema 14/15). Existing study files remain readable. Corresponding source, dependency notices, '
        'SHA-256 checksums and the matching validation report accompany these installers. '
        'Live AI-provider account access and vector paste into external design apps are not certified by these automated tests.\n\n'
        f'Release source: `{sha}`. The validation report identifies each installer’s actual build commit and run.\n'
        + (f'The tested Mac and Windows installers are preserved from `{plan["commit"]}` (run {plan["run_id"]}); only Ubuntu was rebuilt. Corresponding application source for both commits is included.\n' if plan else '')).encode('utf-8'))
    payload = dict(tag_name=tag, target_commitish=sha, name='RDataCraft ' + tag,
                   body=notes.read_text(encoding='utf-8'), draft=True)
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
