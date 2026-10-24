const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
let checks=0;
const check=(value,label)=>{assert.ok(value,label);checks++;console.log('PASS:',label);};
function workspace(native=false,blocked=false){
  const opens=[],inputs=[],posts=[],alerts=[];
  const child={opener:{}};
  const window={location:{href:'http://127.0.0.1:54321/?previous=1#analysis'},addEventListener(){},
    open(...args){opens.push(args);return blocked?null:child;},alert(message){alerts.push(message);}};
  if(native)window.webkit={messageHandlers:{rdatacraft:{postMessage(body){posts.push(body);}}}};
  const $=value=>({on(){}}); // App DOM setup is unrelated to this command-path test.
  const sandbox={window,document:{},Shiny:{setInputValue(...args){inputs.push(args);}},$,URL,Date};
  vm.runInNewContext(fs.readFileSync('www/rdatacraft.js','utf8'),sandbox);
  return {window,child,opens,inputs,posts,alerts};
}
const browser=workspace();browser.window.RDataCraftDesktop.receive({type:'command',name:'new'});
check(browser.opens.length===1 && browser.opens[0][1]==='_blank','browser New Study opens a separate browsing context');
const target=new URL(browser.opens[0][0]);
check(target.origin==='http://127.0.0.1:54321' && target.searchParams.get('rdatacraft_new_study')==='1','new browser study uses the same local engine with its own new-session request');
check(!target.searchParams.has('previous') && !target.hash,'new browser study does not inherit stale navigation parameters');
check(browser.inputs.length===0 && browser.child.opener===null,'new browser window does not reset the current study or retain an opener link');
const blocked=workspace(false,true);blocked.window.RDataCraftDesktop.receive({type:'command',name:'new'});
check(blocked.alerts.length===1 && blocked.inputs.length===0,'blocked popups leave the current study intact and explain how to retry');
const native=workspace(true);native.window.RDataCraftDesktop.receive({type:'command',name:'new'});
check(native.opens.length===0 && native.posts.length===1 && native.posts[0].name==='new','native New Study is delegated to the Mac window coordinator');
console.log(checks,'window command checks passed.');
