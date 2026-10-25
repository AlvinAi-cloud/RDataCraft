"""Publish only the exact final installers whose checksums/native reports agree."""
import hashlib,json,os,pathlib,subprocess,tarfile
from assemble import artifact,api,REPO,APP_SHA
ROOT=pathlib.Path.cwd();assets=ROOT/'release-assets';assets.mkdir()
# The current release workflow's required package jobs must all have passed.
run=int(os.environ['GITHUB_RUN_ID']);jobs=api(f'repos/{REPO}/actions/runs/{run}/jobs?per_page=100')['jobs']
for name in ['sources','windows','mac (macos-15, arm64)','mac (macos-15-intel, x86_64)']:
 matches=[j for j in jobs if j['name']==name];assert len(matches)==1 and matches[0]['conclusion']=='success',name
for name in ['v031-final-macos-arm64','v031-final-macos-x86_64','v031-final-windows','v031-source-assets']:
 artifact(run,name,ROOT/'final-inputs'/name)
for pattern in ['*.dmg','*-setup.exe','*.validation.json','RDataCraft-0.31-sources.tar.gz','THIRD-PARTY-NOTICES.txt','SOURCE-ACCESS.txt']:
 for p in (ROOT/'final-inputs').rglob(pattern):
  q=assets/p.name;assert not q.exists();__import__('shutil').copy2(p,q)
expected={'RDataCraft-0.31-macos-arm64.dmg','RDataCraft-0.31-macos-x86_64.dmg','RDataCraft-0.31-windows-x64-setup.exe'}
assert {p.name for p in assets.iterdir() if p.suffix in ('.exe','.dmg')}==expected
reports=[]
for name in sorted(expected):
 p=assets/name;r=json.loads((assets/(name+'.validation.json')).read_text())
 assert r['file']==name and r['sha256']==hashlib.sha256(p.read_bytes()).hexdigest()
 if name.endswith('.dmg'):assert r['native']['status']=='passed' and r['native']['checks']==114
 else:
  assert r['installer']['status']=='passed' and r['installer']['extra_study_preserved'] and r['installer']['engine_cleanup_verified']
  assert r['installed_R']['status']=='passed' and sum(t['checks'] for t in r['installed_R']['tests'])==963
 reports.append(r)
summary={'version':'0.31','application_source':APP_SHA,'release_assembly_commit':os.environ['GITHUB_SHA'],'release_workflow':f'https://github.com/{REPO}/actions/runs/{run}','status':'passed','installers':reports,'signing':{'macOS':'ad-hoc; not notarized','Windows':'unsigned'},'limitations':['Live ChatGPT eligibility and paid provider requests have not been tested with real accounts.','Bit-identical reproduction of upstream CRAN dependency binaries has not been established.']}
(assets/'RDataCraft-0.31-validation.json').write_text(json.dumps(summary,indent=2)+'\n')
# SHA-256 checksums are for assets exactly as attached, after all repackaging/signing.
(assets/'RDataCraft-0.31-SHA256SUMS.txt').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n' for p in sorted(assets.iterdir())))
notes='''RDataCraft is an open-source scientific plotting and statistics app powered by R. It combines editable tables, linked graphs, curve fitting, PCA, layouts and reviewed Advanced R analysis in a desktop workspace.

### v0.31
- Direct AI account/provider connections: ChatGPT sign-in, OpenAI, Claude, Gemini and compatible API services, without a separate Codex installation.
- Improved Intel Mac Dock icon sizing.
- Bundled R and native desktop windows on Mac and Windows.
- Added dependency notices and matching source/build material.

### Downloads
- **Intel Mac:** `RDataCraft-0.31-macos-x86_64.dmg`
- **Apple Silicon:** `RDataCraft-0.31-macos-arm64.dmg`
- **Windows 10/11 x64:** `RDataCraft-0.31-windows-x64-setup.exe`

R and required packages are bundled. Choose the installer matching your computer. Verify downloads with `RDataCraft-0.31-SHA256SUMS.txt`.

### Validation and current limitations
These exact final installers were tested by GitHub Actions after dependency notices were added. Mac installers passed 114 native workflow checks each; their application source passed 1,003 source checks per architecture. Windows passed 963 installed R checks, 21 native desktop checks, installation/uninstallation, process cleanup, and preservation of a synthetic study during uninstall. The shared AI service passed 29 synthetic tests and 7 bridge checks on each platform. The attached validation report records the final installer hashes and workflow.

This is a **development preview**. Mac builds use ad-hoc signatures and are **not Apple-notarized**; Windows setup is **unsigned**. Operating-system trust warnings may appear. Trusted distribution signing is not configured. Live ChatGPT account eligibility and paid provider requests require user acceptance testing; data is sent to a provider only when the user chooses to use connected AI.

Application source is GPL-3.0; dependencies retain their respective licenses. `RDataCraft-0.31-sources.tar.gz` provides application/R/package sources, native library sources, build recipes/patches, Rust dependencies and build instructions. `THIRD-PARTY-NOTICES.txt` is also included in the installed apps. Historical upstream binary build provenance is recorded where available; bit-identical reproduction of upstream CRAN binaries is not claimed.
'''
body=ROOT/'release-notes.md';body.write_text(notes)
# Fail closed on an existing public release or any conflicting asset; never replace released bytes.
lookup=subprocess.run(['gh','api',f'repos/{REPO}/releases/tags/v0.31'],capture_output=True,text=True)
if lookup.returncode==0:
 existing=json.loads(lookup.stdout);assert existing['draft'] and not existing['assets'],'Existing release requires explicit reconciliation'
 release_id=existing['id']
else:
 assert '404' in lookup.stderr,'Could not establish release absence'
 payload={'tag_name':'v0.31','target_commitish':os.environ['GITHUB_SHA'],'name':'RDataCraft v0.31','body':notes,'draft':True,'prerelease':True}
 temp=ROOT/'draft-release.json';temp.write_text(json.dumps(payload));r=json.loads(subprocess.check_output(['gh','api','--method','POST',f'repos/{REPO}/releases','--input',str(temp)],text=True));release_id=r['id']
subprocess.run(['gh','release','upload','v0.31','--repo',REPO]+[str(p) for p in sorted(assets.iterdir())],check=True)
remote=api(f'repos/{REPO}/releases/{release_id}')
assert {a['name'] for a in remote['assets']}=={p.name for p in assets.iterdir()}
for a in remote['assets']:
 p=assets/a['name'];assert a['size']==p.stat().st_size and a['digest']=='sha256:'+hashlib.sha256(p.read_bytes()).hexdigest(),'Uploaded asset differs: '+a['name']
subprocess.run(['gh','api','--method','PATCH',f'repos/{REPO}/releases/{release_id}','-F','draft=false','-F','prerelease=true'],check=True)
print('Published https://github.com/'+REPO+'/releases/tag/v0.31',flush=True)
