"""Assemble reviewed release sources/notices and transfer verified Actions artifacts."""
import concurrent.futures,hashlib,json,os,pathlib,re,shutil,subprocess,sys,tarfile,zipfile
HERE=pathlib.Path(__file__).resolve().parent
ROOT=HERE.parent
REPO='AlvinAi-cloud/RDataCraft'
APP_SHA='a8c4bd73cbb55c6a186d5b4327fc69ba6b8b4e6b'
MAC_RUN=40152512569
WIN_RUN=40151056721
OUT=ROOT/'release-material'
def digest(p):
 h=hashlib.sha256()
 with p.open('rb') as s:
  for chunk in iter(lambda:s.read(1024*1024),b''):h.update(chunk)
 return h.hexdigest()
def api(path):return json.loads(subprocess.check_output(['gh','api',path],text=True))
def artifact(run,name,dest):
 records=api(f'repos/{REPO}/actions/runs/{run}/artifacts?per_page=100')['artifacts']
 matches=[r for r in records if r['name']==name and not r['expired']]
 assert len(matches)==1,(run,name)
 record=matches[0];dest=pathlib.Path(dest);dest.mkdir(parents=True,exist_ok=True)
 z=dest.with_suffix('.zip')
 with z.open('wb') as s:subprocess.run(['gh','api',f"repos/{REPO}/actions/artifacts/{record['id']}/zip"],stdout=s,check=True)
 assert record['digest']=='sha256:'+digest(z),'Artifact digest mismatch'
 with zipfile.ZipFile(z) as archive:
  for info in archive.infolist():
   path=pathlib.PurePosixPath(info.filename)
   assert not path.is_absolute() and '..' not in path.parts and (info.external_attr>>16)&0o170000 != 0o120000
  archive.extractall(dest)
 return record

def native_notices(files,out):
 # Preserve notices from every collected source distribution, including vendored subcomponents.
 with out.open('w',encoding='utf-8') as stream:
  stream.write('RDataCraft v0.31: bundled dependency copyright and license notices\n\nApplication source: GPL-3.0. Individual dependencies retain their own licenses.\nSource/build material: https://github.com/AlvinAi-cloud/RDataCraft/releases/tag/v0.31\n\n')
  for p in sorted(files):
   lzip=None
   try:
    if p.name.endswith('.tar.lz'):
     lzip=subprocess.Popen(['lzip','-dc',str(p)],stdout=subprocess.PIPE)
     archive=tarfile.open(fileobj=lzip.stdout,mode='r|')
    else:archive=tarfile.open(p,'r:*')
    with archive:
     for info in archive:
      n=pathlib.PurePosixPath(info.name)
      if not info.isfile() or info.size>2_000_000:continue
      if not (re.match(r'^(copying|licen[cs]e|notice|copyright|exception)([._-].*)?$',n.name.lower()) or any(q.lower() in ('licenses','licences') for q in n.parts[:-1])):continue
      data=archive.extractfile(info).read()
      if b'\0' in data:continue
      stream.write('\n'+'='*72+'\n'+p.name+' :: '+info.name+'\n'+'='*72+'\n')
      stream.write(data.decode('utf-8','replace')+'\n')
   finally:
    if lzip:
     lzip.stdout.close();assert lzip.wait()==0

def collect():
 OUT.mkdir(exist_ok=True)
 subprocess.run([sys.executable,str(HERE/'download_native.py')],check=True)
 subprocess.run([sys.executable,str(HERE/'fetch_mxe.py')],check=True)
 # MAC workflow builds/tests exactly APP_SHA; do not substitute an untested local package.
 subprocess.run(['gh','run','watch',str(MAC_RUN),'--repo',REPO,'--exit-status','--interval','30'],check=True)
 for run in (MAC_RUN,WIN_RUN):
  d=api(f'repos/{REPO}/actions/runs/{run}')
  assert d['conclusion']=='success' and d['repository']['full_name']==REPO
 assert api(f'repos/{REPO}/actions/runs/{WIN_RUN}')['head_sha']==APP_SHA
 inputs=OUT/'inputs';inputs.mkdir(exist_ok=True)
 for arch in ['arm64','x86_64']:
  artifact(MAC_RUN,'v031-sources-macos-'+arch,inputs/('macos-sources-'+arch))
  artifact(MAC_RUN,'rdatacraft-validation-macos-'+arch,inputs/('macos-reports-'+arch))
 artifact(WIN_RUN,'rdatacraft-validation-windows-x64',inputs/'windows-reports')
 sources=OUT/'sources';sources.mkdir(exist_ok=True)
 records={}
 for p in inputs.rglob('source-manifest.json'):
  d=json.loads(p.read_text());assert not d.get('missing')
  for r in d['archives']:
   key=r['archive']
   assert key not in records or records[key]['sha256']==r['sha256']
   records[key]=r
 def get(r):
  p=sources/r['archive'];existing=list(inputs.glob('macos-sources-*/downloads/sources/'+p.name))
  if existing:shutil.copy2(existing[0],p)
  else:
   urls=[r['source'],r['source'].replace('https://cran.r-project.org/','https://cloud.r-project.org/')]
   for url in urls:
    rc=subprocess.run(['curl','--fail','--silent','--show-error','--location','--retry','2','--max-time','180','-o',str(p),url]).returncode
    if rc==0:break
   else:raise RuntimeError('R/package source download failed: '+p.name)
  assert digest(p)==r['sha256'],p.name
 with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:list(pool.map(get,records.values()))
 (sources/'R-package-source-manifest.json').write_text(json.dumps(list(records.values()),indent=2)+'\n')
 for folder in inputs.glob('macos-sources-*/downloads/native-sources'):
  for p in folder.iterdir():
   dest=sources/p.name
   if dest.exists():assert digest(p)==digest(dest)
   else:shutil.copy2(p,dest)
 for p in (HERE/'native-material/archives').iterdir():shutil.copy2(p,sources/p.name)
 shutil.copytree(HERE/'native-material/mxe-6768',sources/'Rtools45-MXE-r6768')
 shutil.copy2(HERE/'native-source-download-report.json',sources/'native-source-manifest.json')
 shutil.copytree(ROOT/'licenses',sources/'application-licenses')
 shutil.copytree(HERE,sources/'release-assembly',ignore=shutil.ignore_patterns('native-material','__pycache__','*.zip'))
 shutil.copytree(ROOT/'desktop/ai-helper',sources/'ai-helper',ignore=shutil.ignore_patterns('target','bin'))
 with (sources/'application-source.tar.gz').open('wb') as stream:
  subprocess.run(['gh','api',f'repos/{REPO}/tarball/{os.environ["GITHUB_SHA"]}'],stdout=stream,check=True)
 subprocess.run(['cargo','vendor','--locked','--versioned-dirs','--manifest-path',str(ROOT/'desktop/ai-helper/Cargo.toml'),str(sources/'rust-vendor')],stdout=(sources/'cargo-vendor-config.toml').open('w'),check=True)
 (sources/'README-SOURCE.txt').write_text('''RDataCraft v0.31 source and build material

Application/Rust/Windows host source and release packaging scripts are in application-source.tar.gz.
R and R package source archives are matched by version/checksum to all three tested inventories.
The native sources are a superset covering libraries identified in packaged runtimes, with R Mac recipes at commit 31e34aad7ae160981913d9f30426bf5529edd60e, Rtools45 MXE recipes/patches at SVN r6768, and the official R Mac GCC 14.2 Darwin r2.1 source release. OpenMP source/build material and NSIS source are included. Native input sources preserve all upstream licenses and notices.

Build the R runtime/packages using their included sources and upstream recipes. R includes its Installation and Administration manual. Windows instructions: https://developer.r-project.org/WindowsBuilds/R-4.6/howto.html . Mac recipes include build.sh and configuration fragments; the Mac runtime configure flags are in its etc/Makeconf. Rtools sources include Makefile, settings and GCC14 plugin patches. R package archives retain their configure/Makevars instructions. These recipes permit rebuilding/relinking the native dependencies; bit-identical reproduction of upstream CRAN binaries has not been established.

Build the app using scripts/bootstrap.py, scripts/install.R, scripts/build_ai.py, scripts/build_desktop.py or scripts/build_windows.py. Rust dependencies are included in rust-vendor, with an example source replacement config in cargo-vendor-config.toml (adjust its directory to rust-vendor). Tests: scripts/test.py and the native platform validation workflow. Repackage and test via release031/final.yml.

The release assembly adds dependency notices and source-access instructions to the previously tested app payloads, preserves their executable code, and retests the final installers. Mac code signatures are ad-hoc; Windows binaries are unsigned. Native build-provenance review is documented separately; this archive does not claim a bit-for-bit upstream build certification.
''')
 # Produce standalone accompanying notices and include them within the installed apps.
 notices=OUT/'THIRD-PARTY-NOTICES.txt';native_notices([p for p in sources.iterdir() if p.is_file() and ('.tar.' in p.name or p.name.endswith('.tgz')) and p.name!='application-source.tar.gz'],notices)
 (OUT/'SOURCE-ACCESS.txt').write_text('RDataCraft v0.31 source, build instructions, licenses and test reports:\nhttps://github.com/AlvinAi-cloud/RDataCraft/releases/tag/v0.31\n\nRDataCraft is GPL-3.0. Dependency licenses remain intact. See THIRD-PARTY-NOTICES.txt and the source bundle provided with the release.\n')
 with tarfile.open(OUT/'RDataCraft-0.31-sources.tar.gz','w:gz',compresslevel=6) as t:t.add(sources,arcname='RDataCraft-0.31-sources')
 for p in list(OUT.glob('*.tar.gz')):
  p.with_suffix(p.suffix+'.sha256').write_text(digest(p)+'  '+p.name+'\n')
 print('Release sources and notices ready',flush=True)

if __name__=='__main__':
 if sys.argv[1]=='collect':collect()
 elif sys.argv[1]=='artifact':artifact(int(sys.argv[2]),sys.argv[3],sys.argv[4])
