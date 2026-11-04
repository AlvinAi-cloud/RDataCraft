#!/usr/bin/env python3
"""Build an Ubuntu 24.04 amd64 .deb on Ubuntu, using its managed R 4.3 runtime."""
import json,os,platform,shutil,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
VERSION=json.loads((ROOT/'config/release.json').read_text())['version']
DEPENDENCIES=['libc6 (>= 2.39)','libstdc++6','libgcc-s1','r-base-core (>= 4.3.3)','r-base-core (<< 4.4)','r-recommended','python3','python3-gi','python3-gi-cairo','gir1.2-gtk-3.0','gir1.2-webkit2-4.1','xdg-utils','fonts-dejavu-core','libcurl4t64','libxml2','libfontconfig1','libfreetype6','libharfbuzz0b','libfribidi0','libpng16-16t64','libjpeg-turbo8','libtiff6','libcairo2','libssl3t64']

def main():
 if platform.system()!='Linux' or platform.machine()!='x86_64':raise SystemExit('Build the Ubuntu installer on an Ubuntu amd64 runner.')
 release=Path('/etc/os-release').read_text()
 if 'VERSION_ID="24.04"' not in release:raise SystemExit('This package targets Ubuntu 24.04 LTS.')
 version=subprocess.check_output(['/usr/bin/Rscript','--vanilla','-e','cat(as.character(getRversion()))'],text=True).strip()
 if not version.startswith('4.3.'):raise SystemExit('Build library packages against the matching Ubuntu R 4.3 engine.')
 stage=ROOT/'artifacts/linux-package';backend=stage/'opt/rdatacraft'
 if stage.exists():raise SystemExit('Use a clean Linux staging folder.')
 backend.mkdir(parents=True)
 for name in ['app.R','README.md','CONTRIBUTING.md','CODE_OF_CONDUCT.md','CONTRIBUTORS.md','CHANGELOG.md','WORKFLOWS.md','RELEASE.md','PLATFORM_SUPPORT.md','LICENSE','dependencies.csv','dependencies.lock.json','source-manifest.json']:
  shutil.copy2(ROOT/name,backend/name)
 for name in ['R','www','config','scripts','tests','examples','licenses','docs']:
  shutil.copytree(ROOT/name,backend/name,ignore=shutil.ignore_patterns('__pycache__','*.pyc','.DS_Store'))
 shutil.copytree(ROOT/'desktop/linux',backend/'desktop/linux')
 shutil.copytree(ROOT/'desktop/ai-helper',backend/'desktop/ai-helper',ignore=shutil.ignore_patterns('target','bin'))
 from build_ai import build
 ai=build(offline=True);shutil.copytree(ai,backend/'desktop/ai-helper/bin')
 shutil.copytree(ROOT/'runtime/library',backend/'runtime/library')
 native=[]
 for file in (backend/'runtime/library').rglob('*.so'):
  data=file.read_bytes()
  if data[:4]!=b'\x7fELF' or data[4]!=2 or int.from_bytes(data[18:20],'little')!=62:raise ValueError('Expected an amd64 ELF library: '+str(file))
  deps=subprocess.check_output(['ldd',str(file)],text=True)
  if 'not found' in deps:raise ValueError('Unresolved runtime library: '+str(file))
  native.append(file.relative_to(backend).as_posix())
 (backend/'build-platform.json').write_text(json.dumps(dict(version=VERSION,platform='Linux',architecture='x86_64',distribution='Ubuntu 24.04 LTS',r_runtime='Ubuntu-managed R 4.3',native_libraries=native),indent=2)+'\n')
 launcher=stage/'usr/bin/rdatacraft';launcher.parent.mkdir(parents=True)
 launcher.write_text('#!/bin/sh\nexport RDATACRAFT_BACKEND=/opt/rdatacraft\nexec /usr/bin/python3 /opt/rdatacraft/desktop/linux/rdatacraft.py "$@"\n');launcher.chmod(0o755)
 desktop=stage/'usr/share/applications/org.rdatacraft.desktop.desktop';desktop.parent.mkdir(parents=True)
 desktop.write_text('[Desktop Entry]\nType=Application\nName=RDataCraft\nComment=Scientific plotting and statistics powered by R\nExec=rdatacraft %F\nIcon=rdatacraft\nTerminal=false\nCategories=Education;Science;DataVisualization;\nMimeType=application/x-rdatacraft;\n')
 mime=stage/'usr/share/mime/packages/rdatacraft.xml';mime.parent.mkdir(parents=True)
 mime.write_text('<?xml version="1.0" encoding="UTF-8"?>\n<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info"><mime-type type="application/x-rdatacraft"><comment>RDataCraft study</comment><glob pattern="*.rdcraft"/><glob pattern="*.rdatacraft"/></mime-type></mime-info>\n')
 # Use the existing cross-platform artwork; SVG works at every desktop scale.
 icons=stage/'usr/share/icons/hicolor/scalable';(icons/'apps').mkdir(parents=True);(icons/'mimetypes').mkdir()
 (icons/'apps/rdatacraft.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128"><rect x="4" y="4" width="120" height="120" rx="25" fill="#247763"/><path d="M28 25v76h76M33 83l21-28 19 10 28-32" fill="none" stroke="white" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/></svg>')
 (icons/'mimetypes/application-x-rdatacraft.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128"><path d="M22 4h60l26 26v94H22z" fill="#f4f8f5" stroke="#247763" stroke-width="5"/><path d="M82 4v28h26M37 56v47h55M42 89l14-19 14 8 20-25" fill="none" stroke="#247763" stroke-width="5"/><text x="38" y="46" font-size="14" font-family="sans-serif" fill="#247763">RDC</text></svg>')
 control=stage/'DEBIAN';control.mkdir()
 (control/'control').write_text(f'Package: rdatacraft\nVersion: {VERSION}\nArchitecture: amd64\nMaintainer: RDataCraft contributors <58916151+AlvinAi-cloud@users.noreply.github.com>\nDepends: '+', '.join(DEPENDENCIES)+'\nSection: science\nPriority: optional\nHomepage: https://github.com/AlvinAi-cloud/RDataCraft\nDescription: R-powered scientific plotting and statistics\n Native GTK desktop workspace with editable tables, linked graphs and reviewed R analyses.\n')
 # No install-time code executes R scripts, launches the app or changes user studies.
 output=ROOT/'dist/RDataCraft-ubuntu-amd64.deb';output.parent.mkdir(exist_ok=True)
 for p in stage.rglob('*'):
  if not p.is_symlink():p.chmod(0o755 if p.is_dir() or p.stat().st_mode&0o111 else 0o644)
 subprocess.run(['dpkg-deb','--root-owner-group','--build',str(stage),str(output)],check=True)
 print(output)
if __name__=='__main__':main()
