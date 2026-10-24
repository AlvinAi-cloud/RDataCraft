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
const window={dispatchEvent(){}};const $=arg=>typeof arg==='function'?arg():{trigger(){}};
const sandbox={window,document,Shiny,$,Date,Event:class Event{constructor(type){this.type=type;}}};
vm.runInNewContext(fs.readFileSync('www/assistant.js','utf8'),sandbox);
check(['rdatacraft-ai-delivery','rdatacraft-ai-request','rdatacraft-ai-status','rdatacraft-ai-cancel','rdatacraft-ai-state'].every(key=>typeof handlers[key]==='function'),'all assistant Shiny handlers register with the required arity');
window.RDataCraftAssistant.toggle();check(!element('assistant_panel').hidden && classes.has('assistant-open'),'toolbar opens the docked assistant');
window.RDataCraftAssistant.toggle();check(element('assistant_panel').hidden,'toolbar closes the docked assistant');
handlers['rdatacraft-ai-request']({id:'offline'});check(inputs.at(-1).key==='assistant_response' && inputs.at(-1).value.ok===false,'browser mode reports the unavailable native connection');
handlers['rdatacraft-ai-delivery']({type:'ai-result',id:'portable',ok:true,response:'{}'});check(inputs.at(-1).key==='assistant_response' && inputs.at(-1).value.id==='portable','portable model delivery returns through the same server validation input');
window.webkit={messageHandlers:{rdatacraft:{postMessage:v=>posts.push(v)}}};
handlers['rdatacraft-ai-request']({id:'native'});check(posts.at(-1).type==='ai-request' && posts.at(-1).id==='native','native requests keep their request identity');
handlers['rdatacraft-ai-status']({});check(posts.at(-1).type==='ai-status','connection check reaches the native bridge');
handlers['rdatacraft-ai-cancel']({id:'native'});check(posts.at(-1).type==='ai-cancel' && posts.at(-1).id==='native','Stop forwards cancellation for the current request');
handlers['rdatacraft-ai-state']({busy:true});check(element('assistant_send').disabled && !element('assistant_stop').disabled,'in-flight request disables Send and enables Stop');
handlers['rdatacraft-ai-state']({busy:false});check(!element('assistant_send').disabled && element('assistant_stop').disabled,'completion restores Send and disables Stop');
window.RDataCraftAssistant.receive({type:'ai-result',id:'native',ok:true,response:'{}'});check(inputs.at(-1).key==='assistant_response' && inputs.at(-1).value.id==='native','model responses return to server validation');
window.RDataCraftAssistant.toggle();handlers['rdatacraft-review-r']({});check(element('assistant_panel').hidden,'opening a reviewed R draft closes the docked assistant');
handlers['rdatacraft-review-r']({});check(element('assistant_panel').hidden,'review routing preserves an already hidden assistant');
console.log(`${checks} checks passed`);
