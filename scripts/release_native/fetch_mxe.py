import urllib.request,pathlib,re,concurrent.futures
base='https://svn.r-project.org/R-dev-web/!svn/rvr/6768/trunk/WindowsBuilds/winutf8/ucrt3/toolchain_libs/mxe/'
root=pathlib.Path(__file__).resolve().parents[2]/'artifacts/release-native/mxe-6768';root.mkdir(parents=True,exist_ok=True)
def read(path):
 p=root/path
 if p.exists():return p.read_bytes()
 with urllib.request.urlopen(base+path,timeout=60) as r:data=r.read()
 p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data);return data
pending=['src/','plugins/','ext/','tools/'];files=['Makefile','README.md','LICENSE.md','00_README_R_MXE.md','settings.mk','mxe.github.mk','mxe.patch.mk','mxe.updates.mk']
while pending:
 path=pending.pop()
 with urllib.request.urlopen(base+path,timeout=60) as r:html=r.read().decode()
 for href in re.findall(r'href="([^"<>]+)"',html):
  if href.startswith(('/', '.', 'http:', 'https:', '?')):continue
  if href.endswith('/'):pending.append(path+href)
  else:files.append(path+href)
print('Collecting',len(files),'source recipe/build files',flush=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=10) as pool:list(pool.map(read,files))
print('Saved immutable Rtools45 MXE revision 6768',flush=True)

import json,hashlib
files=[(p.relative_to(root).as_posix(),hashlib.sha256(p.read_bytes()).hexdigest()) for p in sorted(root.rglob('*')) if p.is_file()]
assert len(files)==1328
assert hashlib.sha256(json.dumps(files,separators=(',',':')).encode()).hexdigest()=='fd305e3726df82e41646dd5c1e16caaae59d5fd41a90a0a551018f5b204e5260', 'MXE snapshot contents changed'
