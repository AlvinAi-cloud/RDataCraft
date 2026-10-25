#!/usr/bin/env python3
"""Exercise R -> bundled native service -> local mock provider, with no real accounts."""
import argparse,json,os,subprocess,tempfile,threading
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
class Provider(BaseHTTPRequestHandler):
    requests=[]
    def log_message(self,*args):pass
    def reply(self,value,status=200):
        body=json.dumps(value).encode();self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
    def do_GET(self):
        self.requests.append(('GET',self.path,self.headers.get('Authorization'),None))
        self.reply({'data':[{'id':'synthetic-model','display_name':'Synthetic text model'}]})
    def do_POST(self):
        value=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        self.requests.append(('POST',self.path,self.headers.get('Authorization'),value))
        self.reply({'choices':[{'finish_reason':'stop','message':{'content':json.dumps({'answer':'Synthetic native bridge answer','operations':[]})}}]})
p=argparse.ArgumentParser();p.add_argument('--helper',type=Path,required=True);args=p.parse_args()
server=ThreadingHTTPServer(('127.0.0.1',0),Provider);threading.Thread(target=server.serve_forever,daemon=True).start()
try:
    with tempfile.TemporaryDirectory(prefix='RDataCraft-AI-test-') as folder:
        environment=dict(os.environ,RDATACRAFT_AI_HELPER=str(args.helper.resolve()),RDATACRAFT_AI_PROFILE=folder,RDATACRAFT_AI_TEST_ENDPOINT=f'http://127.0.0.1:{server.server_port}/v1')
        runner=[str(ROOT/'scripts/rscript.sh')] if os.name!='nt' else [os.environ.get('RDATACRAFT_RSCRIPT','Rscript'),'--vanilla']
        subprocess.run(runner+['tests/ai_bridge.R'],cwd=ROOT,env=environment,check=True)
        posts=[r for r in Provider.requests if r[0]=='POST'];gets=[r for r in Provider.requests if r[0]=='GET']
        assert len(posts)==1 and len(gets)==1,'Only explicit discovery and Send contact the provider'
        assert all(r[2]=='Bearer synthetic-bridge-key' for r in Provider.requests),'API authentication reaches only the selected local mock endpoint'
        assert posts[0][3]['model']=='synthetic-model'
        assert 'user_request' in posts[0][3]['messages'][1]['content']
        print('PASS: provider saw only explicit discovery and Send, with the chosen model')
finally:server.shutdown();server.server_close()
