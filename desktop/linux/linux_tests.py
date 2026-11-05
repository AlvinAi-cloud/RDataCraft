"""Installed Ubuntu desktop integration checks; synthetic studies only."""
import json,time
from pathlib import Path
from gi.repository import GLib

def run(app,window):
 folder=app.test_folder;folder.mkdir(parents=True,exist_ok=True);checks=[];started=time.monotonic();steps=[];position=0;checking=False;deadline=started+100;second=[None];second_open=[False]
 def record(label):checks.append(label)
 def fail(error):
  app.failed=True
  (folder/'validation.json').write_text(json.dumps(dict(version=__import__('rdatacraft').VERSION,status='failed',error=str(error),checks=checks),indent=2))
  for w in app.windows:w.shutdown();w.destroy()
  app.quit()
 def step(action,predicate,label):steps.append((action,predicate,label))
 def command(name):return lambda:window.command(name)
 step(lambda:None,"document.querySelector('.version-label')?.textContent.includes('v0.6') && document.getElementById('data_grid')!==null",'native window loads the installed interface')
 step(lambda:window.open_file(__import__('rdatacraft').BACKEND/'examples/RDataCraft examples.rdatacraft'),"document.getElementById('study_name').value==='RDataCraft examples' && document.querySelector('#data_grid tbody td')!==null && !document.documentElement.classList.contains('shiny-busy')",'opens a teaching study through the native bridge')
 step(command('figure'),"window.RDataCraftGraph?.ready()===true && !!document.querySelector('#figure svg.graph-interactive')",'bundled packages render an interactive graph')
 step(command('assistant'),"document.body.classList.contains('assistant-open') && !document.getElementById('assistant_panel').hidden && document.getElementById('assistant_connection')===null && document.getElementById('assistant_connection_summary')===null && document.getElementById('assistant_status').textContent.includes('AI → Accounts and Models')",'disconnected assistant points to the AI menu without a settings button')
 step(lambda:None,"(()=>{const a=document.getElementById('assistant_panel').getBoundingClientRect(),b=document.querySelector('.inspector').getBoundingClientRect();return b.width>0 && b.right<=a.left+2 && b.top<a.bottom;})()",'figure settings remain visible beside the assistant')
 step(command('inspector'),"document.body.classList.contains('inspector-hidden') && document.body.classList.contains('assistant-open')",'figure settings can be hidden independently')
 step(command('inspector'),"!document.body.classList.contains('inspector-hidden') && document.body.classList.contains('assistant-open')",'figure settings can be restored independently')
 step(command('assistant'),"!document.body.classList.contains('assistant-open')",'assistant closes independently')
 step(command('advanced'),"document.getElementById('r_run').closest('.tab-pane').classList.contains('active')",'Advanced R editor opens')
 step(lambda:window.js("document.getElementById('r_check_script').click()"),"document.getElementById('r_status').textContent.includes('Syntax valid')",'script check validates without executing')
 step(lambda:window.js("document.getElementById('r_run').click()"),"document.getElementById('r_status').textContent.includes('R success') && document.querySelector('#r_results img.r-result-figure')?.complete===true",'reviewed R returns a table and vector figure')
 def save():window.next_destination=folder/'saved-study.rdcraft';window.save(True)
 step(save,"document.getElementById('r_saved').selectize.items.length===1",'native save command dispatched')
 def finish():
  path=folder/'saved-study.rdcraft'
  if not path.exists():return True
  value=json.loads(path.read_text());assert value['app_version']=='0.6' and value['r_analyses'][0]['result']['status']=='success'
  if second[0] is None:second[0]=app.open_window(new=True);return True
  if not second[0].ready:return True
  if not second_open[0]:
   second[0].js("document.body.classList.contains('document-open')",lambda value,error:second_open.__setitem__(0,value is True));return True
  record('native atomic save retains the exact successful R record')
  assert second[0].engine.pid!=window.engine.pid;record('New study opens a separate native window with an independent R process')
  engine=window.engine;other_engine=second[0].engine
  window.shutdown();window.destroy();second[0].shutdown();second[0].destroy()
  assert engine.poll() is not None and other_engine.poll() is not None;record('closing windows stops their own R engines')
  (folder/'validation.json').write_text(json.dumps(dict(version='0.6',status='passed',native_window=True,embedded_webkit=True,external_browser_launched=False,engine_cleanup_verified=True,checks=checks),indent=2));app.quit();return False
 def tick():
  nonlocal position,checking,deadline
  if checking:return True
  if time.monotonic()>deadline:fail('Timed out: '+(steps[position][2] if position<len(steps) else 'native save'));return False
  if position>=len(steps):
   try:return finish()
   except Exception as error:fail(error);return False
  if not window.ready:return True
  action,predicate,label=steps[position];checking=True
  def evaluated(value,error):
   nonlocal position,checking,deadline
   checking=False
   if value is True:
    record(label);position+=1;deadline=time.monotonic()+90
    if position<len(steps):
     try:steps[position][0]()
     except Exception as error:fail(error)
  window.js(predicate,evaluated);return True
 GLib.timeout_add(250,tick)
