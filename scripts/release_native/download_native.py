from pathlib import Path
import json,hashlib,subprocess,concurrent.futures
root=Path(__file__).parent
def archive_urls(r):
 urls=[r['url']]
 if r['url'].startswith('https://ftp.gnu.org/'):
  urls += [r['url'].replace('https://ftp.gnu.org/','https://mirrors.kernel.org/'),r['url'].replace('https://ftp.gnu.org/gnu/','https://ftpmirror.gnu.org/')]
 if 'curl.haxx.se/' in r['url']:urls.insert(0,r['url'].replace('curl.haxx.se','curl.se'))
 if 'downloads.sourceforge.net/' in r['url']:urls += [r['url'].replace('downloads.sourceforge.net','master.dl.sourceforge.net'),r['url'].replace('downloads.sourceforge.net','cytranet.dl.sourceforge.net')]
 # HTTPS mirrors listed by GnuPG itself; every response must match the existing pin.
 # https://www.gnupg.org/download/mirrors.html
 if r['url'].startswith('https://gnupg.org/ftp/gcrypt/'):
  suffix=r['url'].split('/ftp/gcrypt/',1)[1]
  urls += ['https://mirrors.dotsrc.org/gcrypt/'+suffix,
           'https://www.mirrorservice.org/sites/ftp.gnupg.org/gcrypt/'+suffix]
 return urls

def fetch(r,out):
 p=out/r['archive'];urls=archive_urls(r)
 if not p.exists():
  partial=p.with_suffix(p.suffix+'.part')
  for url in urls:
   run=subprocess.run(['curl','--fail','--silent','--show-error','--location','--connect-timeout','15','--max-time','150','--retry','1','-o',str(partial),url],capture_output=True)
   if run.returncode==0:
    if hashlib.sha256(partial.read_bytes()).hexdigest()!=r['sha256']:raise ValueError('Hash mismatch '+r['archive'])
    partial.replace(p);break
  else:raise RuntimeError('Download unavailable '+r['archive']+' '+str(urls))
 if hashlib.sha256(p.read_bytes()).hexdigest()!=r['sha256']:raise ValueError('Hash mismatch '+r['archive'])
 print('Verified',r['archive'],flush=True);return r
def main():
 d=json.loads((root/'native-archives.json').read_text())
 out=root.parents[1]/'artifacts/release-native/archives';out.mkdir(parents=True,exist_ok=True)
 d['archives']=[r for r in d['archives'] if not r['version'].endswith('-kernel')]
 fail=[]
 with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
  for future in concurrent.futures.as_completed([pool.submit(fetch,r,out) for r in d['archives']]):
   try:future.result()
   except Exception as e:fail.append(str(e));print('FAILED',e,flush=True)
 d['missing']=fail;(out.parent/'native-source-download-report.json').write_text(json.dumps(d,indent=2)+'\n')
 if fail:raise SystemExit('Native source downloads incomplete')
 print('All native archives verified')

if __name__=='__main__':main()
