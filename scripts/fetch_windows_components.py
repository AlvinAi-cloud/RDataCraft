#!/usr/bin/env python3
"""Collect the pinned official WebView2 offline installer; never execute it here."""
import argparse
import hashlib
import json
import os
import shutil
from pathlib import Path
import subprocess
import urllib.request

ROOT=Path(__file__).resolve().parent.parent
PIN=json.loads((ROOT/'config/windows-components.json').read_text(encoding='utf-8'))

def verify(path):
    if hashlib.sha256(path.read_bytes()).hexdigest()!=PIN['webview2']['sha256']:
        raise ValueError('The WebView2 runtime differs from the reviewed Microsoft download.')
    if os.name=='nt':
        # Verify Authenticode trust as well as the reviewed content hash.
        environment=dict(os.environ,RDATACRAFT_VERIFY_FILE=str(path.resolve()))
        # Do not make Windows PowerShell 5 load PowerShell 7's module binaries.
        environment.pop('PSModulePath',None)
        script="$s=Get-AuthenticodeSignature -LiteralPath $env:RDATACRAFT_VERIFY_FILE; if($s.Status -ne 'Valid' -or $s.SignerCertificate.Subject -notmatch '(?:^|, )O=Microsoft Corporation(?:,|$)'){throw 'Microsoft signature verification failed'}"
        shell=shutil.which('pwsh.exe') or shutil.which('powershell.exe')
        if not shell:raise RuntimeError('PowerShell is required to verify the Microsoft runtime signature.')
        subprocess.run([shell,'-NoProfile','-NonInteractive','-Command',script],env=environment,check=True)
    return path

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'artifacts/release-tools/webview2/MicrosoftEdgeWebView2RuntimeInstallerX64.exe')
    args=parser.parse_args();path=args.output
    path.parent.mkdir(parents=True,exist_ok=True)
    if not path.exists():
        temporary=path.with_suffix('.download')
        try:
            urllib.request.urlretrieve(PIN['webview2']['url'],temporary)
            verify(temporary);temporary.replace(path)
        finally:temporary.unlink(missing_ok=True)
    verify(path);print(path)

if __name__=='__main__':main()
