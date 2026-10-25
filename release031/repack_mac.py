import hashlib,json,pathlib,shutil,subprocess,sys
ROOT=pathlib.Path.cwd();arch=sys.argv[1];old=next((ROOT/'original').glob('*.dmg'));mount=ROOT/'mounted';mount.mkdir()
subprocess.run(['hdiutil','verify',str(old)],check=True)
subprocess.run(['hdiutil','attach','-readonly','-nobrowse','-mountpoint',str(mount),str(old)],check=True)
try:
 app=next(mount.glob('*.app'));dest=ROOT/'dist'/app.name;dest.parent.mkdir(exist_ok=True)
 subprocess.run(['ditto',str(app),str(dest)],check=True)
finally:subprocess.run(['hdiutil','detach',str(mount)],check=True)
notices=dest/'Contents/Resources/licenses/release-notices';notices.mkdir(parents=True,exist_ok=True)
for name in ['THIRD-PARTY-NOTICES.txt','SOURCE-ACCESS.txt']:shutil.copy2(ROOT/'release-inputs'/name,notices/name)
subprocess.run(['codesign','--force','--sign','-','--timestamp=none',str(dest)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(dest)],check=True)
subprocess.run([sys.executable,'scripts/package_installers.py','--mac-app',str(dest),'--arch',arch],check=True)
image=ROOT/'dist'/('RDataCraft-0.31-macos-'+arch+'.dmg')
subprocess.run([sys.executable,'scripts/test_macos_bundle.py','--dmg',str(image),'--output','artifacts/final-installed-mac'],check=True)
report=json.loads((ROOT/'artifacts/final-installed-mac/validation.json').read_text())
assert report['status']=='passed' and report['checks']==114
p=image.with_suffix('.dmg.validation.json');p.write_text(json.dumps({'version':'0.31','file':image.name,'sha256':hashlib.sha256(image.read_bytes()).hexdigest(),'application_source':'a8c4bd73cbb55c6a186d5b4327fc69ba6b8b4e6b','assembly_commit':__import__('os').environ['GITHUB_SHA'],'native':report,'signing':'ad-hoc; not Apple-notarized'},indent=2)+'\n')
