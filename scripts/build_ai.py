#!/usr/bin/env python3
"""Build the bundled, Codex-independent AI service for the target desktop."""
import argparse, hashlib, json, os, platform, shutil, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent

def build(target=None,cargo=None,test=False,offline=False):
    cargo=cargo or os.environ.get('CARGO') or shutil.which('cargo')
    if not cargo:raise SystemExit('Building the bundled AI service requires the Rust toolchain. End users do not need Rust or Codex.')
    source=ROOT/'desktop/ai-helper'
    args=[str(cargo),'test' if test else 'build','--locked','--manifest-path',str(source/'Cargo.toml')]
    if target:args+=['--target',target]
    if not test:args+=['--release']
    if offline:args+=['--offline']
    def inventory():return {p.relative_to(source).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in source.rglob('*') if p.is_file() and not any(part in ('target','bin') for part in p.relative_to(source).parts)}
    before=inventory()
    environment=dict(os.environ)
    if platform.system()=='Darwin':environment['CARGO_PROFILE_RELEASE_STRIP']='false'
    windows_target=(target is not None and 'windows-msvc' in target) or (target is None and os.name=='nt')
    if windows_target:environment['RUSTFLAGS']=(environment.get('RUSTFLAGS','')+' -C target-feature=+crt-static').strip()
    subprocess.run(args,cwd=ROOT,env=environment,check=True)
    if inventory()!=before:raise SystemExit('AI source changed during compilation; rebuild the matching source.')
    if test:return None
    suffix='.exe' if (target and 'windows' in target) or (not target and os.name=='nt') else ''
    native=source/'target'
    if target:native=native/target
    binary=native/'release'/('rdatacraft-ai'+suffix)
    out=ROOT/'artifacts/ai-helper'/(target or platform.machine())
    out.mkdir(parents=True,exist_ok=True);shutil.copy2(binary,out/binary.name)
    if platform.system()=='Darwin' and not suffix:subprocess.run(['strip','-x',str(out/binary.name)],check=True)
    sources={p.relative_to(source).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in source.rglob('*') if p.is_file() and not any(part in ('target','bin') for part in p.relative_to(source).parts)}
    metadata=json.loads(subprocess.check_output([str(cargo),'metadata','--locked','--offline','--format-version','1','--manifest-path',str(source/'Cargo.toml')],cwd=ROOT,text=True))
    notice=out/'licenses/ai-service';notice.mkdir(parents=True,exist_ok=True)
    packages=[]
    for package in metadata['packages']:
        if package['name']=='rdatacraft-ai':continue
        packages.append({k:package.get(k) for k in ['name','version','license','repository','source']})
        parent=Path(package['manifest_path']).parent
        for entry in parent.iterdir():
            if entry.is_file() and entry.name.lower().startswith(('license','licence','copying','copyright','notice')):
                folder=notice/(package['name']+'-'+package['version']);folder.mkdir(exist_ok=True);shutil.copy2(entry,folder/entry.name)
    shutil.copy2(ROOT/'licenses/PlasmidCraft-AI-MIT.txt',notice/'PlasmidCraft-AI-MIT.txt')
    (notice/'dependencies.json').write_text(json.dumps(packages,indent=2)+'\n')
    (out/'build.json').write_text(json.dumps({'version':'0.31','target':target,'crt_static':windows_target,'binary':binary.name,'sha256':hashlib.sha256((out/binary.name).read_bytes()).hexdigest(),'source_files':sources},indent=2)+'\n')
    return out

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--target');p.add_argument('--cargo');p.add_argument('--test',action='store_true');p.add_argument('--offline',action='store_true');a=p.parse_args()
    result=build(a.target,a.cargo,a.test,a.offline)
    if result:print(result)
