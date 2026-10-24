#!/usr/bin/env python3
"""Build a self-contained x64 Windows window host with the official .NET SDK."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent

def build(dotnet, output):
    output = output.resolve()
    if output.exists():
        raise SystemExit('Choose a new native-host output folder.')
    tools = ROOT/'artifacts/release-tools'
    environment = dict(os.environ, DOTNET_CLI_HOME=str(tools/'dotnet-home'),
                       NUGET_PACKAGES=str(tools/'nuget'), DOTNET_CLI_TELEMETRY_OPTOUT='1',
                       DOTNET_SKIP_FIRST_TIME_EXPERIENCE='1', DOTNET_GENERATE_ASPNET_CERTIFICATE='false')
    project = ROOT/'desktop/windows/RDataCraft.csproj'
    subprocess.run([str(dotnet), 'publish', str(project), '-c', 'Release', '-r', 'win-x64',
                    '--self-contained', 'true', '-o', str(output),
                    '-p:BaseIntermediateOutputPath='+str(tools/'windows-obj')+os.sep],
                   env=environment, check=True)
    # Preserve the Microsoft runtime and SDK notices in every native bundle.
    notice = output/'licenses/windows-host'; notice.mkdir(parents=True, exist_ok=True)
    nuget = tools/'nuget'
    for package in ['microsoft.web.webview2','microsoft.netcore.app.runtime.win-x64','microsoft.windowsdesktop.app.runtime.win-x64']:
        for version in (nuget/package).glob('*'):
            for path in version.rglob('*'):
                if path.is_file() and path.name.lower() in ['license','license.txt','license.md','notice.txt','thirdpartynotices.txt','thirdpartynotices.md','third-party-notices.txt']:
                    target=notice/package/path.relative_to(version); target.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(path,target)
    records={str(p.relative_to(output)):hashlib.sha256(p.read_bytes()).hexdigest() for p in output.rglob('*') if p.is_file()}
    (output/'windows-host-build.json').write_text(json.dumps({'version':'0.3','interface':'WinForms + WebView2','runtime':'self-contained .NET 10 win-x64','files':records},indent=2)+'\n')
    print(output)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dotnet',type=Path,default=Path(shutil.which('dotnet') or 'dotnet'))
    parser.add_argument('--output',type=Path,default=ROOT/'artifacts/windows-host')
    args=parser.parse_args()
    build(args.dotnet,args.output)
