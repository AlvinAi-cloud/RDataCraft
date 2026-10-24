(function(){
  const emit=(key,value)=>Shiny.setInputValue(key,{...value,nonce:Date.now()},{priority:'event'});
  const native=(body)=>{if(window.webkit?.messageHandlers?.rdatacraft){window.webkit.messageHandlers.rdatacraft.postMessage(body);return true;}return false;};
  window.RDataCraftAssistant={receive(message){
    if(message.type==='ai-status') emit('assistant_native_status',{message:message.message});
    if(message.type==='ai-result') emit('assistant_response',message);
  },toggle(){
    const open=document.body.classList.toggle('assistant-open');
    document.getElementById('assistant_panel').hidden=!open;
    document.querySelector('[data-command=assistant]')?.setAttribute('aria-expanded',String(open));
    if(open) {document.getElementById('assistant_prompt')?.focus();native({type:'ai-status'});}
    window.dispatchEvent(new Event('resize'));
  }};
  $(function(){
    document.getElementById('assistant_close').addEventListener('click',()=>window.RDataCraftAssistant.toggle());
    document.querySelectorAll('[data-ai-local]').forEach(b=>b.addEventListener('click',()=>emit('assistant_local',{kind:b.dataset.aiLocal})));
    document.querySelectorAll('[data-ai-prompt]').forEach(b=>b.addEventListener('click',()=>{
      const field=document.getElementById('assistant_prompt');field.value=b.dataset.aiPrompt;field.dispatchEvent(new Event('input',{bubbles:true}));$(field).trigger('change');field.focus();
    }));
    Shiny.addCustomMessageHandler('rdatacraft-review-r',message=>{if(document.body.classList.contains('assistant-open'))window.RDataCraftAssistant.toggle();});
    Shiny.addCustomMessageHandler('rdatacraft-ai-delivery',message=>window.RDataCraftAssistant.receive(message));
    Shiny.addCustomMessageHandler('rdatacraft-ai-request',message=>{
      if(!native({type:'ai-request',...message})) emit('assistant_response',{id:message.id,ok:false,message:'Start the native Mac app or the portable launcher to use a signed-in Codex CLI. Local tools are available here.'});
    });
    Shiny.addCustomMessageHandler('rdatacraft-ai-status',message=>{
      if(!native({type:'ai-status'})) emit('assistant_native_status',{message:'Use the portable launcher or native Mac app for the connected assistant; local tools remain available.'});
    });
    Shiny.addCustomMessageHandler('rdatacraft-ai-cancel',message=>native({type:'ai-cancel',...message}));
    Shiny.addCustomMessageHandler('rdatacraft-ai-state',state=>{
      const send=document.getElementById('assistant_send'),stop=document.getElementById('assistant_stop');
      send.disabled=state.busy;stop.disabled=!state.busy;
      document.getElementById('assistant_panel').setAttribute('aria-busy',String(state.busy));
    });
    document.getElementById('assistant_prompt').addEventListener('keydown',e=>{
      if((e.metaKey||e.ctrlKey)&&e.key==='Enter'){e.preventDefault();document.getElementById('assistant_send').click();}
    });
  });
})();
