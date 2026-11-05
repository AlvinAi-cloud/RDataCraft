// Exercise assistant registration with Shiny's real handler-arity contract.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
let checks=0;const check=(value,label)=>{assert.ok(value,label);checks++;console.log('PASS:',label);};
const handlers={},inputs=[],posts=[];
const elements=new Map();const element=id=>{
 if(!elements.has(id))elements.set(id,{hidden:true,disabled:false,value:'',dataset:{},listeners:{},attributes:{},addEventListener(k,v){this.listeners[k]=v;},setAttribute(k,v){this.attributes[k]=v;},focus(){this.focused=true;},dispatchEvent(){}});
 return elements.get(id);
};
const classes=new Set();const document={body:{classList:{contains(c){return classes.has(c);},toggle(c){if(classes.has(c)){classes.delete(c);return false;}classes.add(c);return true;}}},getElementById:element,querySelector:()=>element('assistant_toolbar'),querySelectorAll:()=>[]};
const Shiny={setInputValue:(key,value)=>inputs.push({key,value}),addCustomMessageHandler:(key,fn)=>{assert.equal(fn.length,1,'Shiny custom message handlers take one argument');handlers[key]=fn;}};
const window={dispatchEvent(){}};const events={};const $=arg=>typeof arg==='function'?arg():{trigger(){},on(name,...args){events[name]=args.at(-1);}};
const sandbox={window,document,Shiny,$,Date,setTimeout,clearTimeout,Event:class Event{constructor(type){this.type=type;}}};
vm.runInNewContext(fs.readFileSync('www/assistant.js','utf8'),sandbox);
check(['rdatacraft-ai-delivery','rdatacraft-ai-connection','rdatacraft-ai-clear-key','rdatacraft-ai-state'].every(key=>typeof handlers[key]==='function'),'all assistant Shiny handlers register with the required arity');
window.RDataCraftAssistant.toggle();check(!element('assistant_panel').hidden && classes.has('assistant-open'),'toolbar opens the docked assistant');
window.RDataCraftAssistant.toggle();check(element('assistant_panel').hidden,'toolbar closes the docked assistant');
check(inputs.some(x=>x.key==='assistant_status_check') && posts.length===0,'opening the assistant checks status without sending an inference or using Codex');
handlers['rdatacraft-ai-delivery']({type:'ai-result',id:'portable',ok:true,response:'{}'});check(inputs.at(-1).key==='assistant_response' && inputs.at(-1).value.id==='portable','provider delivery returns through the server validation input');
handlers['rdatacraft-ai-connection']({error:'<script>untrusted provider text</script>'});check(element('ai_connection_notice').textContent==='<script>untrusted provider text</script>','connection errors render as plain text');
element('ai_key').value='synthetic-key';handlers['rdatacraft-ai-clear-key']({});check(element('ai_key').value==='','connecting clears the API key field');
element('ai_key').value='synthetic-dismissed-draft';events['hidden.bs.modal']({target:{querySelector:()=>({})}});check(element('ai_key').value==='' && inputs.at(-1).key==='ai_settings_closed','closing settings clears the key draft and cancels only sign-in');
const beforeClose=inputs.length;events['hidden.bs.modal']({target:{querySelector:()=>null}});check(inputs.length===beforeClose,'closing an unrelated dialog does not start or change AI connections');
handlers['rdatacraft-ai-state']({busy:true});check(element('assistant_send').disabled && !element('assistant_stop').disabled,'in-flight request disables Send and enables Stop');
handlers['rdatacraft-ai-state']({busy:false});check(!element('assistant_send').disabled && element('assistant_stop').disabled,'completion restores Send and disables Stop');
window.RDataCraftAssistant.receive({type:'ai-result',id:'native',ok:true,response:'{}'});check(inputs.at(-1).key==='assistant_response' && inputs.at(-1).value.id==='native','model responses return to server validation');
window.RDataCraftAssistant.toggle();handlers['rdatacraft-review-r']({});check(element('assistant_panel').hidden,'opening a reviewed R draft closes the docked assistant');
handlers['rdatacraft-review-r']({});check(element('assistant_panel').hidden,'review routing preserves an already hidden assistant');
element('assistant_prompt').value='Latest unsynchronized text';element('assistant_share').checked=true;
element('assistant_send').listeners.click();
check(inputs.at(-1).key==='assistant_submit' && inputs.at(-1).value.prompt==='Latest unsynchronized text' && inputs.at(-1).value.share===true,'Send captures the current text and explicit sharing choice together');
const beforeDisabled=inputs.length;handlers['rdatacraft-ai-state']({busy:true});element('assistant_send').listeners.click();
check(inputs.length===beforeDisabled && element('assistant_clear').disabled,'busy controls prevent duplicate DOM submits and clearing');
handlers['rdatacraft-ai-state']({busy:false});handlers['rdatacraft-ai-compose']({prompt:'Review this synthetic script'});
check(!element('assistant_panel').hidden && element('assistant_prompt').value==='Review this synthetic script' && inputs.at(-1).key!=='assistant_submit','Advanced R help opens a reviewable prompt without sending inference');
handlers['rdatacraft-ai-reset']({});
check(element('assistant_prompt').value==='' && element('assistant_share').checked===false,'new-study reset clears the message and disables value sharing');
handlers['rdatacraft-r-state']({busy:true});check(element('r_run').disabled && element('r_load_template').disabled && !element('r_stop').disabled,'R execution locks draft-loading controls and enables Stop');
handlers['rdatacraft-r-state']({busy:false});check(!element('r_run').disabled && element('r_stop').disabled,'R completion restores editing controls');
element('r_code').value='result <- list(text="latest edit")';element('r_title').value='Current R draft';element('r_packages').value='stats';element('r_use_saved').checked=true;element('r_timeout').value='30';
element('r_run').listeners.click();
check(inputs.at(-1).key==='r_submit' && inputs.at(-1).value.r_code==='result <- list(text="latest edit")' && inputs.at(-1).value.r_use_saved===true && inputs.at(-1).value.r_timeout==='30','Run captures the currently reviewed script, package list and input choice together');
console.log(`${checks} checks passed`);

// The installed Ubuntu test must follow the current assistant markup. The account
// summary was intentionally removed; guidance remains in the normal status area.
const ubuntuSource=fs.readFileSync('desktop/linux/linux_tests.py','utf8');
const ubuntuMatch=ubuntuSource.match(/step\(command\('assistant'\),"([^"]+)"/);
assert.ok(ubuntuMatch,'Ubuntu assistant predicate is present');
const ubuntuPredicate=ubuntuMatch[1];
const ubuntuNodes={assistant_panel:{hidden:false},assistant_status:{textContent:'No provider connected · set up through AI → Accounts and Models… Local tools work offline.'}};
const ubuntuDocument={body:{classList:{contains:name=>name==='assistant-open'}},getElementById:id=>ubuntuNodes[id]||null};
check(vm.runInNewContext(ubuntuPredicate,{document:ubuntuDocument})===true,'Ubuntu installed-app check accepts the removed duplicate summary and actual disconnected guidance');
ubuntuNodes.assistant_status.textContent='Ready';
check(vm.runInNewContext(ubuntuPredicate,{document:ubuntuDocument})===false,'Ubuntu installed-app check still requires disconnected-account setup guidance');
ubuntuNodes.assistant_status.textContent='Set up through AI → Accounts and Models…';ubuntuNodes.assistant_connection_summary={textContent:'Repeated connection status'};
check(vm.runInNewContext(ubuntuPredicate,{document:ubuntuDocument})===false,'Ubuntu installed-app check rejects a reintroduced duplicate account summary');
console.log(`${checks} total checks passed`);
