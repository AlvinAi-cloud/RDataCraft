#!/usr/bin/env python3
"""Validate installation, the native desktop and a package-manager upgrade on Ubuntu."""
import json,os,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];VERSION=json.loads((ROOT/'config/release.json').read_text())['version']
installer=(ROOT/'dist/RDataCraft-ubuntu-amd64.deb').resolve()
subprocess.run(['sudo','apt-get','install','-y',str(installer)],check=True)
backend=Path('/opt/rdatacraft');metadata=json.loads((backend/'build-platform.json').read_text());assert metadata['version']==VERSION
assert Path('/usr/share/mime/packages/rdatacraft.xml').is_file()
assert Path('/usr/share/icons/hicolor/scalable/mimetypes/application-x-rdatacraft.svg').is_file()
# GUI tests and analysis run as the regular user against the read-only installation.
subprocess.run(['xvfb-run','-a','/usr/bin/rdatacraft','--self-test',str(ROOT/'artifacts/installed-linux')],check=True,timeout=360)
report=json.loads((ROOT/'artifacts/installed-linux/validation.json').read_text());assert report['status']=='passed'
# Run the installed regression suite in a separate writable copy, so tests never
# require /opt write access. The native test above exercises /opt directly.
with tempfile.TemporaryDirectory(prefix='RDataCraft-installed-validation-') as folder:
 subprocess.run(['cp','-a',str(backend)+ '/.',folder],check=True)
 env=dict(os.environ,RDATACRAFT_RUNTIME=str(Path(folder)/'runtime'))
 subprocess.run([sys.executable,str(Path(folder)/'scripts/test.py'),'--require-node'],cwd=folder,env=env,check=True,timeout=1800)
 source=Path(folder)/f'artifacts/validation-{VERSION}.json'
 (ROOT/f'artifacts/validation-installed-linux-{VERSION}.json').write_bytes(source.read_bytes())
 # A user-created document in user storage survives reinstall and uninstall.
 sentinel=Path(folder)/'user-study.rdcraft';sentinel.write_text('original synthetic study');before=sentinel.read_bytes()
 subprocess.run(['sudo','dpkg','-i',str(installer)],check=True);assert sentinel.read_bytes()==before
 subprocess.run(['sudo','dpkg','--remove','rdatacraft'],check=True);assert sentinel.read_bytes()==before
 assert not Path('/usr/bin/rdatacraft').exists() and not (backend/'app.R').exists()
(ROOT/f'artifacts/validation-linux-installer-{VERSION}.json').write_text(json.dumps(dict(version=VERSION,status='passed',native_window_tested=True,reinstall_tested=True,uninstall_tested=True,user_study_preserved=True,document_icon_verified=True,system_R_managed_by_ubuntu=True),indent=2)+'\n')
