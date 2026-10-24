#!/usr/bin/env python3
"""Collect exact R/package sources; native-library source coverage is a separate audit."""
import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parent.parent


def download(name, version, destination, pinned):
    if not re.fullmatch(r'[A-Za-z][A-Za-z0-9.]*', name) or not re.fullmatch(r'[0-9][0-9A-Za-z.+-]*', version):
        raise ValueError('Invalid source component or version.')
    filename = f'R-{version}.tar.gz' if name == 'R' else f'{name}_{version}.tar.gz'
    target = destination / filename
    previous = pinned.get(filename, {})
    urls = ([f'https://cran.r-project.org/src/base/R-4/{filename}'] if name == 'R' else [
        f'https://cran.r-project.org/src/contrib/{filename}',
        f'https://cran.r-project.org/src/contrib/Archive/{name}/{filename}'])
    source = previous.get('source', urls[0])
    if not target.exists():
        partial = target.with_name(target.name + '.part')
        for url in urls:
            run = subprocess.run(['curl', '--silent', '--show-error', '--fail', '--location',
                                  '--connect-timeout', '20', '--max-time', '180', '--retry', '2',
                                  '--output', str(partial), url], capture_output=True)
            if run.returncode == 0:
                partial.replace(target)
                source = url
                break
        else:
            partial.unlink(missing_ok=True)
            raise RuntimeError(f'No matching source archive available for {name} {version}')
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    if previous.get('sha256') and digest != previous['sha256']:
        raise RuntimeError(f'Pinned source checksum changed for {filename}; retained for investigation.')
    # Inspect metadata without extracting paths or running package code.
    with tarfile.open(target, 'r:gz') as archive:
        if name != 'R':
            desc = archive.getmember(f'{name}/DESCRIPTION')
            if desc.size > 1_000_000:
                raise ValueError(f'Oversized DESCRIPTION in {filename}')
            text = archive.extractfile(desc).read().decode('utf-8')
            if not re.search(rf'^Package:\s*{re.escape(name)}\s*$', text, re.M) or not re.search(
                    rf'^Version:\s*{re.escape(version)}\s*$', text, re.M):
                raise ValueError(f'Wrong source version in {filename}')
        elif f'R-{version}/VERSION' not in archive.getnames():
            raise ValueError(f'Wrong R source archive: {filename}')
    return dict(component=name, version=version, archive=filename, source=source, sha256=digest)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lock', type=Path, action='append', help='Include target-platform dependencies; repeat as needed.')
    args = parser.parse_args()
    destination = ROOT / 'downloads/sources'
    destination.mkdir(parents=True, exist_ok=True)
    path = ROOT / 'source-manifest.json'
    previous = json.loads(path.read_text()) if path.exists() else {}
    pinned = {p['archive']: p for p in previous.get('archives', [])}
    jobs = set()
    for lock in [ROOT / 'dependencies.lock.json'] + (args.lock or []):
        data = json.loads(lock.read_text())
        jobs.add(('R', data['r_version']))
        jobs.update((p['package'], p['version']) for p in data['packages'])
    records, failures = [], []
    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
        futures = {pool.submit(download, *job, destination, pinned): job for job in sorted(jobs)}
        for future in concurrent.futures.as_completed(futures):
            try:
                record = future.result()
                records.append(record)
                print('Verified source:', record['archive'], flush=True)
            except Exception as exc:
                failures.append(str(exc))
                print('FAILED:', exc, flush=True)
    report = dict(archives=sorted(records, key=lambda x: (x['component'].lower(), x['version'])),
                  expected_archives=len(jobs), verified_archives=len(records), missing=failures,
                  native_library_audit='pending; see licenses/REDISTRIBUTION.md')
    path.write_text(json.dumps(report, indent=2) + '\n')
    if failures:
        raise SystemExit('Some sources could not be verified; inspect source-manifest.json.')
    print(f'Verified {len(records)} exact R/package source releases.')


if __name__ == '__main__':
    main()
