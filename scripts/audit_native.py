#!/usr/bin/env python3
"""Record Mac runtime binaries and their linked libraries; this does not certify source coverage."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def audit(runtime, arch):
    records = []
    for file in sorted(runtime.rglob('*')):
        if file.is_symlink() or not file.is_file() or file.suffix == '.class':
            continue
        if file.open('rb').read(4) not in [bytes.fromhex(x) for x in ['cffaedfe','feedfacf','cafebabe','bebafeca','cefaedfe','feedface']]:
            continue
        architectures = subprocess.check_output(['lipo','-archs',str(file)],text=True).split()
        if arch not in architectures:
            raise ValueError('Runtime architecture mismatch: ' + str(file.relative_to(runtime)))
        linked = [line.strip().split(' (compatibility')[0] for line in subprocess.check_output(['otool','-L',str(file)],text=True).splitlines()[1:]]
        optional = [link for link in linked if link.startswith(('/opt/X11/', '/opt/R/'))]
        records.append(dict(path=file.relative_to(runtime).as_posix(),sha256=hashlib.sha256(file.read_bytes()).hexdigest(),
                            architectures=architectures,linked_libraries=linked,external_optional_libraries=optional))
    return dict(architecture=arch,binaries=records,source_coverage='not certified',
                optional_modules='Stock R Tcl/Tk and X11 modules depend on external installations. Main app graphics use Quartz/SVG.')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime',type=Path,required=True)
    parser.add_argument('--arch',choices=['x86_64','arm64'],required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    report=audit(args.runtime.resolve(),args.arch)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(report,indent=2)+'\n')
    print('Inventoried',len(report['binaries']),'native',args.arch,'runtime binaries.')


if __name__=='__main__':main()
