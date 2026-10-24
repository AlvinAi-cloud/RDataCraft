#!/usr/bin/env python3
"""Create a self-contained local browser workspace on the target OS/CPU.
R and compiled R packages must come from this same platform and architecture.
"""
import argparse, hashlib, json, os, platform, shutil, subprocess, zipfile, struct, re
from pathlib import Path
from runtime_inventory import manifest as runtime_manifest, write_notices
ROOT=Path(__file__).resolve().parent.parent
VERSION='0.3'

def portable_arch(system, arch):
    arch={'amd64':'x86_64','x64':'x86_64','aarch64':'arm64'}.get(arch.lower(),arch.lower())
    if system not in ['Darwin','Windows'] or arch not in (['x86_64'] if system=='Windows' else ['arm64','x86_64']):
        raise ValueError('Choose Darwin arm64/x86_64 or Windows x86_64; Windows ARM is not packaged.')
    return arch

def verify_windows_runtime(home, library):
    count=0
    for root in [home,library]:
        for f in root.rglob('*'):
            if f.suffix.lower() not in ['.exe','.dll']:continue
            data=f.read_bytes()
            try:
                offset=struct.unpack_from('<I',data,0x3c)[0]
                valid=data[:2]==b'MZ' and data[offset:offset+4]==b'PE\0\0' and struct.unpack_from('<H',data,offset+4)[0]==0x8664
            except struct.error:valid=False
            if not valid:raise ValueError(f'Expected an x64 Windows executable: {f}')
            count+=1
    if not (home/'bin/x64/Rscript.exe').is_file() and not (home/'bin/Rscript.exe').is_file():raise ValueError('The Windows Rscript engine is missing.')
    packages=list(library.glob('*/DESCRIPTION'))
    if not packages:raise ValueError('The Windows package library is empty.')
    for desc in packages:
        text=desc.read_text(encoding='utf-8')
        built=re.search(r'^Built: (.+)$',text,re.M)
        if not built or not re.search(r';\s*windows\s*$',built[1]):raise ValueError(f'Expected a Windows-built R package: {desc.parent.name}')
        if 'darwin' in built[1].lower() or 'aarch64' in built[1].lower():raise ValueError(f'Wrong package architecture: {desc.parent.name}')
    return {'x64_pe_files':count,'windows_packages':len(packages)}

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--target',choices=['Darwin','Windows'],default=platform.system())
    ap.add_argument('--arch',default=platform.machine().lower())
    ap.add_argument('--runtime-root',type=Path,default=ROOT/'runtime')
    ap.add_argument('--r-home',type=Path,help='Windows R installation to bundle; otherwise query Rscript.')
    ap.add_argument('--output',type=Path)
    args=ap.parse_args();runtime=args.runtime_root.resolve()
    system=args.target
    try:arch=portable_arch(system,args.arch)
    except ValueError as error:raise SystemExit(str(error))
    cross=system!=platform.system()
    audit={}
    if system=='Windows':
        engine=os.environ.get('RDATACRAFT_RSCRIPT') or shutil.which('Rscript.exe') or shutil.which('Rscript')
        if not args.r_home and not engine:raise SystemExit('Rscript is required on the packaging host.')
        home=args.r_home.resolve() if args.r_home else Path(subprocess.check_output([engine,'--vanilla','-e',"cat(normalizePath(R.home(),winslash='/'))"],text=True).strip())
        try:audit=verify_windows_runtime(home,runtime/'library')
        except ValueError as error:raise SystemExit(str(error))
    elif system=='Darwin':
        arches=subprocess.check_output(['lipo','-archs',str(runtime/'R.framework/Resources/bin/exec/R')],text=True).split()
        if arch not in arches:raise SystemExit(f'Requested {arch}, but the R engine contains {arches}.')
    tag=f'{system.lower()}-{arch}'
    destination=(args.output or ROOT/'dist'/f'RDataCraft-{VERSION}-{tag}-portable').resolve()
    if destination.exists():raise SystemExit('Choose a new output folder; existing builds are never overwritten.')
    destination.mkdir(parents=True)
    for name in ['app.R','README.md','PLATFORM_SUPPORT.md','WORKFLOWS.md','RELEASE.md','LICENSE','CHANGELOG.md','dependencies.csv','dependencies.lock.json','source-manifest.json',
                 'Launch RDataCraft.cmd','Launch RDataCraft.ps1','Validate RDataCraft.cmd','Launch RDataCraft portable.command']:
        shutil.copy2(ROOT/name,destination/name)
    for name in ['R','www','config','scripts','examples','licenses','tests']:
        shutil.copytree(ROOT/name,destination/name,symlinks=True,ignore=shutil.ignore_patterns('__pycache__','*.pyc','.DS_Store'))
    if (ROOT/'.github').exists():shutil.copytree(ROOT/'.github',destination/'.github')
    (destination/'runtime').mkdir()
    if system=='Windows':
        shutil.copytree(home,destination/'runtime/R')
        shutil.copytree(runtime/'library',destination/'runtime/library')
        (destination/'Launch RDataCraft portable.command').unlink()
        for name in ['dependencies.csv','dependencies.lock.json','windows-packages.json']:
            if (runtime/name).exists():shutil.copy2(runtime/name,destination/name)
        inventory=runtime_manifest(home,runtime/'library','x86_64-w64-mingw32')
        (destination/'dependencies.lock.json').write_text(json.dumps(inventory,indent=2)+'\n')
        import csv
        with (destination/'dependencies.csv').open('w',newline='') as stream:
            writer=csv.DictWriter(stream,fieldnames=['package','version','license']);writer.writeheader();writer.writerows(inventory['packages'])
        write_notices(home,runtime/'library',destination/'licenses')
        for pkg in (runtime/'library').iterdir():
            if not pkg.is_dir():continue
            target=destination/'licenses/packages'/pkg.name;target.mkdir(parents=True,exist_ok=True)
            for f in pkg.rglob('*'):
                if f.is_file() and (f.name=='DESCRIPTION' or f.name.lower().startswith(('license','licence','copying','copyright','notice'))):
                    output=target/f.relative_to(pkg);output.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(f,output)
    elif system=='Darwin':
        subprocess.run(['ditto',str(runtime/'R.framework'),str(destination/'runtime/R.framework')],check=True)
        shutil.copytree(runtime/'library',destination/'runtime/library',symlinks=True)
        (destination/'Launch RDataCraft.cmd').unlink();(destination/'Launch RDataCraft.ps1').unlink();(destination/'Validate RDataCraft.cmd').unlink()
    else:
        raise SystemExit('Bundle packaging is configured for macOS and Windows; source can use an existing R elsewhere.')
    manifest={'version':VERSION,'platform':system,'architecture':arch,'interface':'local browser','engine':'bundled R',
              'status':'cross-assembled; Windows execution not tested on this host' if cross else 'built on target; consult validation report for tested workflows','binary_audit':audit}
    (destination/'build-platform.json').write_text(json.dumps(manifest,indent=2)+'\n')
    if (ROOT/'downloads/sources').is_dir():shutil.copytree(ROOT/'downloads/sources',destination/'downloads/sources')
    if (ROOT/'downloads/native-sources').is_dir():shutil.copytree(ROOT/'downloads/native-sources',destination/'downloads/native-sources')
    archive=Path(str(destination)+'.zip')
    if system=='Darwin':subprocess.run(['ditto','-c','-k','--sequesterRsrc','--keepParent',str(destination),str(archive)],check=True)
    else:
        with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
            for f in destination.rglob('*'):
                if f.is_file():z.write(f,Path(destination.name)/f.relative_to(destination))
    checksum=hashlib.sha256(archive.read_bytes()).hexdigest()
    archive.with_suffix('.zip.sha256').write_text(f'{checksum}  {archive.name}\n')
    print(archive)
if __name__=='__main__':main()
