import hashlib,json,os,pathlib,shutil,subprocess,sys
ROOT=pathlib.Path.cwd();installer=next((ROOT/'original').glob('*-setup.exe'))
expected=installer.with_suffix('.exe.sha256').read_text().split()[0]
assert hashlib.sha256(installer.read_bytes()).hexdigest()==expected
seven=pathlib.Path(os.environ['ProgramFiles'])/'7-Zip/7z.exe'
subprocess.run([str(seven),'x','-y',str(installer),'-o'+str(ROOT/'unpacked')],check=True)
parents=[p.parent for p in (ROOT/'unpacked').rglob('build-platform.json') if (p.parent/'RDataCraft.exe').is_file()]
assert len(parents)==1;bundle=parents[0]
# 7-Zip may expose NSIS plugins beside the app payload; these are setup-only.
shutil.rmtree(bundle/'$PLUGINSDIR',ignore_errors=True)
# Preserve the existing tested executable/runtime payload; add accompanying notices only.
code={p.relative_to(bundle).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in bundle.rglob('*') if p.is_file() and p.suffix.lower() in ['.exe','.dll'] and p.name!='Uninstall.exe'}
notices=bundle/'licenses/release-notices';notices.mkdir(parents=True,exist_ok=True)
for name in ['THIRD-PARTY-NOTICES.txt','SOURCE-ACCESS.txt']:shutil.copy2(ROOT/'release-inputs'/name,notices/name)
(bundle/'Uninstall.exe').unlink(missing_ok=True)
subprocess.run([sys.executable,'scripts/fetch_nsis.py'],check=True)
subprocess.run([sys.executable,'scripts/fetch_windows_components.py'],check=True)
nsis=ROOT/'artifacts/release-tools/nsis-3.13'
(ROOT/'dist').mkdir(exist_ok=True)
subprocess.run([sys.executable,'scripts/package_installers.py','--windows-bundle',str(bundle),'--makensis',str(nsis/'makensis.exe'),'--nsis-dir',str(nsis),'--webview-installer',str(ROOT/'artifacts/release-tools/webview2/MicrosoftEdgeWebView2RuntimeInstallerX64.exe')],check=True)
for name,digest in code.items():assert hashlib.sha256((bundle/name).read_bytes()).hexdigest()==digest
final=ROOT/'dist/RDataCraft-0.31-windows-x64-setup.exe'
subprocess.run(['pwsh','-NoProfile','-NonInteractive','-File','scripts/test_windows_installer.ps1','-Installer',str(final)],check=True)
installed=json.loads((ROOT/'artifacts/validation-installed-windows-0.31.json').read_text(encoding='utf-8-sig'))
audit=json.loads((ROOT/'artifacts/validation-windows-installer-0.31.json').read_text(encoding='utf-8-sig'))
assert installed['status']=='passed' and audit['status']=='passed'
report={'version':'0.31','file':final.name,'sha256':hashlib.sha256(final.read_bytes()).hexdigest(),'application_source':'a8c4bd73cbb55c6a186d5b4327fc69ba6b8b4e6b','assembly_commit':os.environ['GITHUB_SHA'],'installer':audit,'installed_R':installed,'code_preserved_from_tested_installer':expected,'signing':'unsigned'}
final.with_suffix('.exe.validation.json').write_text(json.dumps(report,indent=2)+'\n')
