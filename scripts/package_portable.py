#!/usr/bin/env python3
"""Create a self-contained local browser workspace on the target OS/CPU.
R and compiled R packages must come from this same platform and architecture.
"""
import argparse, hashlib, json, os, platform, shutil, subprocess, zipfile, struct, re
from pathlib import Path
from runtime_inventory import manifest as runtime_manifest, write_notices
from build_ai import build as build_ai
ROOT=Path(__file__).resolve().parent.parent
VERSION='0.31'

def portable_arch(system, arch):
    arch={'amd64':'x86_64','x64':'x86_64','aarch64':'arm64'}.get(arch.lower(),arch.lower())
    if system not in ['Darwin','Windows'] or arch not in (['x86_64'] if system=='Windows' else ['arm64','x86_64']):
        raise ValueError('Choose Darwin arm64/x86_64 or Windows x86_64; Windows ARM is not packaged.')
    return arch

def r_installer_file(path, home):
    """R's own installer maintenance program is not part of its x64 engine."""
    return path.parent == home and bool(re.fullmatch(r'unins\d+\.(exe|dat|msg|log)', path.name, re.I))

def verify_windows_runtime(home, library):
    count=0
    for root in [home,library]:
        for f in root.rglob('*'):
            if r_installer_file(f, home):continue
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

def verify_windows_host(host):
    """Refuse stale native builds or incomplete self-contained payloads."""
    metadata=json.loads((host/'windows-host-build.json').read_text(encoding='utf-8'))
    if metadata['version']!=VERSION or not metadata.get('source_files'):raise ValueError('Rebuild the matching native Windows host.')
    for name,digest in metadata['files'].items():
        file=(host/name).resolve()
        if host.resolve() not in file.parents or not file.is_file() or hashlib.sha256(file.read_bytes()).hexdigest()!=digest:
            raise ValueError('The native host payload differs from its build manifest: '+name)
    for name,digest in metadata['source_files'].items():
        file=ROOT/'desktop/windows'/name
        if file.parent!=ROOT/'desktop/windows' or not file.is_file() or hashlib.sha256(file.read_bytes()).hexdigest()!=digest:
            raise ValueError('The native Windows host source changed; rebuild before packaging: '+name)
    for name in ['RDataCraft.exe','RDataCraft.dll','coreclr.dll','hostfxr.dll','System.Private.CoreLib.dll','Microsoft.Web.WebView2.Core.dll','Microsoft.Web.WebView2.WinForms.dll','WebView2Loader.dll']:
        if not (host/name).is_file():raise ValueError('The self-contained native host is missing '+name)
    data=(host/'RDataCraft.exe').read_bytes();offset=struct.unpack_from('<I',data,0x3c)[0]
    if data[:2]!=b'MZ' or data[offset:offset+4]!=b'PE\0\0' or struct.unpack_from('<H',data,offset+4)[0]!=0x8664 or struct.unpack_from('<H',data,offset+24+68)[0]!=2:
        raise ValueError('The native Windows launcher must be an x64 GUI executable.')
    return {'native_host':'WinForms + WebView2','host_files':len(metadata['files']),'source_files':len(metadata['source_files'])}

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--target',choices=['Darwin','Windows'],default=platform.system())
    ap.add_argument('--arch',default=platform.machine().lower())
    ap.add_argument('--runtime-root',type=Path,default=ROOT/'runtime')
    ap.add_argument('--r-home',type=Path,help='Windows R installation to bundle; otherwise query Rscript.')
    ap.add_argument('--output',type=Path)
    ap.add_argument('--native-host',type=Path,help='Published self-contained Windows desktop host folder.')
    args=ap.parse_args();runtime=args.runtime_root.resolve()
    system=args.target
    if args.native_host and (system != 'Windows' or not (args.native_host/'RDataCraft.exe').is_file()):
        raise SystemExit('Choose a published Windows host containing RDataCraft.exe.')
    host_audit=verify_windows_host(args.native_host) if args.native_host else {}
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
    ai_target="x86_64-pc-windows-msvc" if system=="Windows" else ("aarch64-apple-darwin" if arch=="arm64" else "x86_64-apple-darwin")
    ai_output=build_ai(target=ai_target)
    destination.mkdir(parents=True)
    for name in ['app.R','README.md','PLATFORM_SUPPORT.md','WORKFLOWS.md','RELEASE.md','LICENSE','CHANGELOG.md','dependencies.csv','dependencies.lock.json','source-manifest.json',
                 'Launch RDataCraft.cmd','Launch RDataCraft.ps1','Validate RDataCraft.cmd','Launch RDataCraft portable.command']:
        shutil.copy2(ROOT/name,destination/name)
    for name in ['R','www','config','scripts','examples','licenses','tests']:
        shutil.copytree(ROOT/name,destination/name,symlinks=True,ignore=shutil.ignore_patterns('__pycache__','*.pyc','.DS_Store'))
    shutil.copytree(ROOT/'desktop/ai-helper',destination/'desktop/ai-helper',ignore=shutil.ignore_patterns('target','bin'))
    shutil.copytree(ai_output,destination/'desktop/ai-helper/bin',dirs_exist_ok=True)
    if (ROOT/'.github').exists():shutil.copytree(ROOT/'.github',destination/'.github')
    (destination/'runtime').mkdir()
    if system=='Windows':
        shutil.copytree(home,destination/'runtime/R',ignore=lambda folder,names:[n for n in names if r_installer_file(Path(folder)/n,home)])
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
    if args.native_host:
        shutil.copytree(args.native_host,destination,dirs_exist_ok=True)
        shutil.copytree(ROOT/'desktop/windows',destination/'desktop/windows',ignore=shutil.ignore_patterns('bin','obj'))
        audit.update(host_audit)
    manifest={'version':VERSION,'platform':system,'architecture':arch,'interface':'native Windows window (WebView2)' if args.native_host else 'local browser','engine':'bundled R',
              'status':'cross-assembled; Windows execution not tested on this host' if cross else 'built on target; consult validation report for tested workflows','binary_audit':audit}
    (destination/'build-platform.json').write_text(json.dumps(manifest,indent=2)+'\n')
    if (ROOT/'downloads/sources').is_dir():shutil.copytree(ROOT/'downloads/sources',destination/'downloads/sources')
    if (ROOT/'downloads/native-sources').is_dir():shutil.copytree(ROOT/'downloads/native-sources',destination/'downloads/native-sources')
    archive=Path(str(destination)+'.zip')
    if system=='Darwin':subprocess.run(['ditto','-c','-k','--sequesterRsrc','--keepParent',str(destination),str(archive)],check=True)
    else:
        with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,strict_timestamps=False) as z:
            for f in destination.rglob('*'):
                if f.is_file():z.write(f,Path(destination.name)/f.relative_to(destination))
    checksum=hashlib.sha256(archive.read_bytes()).hexdigest()
    archive.with_suffix('.zip.sha256').write_text(f'{checksum}  {archive.name}\n')
    print(archive)
if __name__=='__main__':main()
