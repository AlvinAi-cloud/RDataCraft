(function(){
  const emit=(key,value)=>Shiny.setInputValue(key,{...value,nonce:Date.now()},{priority:'event'});
  window.RDataCraftAssistant={receive(message){
    if(message.type==='ai-status') emit('assistant_native_status',{message:message.message});
    if(message.type==='ai-result') emit('assistant_response',message);
  },toggle(){
    const open=document.body.classList.toggle('assistant-open');
    document.getElementById('assistant_panel').hidden=!open;
    document.querySelector('[data-command=assistant]')?.setAttribute('aria-expanded',String(open));
    if(open) {document.getElementById('assistant_prompt')?.focus();Shiny.setInputValue('assistant_status_check',Date.now(),{priority:'event'});}
    window.dispatchEvent(new Event('resize'));
  }};
  const setPrompt=text=>{const field=document.getElementById('assistant_prompt');field.value=text;field.dispatchEvent(new Event('input',{bubbles:true}));$(field).trigger('change');field.focus();};
  $(function(){
    document.getElementById('assistant_send').addEventListener('click',()=>{
      if(document.getElementById('assistant_send').disabled)return;
      emit('assistant_submit',{prompt:document.getElementById('assistant_prompt').value,share:document.getElementById('assistant_share').checked===true});
    });
    Shiny.addCustomMessageHandler('rdatacraft-ai-compose',message=>{if(!document.body.classList.contains('assistant-open'))window.RDataCraftAssistant.toggle();setPrompt(message.prompt);});
    Shiny.addCustomMessageHandler('rdatacraft-ai-reset',message=>{setPrompt('');document.getElementById('assistant_share').checked=false;$('#assistant_share').trigger('change');});
    document.getElementById('assistant_close').addEventListener('click',()=>window.RDataCraftAssistant.toggle());
    document.querySelectorAll('[data-ai-local]').forEach(b=>b.addEventListener('click',()=>emit('assistant_local',{kind:b.dataset.aiLocal})));
    document.querySelectorAll('[data-ai-prompt]').forEach(b=>b.addEventListener('click',()=>{
      setPrompt(b.dataset.aiPrompt);
    }));
    Shiny.addCustomMessageHandler('rdatacraft-review-r',message=>{if(document.body.classList.contains('assistant-open'))window.RDataCraftAssistant.toggle();});
    Shiny.addCustomMessageHandler('rdatacraft-ai-delivery',message=>window.RDataCraftAssistant.receive(message));
    Shiny.addCustomMessageHandler('rdatacraft-ai-state',state=>{
      const send=document.getElementById('assistant_send'),stop=document.getElementById('assistant_stop');
      send.disabled=state.busy;stop.disabled=!state.busy;document.getElementById('assistant_clear').disabled=state.busy;
      document.getElementById('assistant_panel').setAttribute('aria-busy',String(state.busy));
    });
    const history=document.getElementById('assistant_history_scroll');
    if(history && typeof MutationObserver!=='undefined') {
      let follow=true;history.addEventListener('scroll',()=>{follow=history.scrollHeight-history.clientHeight-history.scrollTop<48;});
      new MutationObserver(()=>{if(follow)history.scrollTop=history.scrollHeight;}).observe(document.getElementById('assistant_history'),{childList:true,subtree:true});
    }
    document.getElementById('r_run')?.addEventListener('click',()=>{
      if(document.getElementById('r_run').disabled)return;
      emit('r_submit',{r_title:document.getElementById('r_title').value,r_code:document.getElementById('r_code').value,r_packages:document.getElementById('r_packages').value,r_use_saved:document.getElementById('r_use_saved').checked===true,r_timeout:document.getElementById('r_timeout').value});
    });
    document.getElementById('r_code')?.addEventListener('keydown',e=>{if((e.metaKey||e.ctrlKey)&&e.key==='Enter'){e.preventDefault();document.getElementById('r_run')?.click();}});
    Shiny.addCustomMessageHandler('rdatacraft-r-state',state=>{for(const id of ['r_run','r_check_script','r_load_template','r_load_saved','r_save_draft','r_delete','r_ask_ai']){const button=document.getElementById(id);if(button)button.disabled=state.busy;}const stop=document.getElementById('r_stop');if(stop)stop.disabled=!state.busy;});
    document.getElementById('assistant_prompt').addEventListener('keydown',e=>{
      if((e.metaKey||e.ctrlKey)&&e.key==='Enter'){e.preventDefault();document.getElementById('assistant_send').click();}
    });
  });
})();

// Accounts are managed independently of the message panel. No credentials enter
// conversation history, browser storage, exported studies or diagnostic logs.
(function(){
  let discoverTimer;
  $(function(){
    Shiny.addCustomMessageHandler('rdatacraft-ai-connection',value=>{
      const notice=document.getElementById('ai_connection_notice');
      if(typeof value.loginBusy==='boolean') {
        for(const id of ['ai_sign_in','ai_activate','ai_reauthorize']) {const button=document.getElementById(id);if(button)button.disabled=value.loginBusy;}
        const cancel=document.getElementById('ai_cancel_login');if(cancel)cancel.disabled=!value.loginBusy;
      }
      if(value.chatgpt && !value.chatgpt.accounts?.length) for(const id of ['ai_activate','ai_reauthorize','ai_sign_out']) {const button=document.getElementById(id);if(button)button.disabled=true;}
      if(notice) notice.textContent=value.error || value.notice || value.chatgpt?.notice || value.status || 'Connection settings updated.';
    });
    Shiny.addCustomMessageHandler('rdatacraft-ai-clear-key',message=>{
      const key=document.getElementById('ai_key');if(key)key.value='';
    });
    $(document).on('hidden.bs.modal',event=>{
      if(!event.target?.querySelector('#ai_connection_dialog')) return;
      clearTimeout(discoverTimer);
      const key=document.getElementById('ai_key');if(key)key.value='';
      Shiny.setInputValue('ai_settings_closed',Date.now(),{priority:'event'});
    });
    $(document).on('input','#ai_key',()=>{
      clearTimeout(discoverTimer);
      discoverTimer=setTimeout(()=>{
        if(document.getElementById('ai_connection_dialog') && document.getElementById('ai_key')?.value.trim()) Shiny.setInputValue('ai_discover',Date.now(),{priority:'event'});
      },900);
    });
  });
})();
