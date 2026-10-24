(function(){
  let context=null, selected="", loaded="", pending=false;
  const $id=id=>document.getElementById(id);
  const status=text=>{$id("layout_edit_status").textContent=text;};
  function send(action,extra={}){if(!context || pending)return;pending=true;status("Updating figure…");Shiny.setInputValue("layout_edit",{token:context.token,action,...extra,nonce:Date.now()},{priority:"event"});}
  function choose(key){
    selected=key;const r=context?.rects[key];if(!r)return;
    document.querySelectorAll('.layout-panel-hit').forEach(el=>{el.classList.toggle('selected',el.dataset.key===key);el.setAttribute('aria-pressed',String(el.dataset.key===key));});
    $id('layout_panel_name').textContent=context.names[key] || key;
    for(const k of ['x','y','w','h']) $id('panel_'+k).value=Number(r[k].toFixed(2));
    $id('panel_label').value=JSON.parse(context.settings.labels || '{}')[key] ?? String.fromCharCode(65+context.settings.selected.indexOf(key));
  }
  function position(el,r){const s=context.settings;Object.assign(el.style,{left:r.x/s.width*100+'%',top:r.y/s.height*100+'%',width:r.w/s.width*100+'%',height:r.h/s.height*100+'%'});}
  async function mount(){
    const img=$id('layout_figure')?.querySelector('img');if(!img?.src || img.src===loaded)return;
    const src=img.src;loaded=src;context=null;$id('layout_handles').replaceChildren();
    try{
      const url=new URL(src,location.href);let text;
      if(src.startsWith('data:image/svg+xml;base64,')) text=new TextDecoder().decode(Uint8Array.from(atob(src.split(',')[1]),c=>c.charCodeAt(0)));
      else {if(url.origin!==location.origin)throw Error('Unexpected page source.');const response=await fetch(url);text=await response.text();}
      if(img.src!==src)return;
      const xml=new DOMParser().parseFromString(text,'image/svg+xml');context=JSON.parse(xml.querySelector('#rdatacraft-layout').textContent);
      const keys=Array.isArray(context.settings.selected)?context.settings.selected:[context.settings.selected];context.settings.selected=keys;
      for(const key of keys){
        const r=context.rects[key], hit=document.createElement('div');hit.className='layout-panel-hit';hit.tabIndex=0;hit.setAttribute('role','button');hit.setAttribute('aria-label','Select panel '+context.names[key]);hit.dataset.key=key;
        const label=document.createElement('span');label.className='panel-drag-label';label.textContent='↔ '+(JSON.parse(context.settings.labels)[key] ?? String.fromCharCode(65+keys.indexOf(key)));hit.append(label);
        const resize=document.createElement('span');resize.className='panel-resize';resize.title='Drag to resize panel';hit.append(resize);position(hit,r);
        hit.addEventListener('click',()=>choose(key));hit.addEventListener('keydown',event=>{
          if(event.key==='Enter' || event.key===' '){event.preventDefault();choose(key);return;}
          const delta={ArrowLeft:[-1,0],ArrowRight:[1,0],ArrowUp:[0,-1],ArrowDown:[0,1]}[event.key];if(!delta || pending)return;
          event.preventDefault();choose(key);const rect={...context.rects[key]},step=event.shiftKey?5:1;rect.x=Math.max(0,Math.min(context.settings.width-rect.w,rect.x+delta[0]*step));rect.y=Math.max(0,Math.min(context.settings.height-rect.h,rect.y+delta[1]*step));send('move',{key,rect});
        });
        hit.addEventListener('pointerdown',event=>{
          if(event.button!==0 || pending)return;event.preventDefault();choose(key);
          const source=context,rect={...r},start=[event.clientX,event.clientY],bounds=$id('layout_stage').getBoundingClientRect(),sizing=event.target===resize;
          const ghost=document.createElement('div');ghost.className='layout-drag-ghost';$id('layout_handles').append(ghost);position(ghost,rect);hit.setPointerCapture(event.pointerId);
          let moved=false;
          const move=e=>{moved ||= Math.abs(e.clientX-start[0])+Math.abs(e.clientY-start[1])>3;
            const dx=(e.clientX-start[0])/bounds.width*source.settings.width,dy=(e.clientY-start[1])/bounds.height*source.settings.height;
            const snap=v=>$id('layout_snap').checked?Math.round(v):v;
            if(sizing){rect.w=Math.max(15,Math.min(source.settings.width-r.x,snap(r.w+dx)));rect.h=Math.max(15,Math.min(source.settings.height-r.y,snap(r.h+dy)));}
            else {rect.x=Math.max(0,Math.min(source.settings.width-r.w,snap(r.x+dx)));rect.y=Math.max(0,Math.min(source.settings.height-r.h,snap(r.y+dy)));}
            position(ghost,rect);for(const k of ['x','y','w','h'])$id('panel_'+k).value=Number(rect[k].toFixed(2));};
          const finish=e=>{hit.removeEventListener('pointermove',move);hit.removeEventListener('pointerup',finish);hit.removeEventListener('pointercancel',cancel);ghost.remove();if(moved)send('move',{key,rect});};
          const cancel=()=>{hit.removeEventListener('pointermove',move);hit.removeEventListener('pointerup',finish);hit.removeEventListener('pointercancel',cancel);ghost.remove();choose(key);};
          hit.addEventListener('pointermove',move);hit.addEventListener('pointerup',finish);hit.addEventListener('pointercancel',cancel);
        });
        $id('layout_handles').append(hit);
      }
      if(!keys.includes(selected))selected=keys[0];choose(selected);status('Drag a panel to move it; drag its corner to resize. Arrow keys move 1 mm; Shift moves 5 mm.');
    }catch(error){loaded='';status('Layout editing unavailable: '+error.message);}
  }
  $(function(){
    new MutationObserver(mount).observe($id('layout_figure'),{childList:true,subtree:true,attributes:true,attributeFilter:['src']});$(document).on('shiny:idle',mount);
    document.addEventListener('click',event=>{const template=event.target.closest('[data-layout-template]');if(template)send('template',{value:template.dataset.layoutTemplate});const order=event.target.closest('[data-layout-order]');if(order && selected)send(order.dataset.layoutOrder,{key:selected});});
    $id('layout_panel_form').onsubmit=event=>{event.preventDefault();if(!context || !selected || !event.target.reportValidity())return;const rect={};for(const k of ['x','y','w','h'])rect[k]=Number($id('panel_'+k).value);send('move',{key:selected,rect});};
    $id('panel_label').onchange=()=>{if(selected)send('label',{key:selected,value:$id('panel_label').value});};
    Shiny.addCustomMessageHandler('rdatacraft-layout-edit',r=>{pending=false;status(r.message);});
    Shiny.addCustomMessageHandler('rdatacraft-layout-history',h=>{for(const k of ['undo','redo'])$id(k+'_layout').disabled=!h[k];});
    Shiny.addCustomMessageHandler('rdatacraft-header',r=>{const node=$id('grid_selection');if(node)node.textContent=r.message;});
  });
})();
