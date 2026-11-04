#!/usr/bin/python3
"""Native Ubuntu GTK/WebKit host; one local R process per study window."""
import argparse,json,os,signal,socket,subprocess,sys,tempfile,threading,time,urllib.request
from pathlib import Path
import gi
gi.require_version('Gtk','3.0');gi.require_version('WebKit2','4.1')
from gi.repository import Gtk,Gio,GLib,WebKit2
BACKEND=Path(os.environ.get('RDATACRAFT_BACKEND',Path(__file__).resolve().parents[2]))
VERSION=json.loads((BACKEND/'config/release.json').read_text())['version']

class Window(Gtk.ApplicationWindow):
 def __init__(self,app,path=None,new=False):
  super().__init__(application=app,title='RDataCraft');self.app=app;self.path=None;self.dirty=False;self.ready=False;self.new=new;self.initial=path;self.stopping=False;self.saving_close=False;self.force_save=False;self.downloads={};self.next_destination=None
  self.set_default_size(1320,870);self.connect('delete-event',self.on_close)
  self.temp=tempfile.TemporaryDirectory(prefix='RDataCraft-window-');self.folder=Path(self.temp.name)
  self.log=open(self.folder/'engine.log','wb');self.started=time.monotonic()
  with socket.socket() as sock:sock.bind(('127.0.0.1',0));self.port=sock.getsockname()[1]
  self.endpoint=f'http://127.0.0.1:{self.port}/'
  box=Gtk.Box(orientation=Gtk.Orientation.VERTICAL);self.add(box);bar=Gtk.MenuBar();box.pack_start(bar,False,False,0)
  def menu(label,items):
   item=Gtk.MenuItem(label=label);sub=Gtk.Menu();item.set_submenu(sub);bar.append(item)
   for text,callback in items:
    button=Gtk.MenuItem(label=text);button.connect('activate',lambda _,f=callback:f());sub.append(button)
  menu('File',[('New study',lambda:app.open_window(new=True)),('Open study…',self.open_dialog),('Import data…',lambda:self.open_dialog(True)),('Save',self.save),('Save As…',lambda:self.save(True)),('Close window',self.close)])
  menu('Edit',[(x,lambda c=x:self.web.execute_editing_command(c)) for x in ['Undo','Redo','Cut','Copy','Paste','SelectAll']])
  menu('View',[(label,lambda c=command:self.command(c)) for label,command in [('Data table','data'),('Analysis','analysis'),('Graph','figure'),('Figure settings','inspector'),('Figure layout','layout')]])
  menu('AI',[('AI Assistant',lambda:self.command('assistant')),('Accounts and Models…',lambda:self.command('ai-accounts'))])
  menu('Help',[('Examples & analysis guide',lambda:self.command('help')),('Check for Updates…',lambda:self.command('check-updates')),('About RDataCraft',lambda:self.alert(f'RDataCraft v{VERSION}\nScientific plotting and statistics powered by R.\nGPL-3.0; notices included with the app.'))])
  self.context=WebKit2.WebContext.new_ephemeral();manager=WebKit2.UserContentManager();manager.connect('script-message-received::rdatacraft',self.on_message);manager.register_script_message_handler('rdatacraft')
  self.web=WebKit2.WebView(web_context=self.context,user_content_manager=manager)
  self.web.connect('decide-policy',self.policy);self.web.connect('create',self.create_external);self.context.connect('download-started',self.on_download)
  self.web.connect('permission-request',lambda _,request: (request.deny() or True))
  box.pack_start(self.web,True,True,0);self.show_all()
  env=dict(os.environ,RDATACRAFT_DESKTOP='1',RDATACRAFT_NATIVE_HOST='gtk',RDATACRAFT_PARENT_PID=str(os.getpid()),RDATACRAFT_RUNTIME=str(BACKEND/'runtime'),R_LIBS_USER=str(BACKEND/'runtime/library'))
  # Keep system R and its recommended packages under Ubuntu package management.
  env.pop('R_HOME',None);env.pop('RHOME',None)
  if app.test_folder:
   env['RDATACRAFT_USER_LIBRARY']=str(app.test_folder/'optional-library');env['RDATACRAFT_AI_PROFILE']=str(app.test_folder/'ai-profile')
  self.engine=subprocess.Popen(['/usr/bin/R','--vanilla','--slave','--file='+str(BACKEND/'scripts/run.R'),'--args','--no-browser','--port='+str(self.port)],cwd=BACKEND,env=env,stdin=subprocess.DEVNULL,stdout=self.log,stderr=subprocess.STDOUT,start_new_session=True)
  threading.Thread(target=self.wait_engine,daemon=True).start()
 def trusted(self,url):return isinstance(url,str) and url.startswith(self.endpoint)
 def wait_engine(self):
  while not self.stopping and time.monotonic()-self.started<90:
   if self.engine.poll() is not None:break
   try:
    with urllib.request.urlopen(self.endpoint,timeout=1) as response:
     if response.status==200:GLib.idle_add(self.web.load_uri,self.endpoint);return
   except Exception:time.sleep(.2)
  if not self.stopping:GLib.idle_add(self.alert,'The local R engine did not start. Reinstall RDataCraft or inspect '+str(self.folder/'engine.log'))
 def js(self,code,callback=None):
  def done(view,result,*_):
   try:value=view.evaluate_javascript_finish(result);value=json.loads(value.to_json(0)) if value and not value.is_undefined() else None
   except Exception as error:
    if callback:callback(None,error)
    return
   if callback:callback(value,None)
  self.web.evaluate_javascript(code,-1,None,None,None,done,None)
 def send(self,value):self.js('window.RDataCraftDesktop.receive('+json.dumps(value)+')')
 def command(self,name):self.send(dict(type='command',name=name))
 def policy(self,view,decision,kind):
  if kind in (WebKit2.PolicyDecisionType.NAVIGATION_ACTION,WebKit2.PolicyDecisionType.NEW_WINDOW_ACTION):
   action=decision.get_navigation_action();url=action.get_request().get_uri()
   if self.trusted(url):decision.use();return True
   decision.ignore()
   if action.is_user_gesture() and url.startswith(('https://','http://')):Gio.AppInfo.launch_default_for_uri(url,None)
   return True
  if kind==WebKit2.PolicyDecisionType.RESPONSE:
   url=decision.get_request().get_uri()
   if self.trusted(url) and '/download/' in url:decision.download();return True
  return False
 def create_external(self,view,action):
  url=action.get_request().get_uri()
  if action.is_user_gesture() and url.startswith(('https://','http://')) and not self.trusted(url):Gio.AppInfo.launch_default_for_uri(url,None)
  return None
 def on_message(self,manager,result):
  if not self.trusted(self.web.get_uri()):return
  try:
   body=json.loads(result.get_js_value().to_json(0));kind=body.get('type')
   if kind=='ready' and not self.ready:
    self.ready=True
    if self.initial:self.open_file(self.initial)
    elif self.new:self.send(dict(type='new'))
   elif kind=='document':
    self.dirty=bool(body.get('dirty'));self.path=body.get('path') or None;self.set_title((body.get('name') or 'Untitled study')+' — RDataCraft')
   elif kind=='command':
    name=body.get('name')
    if name=='new':self.app.open_window(new=True)
    elif name=='open':self.open_dialog()
    elif name=='import':self.open_dialog(True)
   elif kind=='vector':self.send(dict(type='vector-result',ok=False,message='On Ubuntu, export SVG or PDF to transfer a vector figure.'))
  except (ValueError,TypeError):return
 def open_dialog(self,importing=False):
  dialog=Gtk.FileChooserDialog(title='Import data' if importing else 'Open study',transient_for=self,action=Gtk.FileChooserAction.OPEN);dialog.add_buttons('Cancel',Gtk.ResponseType.CANCEL,'Open',Gtk.ResponseType.OK)
  if dialog.run()==Gtk.ResponseType.OK:
   path=dialog.get_filename();dialog.destroy()
   if importing or not self.dirty:self.open_file(path)
   else:self.app.open_window(path=path)
  else:dialog.destroy()
 def open_file(self,path):
  path=str(Path(path).resolve());extension=Path(path).suffix.lower();kind='prism' if extension in ('.prism','.pzfx','.pzf') else 'import' if extension in ('.csv','.tsv','.txt','.xlsx') else 'open';self.send(dict(type=kind,path=path))
 def save(self,save_as=False):self.force_save=save_as;self.command('save')
 def on_download(self,context,download):
  if not self.trusted(download.get_request().get_uri()):download.cancel();return
  state=dict(temp=None,destination=None,project=False,failed=False);self.downloads[download]=state
  def destination(item,suggested):
   name=Path(suggested).name;state['project']=Path(name).suffix.lower() in ('.rdcraft','.rdatacraft')
   target=self.next_destination;self.next_destination=None
   if target is None and state['project'] and self.path and not self.force_save:target=self.path
   self.force_save=False
   if target is None:
    dialog=Gtk.FileChooserDialog(title='Save study' if state['project'] else 'Export file',transient_for=self,action=Gtk.FileChooserAction.SAVE);dialog.set_do_overwrite_confirmation(True);dialog.set_current_name(name);dialog.add_buttons('Cancel',Gtk.ResponseType.CANCEL,'Save',Gtk.ResponseType.OK)
    if dialog.run()==Gtk.ResponseType.OK:target=dialog.get_filename()
    dialog.destroy()
   if target is None:self.saving_close=False;item.cancel();return True
   try:
    state['destination']=Path(target).resolve();fd,temporary=tempfile.mkstemp(prefix='.rdatacraft-',suffix='.tmp',dir=state['destination'].parent);os.close(fd);state['temp']=Path(temporary);item.set_allow_overwrite(True);item.set_destination(state['temp'].as_uri())
   except OSError:
    self.saving_close=False;item.cancel();self.alert('This location is not writable. Choose Save As and select a folder in your home directory.')
   return True
  def failed(item,error):state['failed']=True;self.saving_close=False
  def finished(item):
   try:
    if state['temp'] and not state['failed']:
     os.replace(state['temp'],state['destination'])
     if state['project']:self.send(dict(type='saved',path=str(state['destination'])))
     if self.saving_close:self.dirty=False;self.shutdown();self.destroy()
   except OSError as error:self.saving_close=False;self.alert(str(error))
   finally:
    if state['temp']:state['temp'].unlink(missing_ok=True)
    self.downloads.pop(item,None)
  download.connect('decide-destination',destination);download.connect('failed',failed);download.connect('finished',finished)
 def alert(self,text):
  dialog=Gtk.MessageDialog(transient_for=self,modal=True,message_type=Gtk.MessageType.INFO,buttons=Gtk.ButtonsType.OK,text=text);dialog.run();dialog.destroy()
 def on_close(self,*_):
  if self.dirty:
   dialog=Gtk.MessageDialog(transient_for=self,modal=True,message_type=Gtk.MessageType.QUESTION,text='Save changes before closing?');dialog.add_buttons('Cancel',Gtk.ResponseType.CANCEL,'Don’t save',Gtk.ResponseType.NO,'Save',Gtk.ResponseType.YES);response=dialog.run();dialog.destroy()
   if response==Gtk.ResponseType.CANCEL:return True
   if response==Gtk.ResponseType.YES:self.saving_close=True;self.save();return True
  self.shutdown();return False
 def shutdown(self):
  if self.stopping:return
  self.stopping=True
  for item in list(self.downloads):item.cancel()
  if self.engine.poll() is None:
   try:os.killpg(self.engine.pid,signal.SIGTERM);self.engine.wait(timeout=5)
   except (ProcessLookupError,subprocess.TimeoutExpired):
    try:os.killpg(self.engine.pid,signal.SIGKILL);self.engine.wait(timeout=2)
    except (ProcessLookupError,subprocess.TimeoutExpired):pass
  self.log.close();self.temp.cleanup()

class App(Gtk.Application):
 def __init__(self,files,test_folder=None):
  super().__init__(application_id='org.rdatacraft.desktop',flags=Gio.ApplicationFlags.NON_UNIQUE);self.files=files;self.test_folder=test_folder;self.windows=[];self.failed=False
 def do_activate(self):
  for path in self.files or [None]:self.open_window(path=path)
  if self.test_folder:
   from linux_tests import run
   run(self,self.windows[0])
 def open_window(self,**kwargs):
  window=Window(self,**kwargs);self.windows.append(window);return window
 def do_shutdown(self):
  for window in self.windows:window.shutdown()
  Gtk.Application.do_shutdown(self)

if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--self-test',type=Path);parser.add_argument('files',nargs='*');args=parser.parse_args()
 app=App(args.files,args.self_test);app.run([sys.argv[0]]);sys.exit(1 if app.failed else 0)
