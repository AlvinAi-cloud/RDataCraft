#!/usr/bin/env python3
"""Fetch the pinned NSIS compiler, rejecting mirror error pages and changed bytes."""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request
import zipfile

ROOT=Path(__file__).resolve().parent.parent
PIN=json.loads((ROOT/'config/windows-components.json').read_text(encoding='utf-8'))['nsis']

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'artifacts/release-tools')
    args=parser.parse_args();directory=args.output;directory.mkdir(parents=True,exist_ok=True)
    archive=directory/'nsis.zip';temporary=directory/'nsis.zip.download'
    valid=archive.is_file() and hashlib.sha256(archive.read_bytes()).hexdigest()==PIN['sha256']
    failures=[]
    if not valid:
        for url in PIN['urls']:
            try:
                with urllib.request.urlopen(url,timeout=90) as response,temporary.open('wb') as stream:
                    while True:
                        block=response.read(1024*1024)
                        if not block:break
                        stream.write(block)
                digest=hashlib.sha256(temporary.read_bytes()).hexdigest()
                if digest!=PIN['sha256']:raise ValueError('Download checksum mismatch: '+digest)
                temporary.replace(archive);valid=True;break
            except Exception as error:failures.append(url+': '+str(error))
            finally:temporary.unlink(missing_ok=True)
    if not valid:raise RuntimeError('No NSIS mirror returned the pinned archive.\n'+'\n'.join(failures))
    with zipfile.ZipFile(archive) as source:
        for item in source.infolist():
            destination=(directory/item.filename).resolve()
            if directory.resolve() not in destination.parents:raise ValueError('Unsafe NSIS archive path.')
        source.extractall(directory)
    print(directory/('nsis-'+PIN['version']))

if __name__=='__main__':main()
