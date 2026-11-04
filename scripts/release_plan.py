#!/usr/bin/env python3
"""Explicit target-only rebuilds with original, verified platform provenance."""
import argparse,json,os,re,subprocess,urllib.request
from pathlib import Path
PRESERVED=('macos-x86_64','macos-arm64','windows-x64')
# These files cannot affect the scientific application or the Mac/Windows build
# inputs. Preserve exact source archives for both commits even for these changes.
REUSE_ONLY_PATHS={'.github/workflows/platform-builds.yml','config/release-reuse.json','scripts/release_plan.py','scripts/package_linux.py','scripts/test_linux_installer.py','scripts/release_assets.py','scripts/publish_release.py','tests/release_tools.py','RELEASE.md'}

def allowed_reuse_change(path):
 return path in REUSE_ONLY_PATHS or path.startswith('desktop/linux/')

def invariant_workflow_inputs(text):
 # Job selection may change for a targeted rebuild; the actual Mac and Windows
 # build/test steps, versions, architecture matrix and global defaults may not.
 header=text.split('jobs:\n',1)[0]
 header='\n'.join(line for line in header.splitlines() if line!='  actions: read')
 jobs={}
 for name in ('mac','windows'):
  match=re.search(r'^  '+name+r':\n(.*?)(?=^  [A-Za-z_][A-Za-z0-9_-]*:|\Z)',text,re.M|re.S)
  if not match:raise ValueError('Missing preserved platform workflow job: '+name)
  jobs[name]='\n'.join(line for line in match[1].splitlines() if not re.match(r'^    (needs|if):',line))
 return header,jobs

def load_reuse(root,version,verify_git=True):
 path=Path(root)/'config/release-reuse.json'
 if not path.exists():return None
 p=json.loads(path.read_text(encoding='utf-8'))
 # A plan cannot silently carry over to the next release.
 if p.get('version')!=version:return None
 if p.get('preserve')!=list(PRESERVED) or p.get('rebuild')!=['ubuntu-amd64'] or not re.fullmatch('[0-9a-f]{40}',str(p.get('commit',''))) or not re.fullmatch('[1-9][0-9]*',str(p.get('run_id',''))):raise ValueError('Invalid explicit Ubuntu-only release plan.')
 if verify_git:
  subprocess.run(['git','merge-base','--is-ancestor',p['commit'],'HEAD'],cwd=root,check=True,stdout=subprocess.DEVNULL)
  paths=subprocess.check_output(['git','diff','--name-only','-z',p['commit'],'HEAD'],cwd=root).decode().split('\0')
  forbidden=[name for name in paths if name and not allowed_reuse_change(name)]
  if forbidden:raise ValueError('Cannot preserve installers after shared application/build inputs changed: '+', '.join(forbidden))
  old_workflow=subprocess.check_output(['git','show',p['commit']+':.github/workflows/platform-builds.yml'],cwd=root,text=True)
  new_workflow=subprocess.check_output(['git','show','HEAD:.github/workflows/platform-builds.yml'],cwd=root,text=True)
  if invariant_workflow_inputs(old_workflow)!=invariant_workflow_inputs(new_workflow):raise ValueError('Cannot preserve installers after Mac/Windows workflow inputs changed.')
 return p

def expected_provenance(current,platform,plan=None):
 if plan and platform in plan['preserve']:return dict(version=current['version'],commit=plan['commit'],run_id=str(plan['run_id']))
 return current

def verify_report(record,current,platform,plan=None):
 expected=expected_provenance(current,platform,plan)
 if record.get('status')!='passed' or record.get('platform')!=platform or any(record.get(k)!=v for k,v in expected.items()):raise ValueError('Validation provenance differs for '+platform)
 # Real reports contain the native/source/installer gates. Synthetic fixtures
 # are handled in their isolated assembly tests; preservation always needs them.
 if plan and platform in plan['preserve']:
  reports=record.get('reports',{})
  required=['native','source']+(['installer'] if platform=='windows-x64' else [])
  if any(reports.get(k,{}).get('status')!='passed' or reports[k].get('version')!=current['version'] for k in required):raise ValueError('Preserved installer lacks its original required passing checks: '+platform)

def verify_prior_run(plan,repo,get_json):
 r=get_json(f'repos/{repo}/actions/runs/{plan["run_id"]}')
 if r.get('name')!='Native platform validation' or r.get('path')!='.github/workflows/platform-builds.yml' or r.get('head_sha')!=plan['commit'] or r.get('head_branch')!='main' or r.get('repository',{}).get('full_name')!=repo or r.get('event') not in ('push','workflow_dispatch') or r.get('status')!='completed':raise ValueError('Prior installer run does not match the declared main commit/repository.')
 jobs=get_json(f'repos/{repo}/actions/runs/{plan["run_id"]}/jobs?per_page=100')['jobs']
 needed={'mac (macos-15, arm64)','mac (macos-15-intel, x86_64)','windows'}
 passed={j['name'] for j in jobs if j.get('status')=='completed' and j.get('conclusion')=='success'}
 if not needed<=passed:raise ValueError('A preserved platform did not pass its original job.')

def github_json(path):
 token=os.environ.get('GH_TOKEN','');headers={'Accept':'application/vnd.github+json','User-Agent':'RDataCraft release validation'}
 if token:headers['Authorization']='Bearer '+token
 with urllib.request.urlopen(urllib.request.Request('https://api.github.com/'+path,headers=headers),timeout=30) as response:return json.load(response)

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--github-output',type=Path,required=True);args=parser.parse_args()
 root=Path(__file__).resolve().parents[1];version=json.loads((root/'config/release.json').read_text())['version'];plan=load_reuse(root,version)
 if plan:verify_prior_run(plan,os.environ['GITHUB_REPOSITORY'],github_json)
 values=dict(build_mac='false' if plan else 'true',build_windows='false' if plan else 'true',build_ubuntu='true',reuse_run=str(plan['run_id']) if plan else '')
 with args.github_output.open('a',encoding='utf-8') as output:
  for key,value in values.items():output.write(key+'='+value+'\n')
 print('Build only Ubuntu; preserve the three previously tested installers.' if plan else 'Build all four platforms.')
if __name__=='__main__':main()
