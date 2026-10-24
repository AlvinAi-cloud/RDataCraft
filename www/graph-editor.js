(function () {
  const native = !!window.webkit?.messageHandlers?.rdatacraft;
  const send = (name, value) => Shiny.setInputValue(name, {...value, nonce: Date.now()}, {priority:"event"});
  let context = null, expected = null, loaded = "", editor = null, pending = false, mounting = null;
  function current(){return context && expected && context.sheet===expected.sheet && context.view===expected.view && context.token===expected.token;}
  const fields = {
    labels: [["title","Graph title"],["x_label","X axis title"],["y_label","Y axis title"]],
    axes: [["x_min","X minimum (blank = automatic)"],["x_max","X maximum"],["y_min","Y minimum (blank = automatic)"],["y_max","Y maximum"],
      ["log_x","Logarithmic X","checkbox"],["log_y","Logarithmic Y","checkbox"],["grid_lines","Major grid lines","checkbox"],
      ["x_tick_step","X tick interval (blank = automatic)"],["y_tick_step","Y tick interval (blank = automatic)"],["x_tick_angle","X tick label angle (degrees)","number",0,90,15],["ref_x","X reference line (blank = hidden)"],["ref_y","Y reference line (blank = hidden)"],
      ["x_axis_length","X axis length (mm; 0 = automatic)","number",0,350,.1],["y_axis_length","Y axis length (mm; 0 = automatic)","number",0,250,.1],
      ["axis_color","Axis color","color"],["axis_line_width","Axis width (mm)","number",0.1,3,0.05],["axis_tick_size","Tick text size (pt; 0 = automatic)","number",0,48,1]],
    data: [["palette","Palette","select",{craft:"RDataCraft",accessible:"Colorblind accessible",monochrome:"Monochrome"}],
      ["point_size","Symbol size","number",1,6,0.2],["point_shape","Symbol","select",{0:"Automatic",16:"Circle",15:"Square",17:"Triangle",18:"Diamond",1:"Open circle"}],
      ["line_width","Curve width (mm; 0 = automatic)","number",0,4,0.1],
      ["error","Mean interval (bars / shading)","select",{sem:"SEM",sd:"SD",ci:"95% CI",none:"None"}],
      ["show_points","Show individual observations","checkbox"],["show_p","Show comparison P values","checkbox"],
      ["annotation","P-value labels","select",{p:"Numeric P (P < 10⁻⁶ below threshold)",stars:"Significance stars (ns, *, **, ***, ****)"}],
      ["legend_position","Legend","select",{auto:"Automatic",top:"Top",bottom:"Bottom",left:"Left",right:"Right",none:"Hidden"}]],
    text: [["font_size","Base text size (pt)","number",4,24,1],["title_size","Title size (pt; 0 = automatic)","number",0,48,1],
      ["axis_title_size","Axis title size (pt; 0 = automatic)","number",0,48,1],["text_color","Title and axis text color","color"]],
    canvas: [["width","Width (in)","number",1,400/25.4,0.1],["height","Height (in)","number",1,300/25.4,0.1]]
  };
  function status(text) { const node = document.getElementById("graph_edit_status"); if (node) node.textContent = text; }
  function commit(changes, source = context) {
    if (!source || pending) return;
    pending = true; status("Updating graph…");
    send("graph_edit", {sheet:source.sheet,view:source.view,token:source.token,changes});
  }
  function editLabel(node, key) {
    if (editor || pending || !current()) return;
    const figure = document.getElementById("figure"), source = context;
    const field = document.createElement("input"); editor = field;
    field.className = "graph-label-editor"; field.value = source.labels[key] || ""; field.maxLength = 300;
    field.setAttribute("aria-label", "Edit " + key.replaceAll("_", " "));
    const box = node.getBoundingClientRect(), frame = figure.getBoundingClientRect(), scale = frame.width / figure.offsetWidth;
    field.style.left = Math.max(2, Math.min((box.left-frame.left)/scale,figure.offsetWidth-220)) + "px";
    field.style.top = Math.max(2, Math.min((box.top-frame.top)/scale,figure.offsetHeight-38)) + "px";
    field.style.width = Math.min(figure.offsetWidth-4,Math.max(220,box.width/scale+30)) + "px";
    let done = false, cancelled = false;
    function finish() {
      if (done) return; done = true; editor = null; field.remove();
      if (!cancelled && field.value !== source.labels[key]) {
        const changes = {[key]:field.value};
        if (key !== "title") changes[key === "x_label" ? "override_x_title" : "override_y_title"] = true;
        commit(changes, source);
      }
    }
    field.addEventListener("blur",finish);
    field.addEventListener("keydown",event => {
      event.stopPropagation();
      if(event.key === "Enter" || event.key === "Escape") {event.preventDefault(); cancelled = event.key === "Escape"; finish();}
    });
    figure.append(field); field.focus({preventScroll:true}); field.select();
  }
  function format(kind, seriesName = "") {
    if (!current()) {status("Wait for the graph to finish drawing."); return;}
    if (pending) return;
    const source = context, dialog = document.getElementById("graph_format_dialog"), form = dialog.querySelector("form");
    form.replaceChildren();
    dialog.querySelector(".graph-format-error").textContent="";
    dialog.querySelector("h2").textContent = ({labels:"Graph and axis titles",axes:"Format axes",data:"Data appearance · all series",text:"Text appearance",canvas:"Canvas size"})[kind];
    const settings = source.settings;
    const styles = Object.assign(Object.create(null), JSON.parse(settings.series_styles || "{}"));
    const series = source.series || [];
    const palettes = {craft:["#247763","#D6A64D","#6B9CC3","#A18AB9","#D18491","#5FA88F"],accessible:["#0072B2","#D55E00","#009E73","#CC79A7","#E69F00","#56B4E9","#000000"],monochrome:["#233C49","#536C79","#849AA5","#B6C5CC","#D6E0E5"]};
    if (kind === "data" && settings.layout !== "contingency") {
      const label = document.createElement("label"), scope = document.createElement("select");
      label.textContent = "Apply appearance to"; scope.className = "form-control"; scope.id = "graph_series_scope";
      for (const value of ["", ...series]) {const option=document.createElement("option");option.value=value;option.textContent=value || "All series · defaults";scope.append(option);}
      scope.value=seriesName;scope.onchange=()=>format(kind,scope.value);label.append(scope);form.append(label);
    }
    const individual = kind === "data" && seriesName;
    if (kind === "data") dialog.querySelector("h2").textContent = individual ? "Data appearance · " + seriesName : "Data appearance · all series";
    const index = Math.max(0,series.indexOf(seriesName)), palette = palettes[settings.palette] || palettes.craft;
    const baseStyle = {color:palette[index%palette.length],point_size:settings.point_size,point_shape:settings.point_shape || (settings.layout === "column" ? 21 : 19),line_width:settings.line_width || .75,line_type:"solid"};
    const seriesFields = [["color","Series color","color"],["point_shape","Symbol","select",{16:"Circle",15:"Square",17:"Triangle",18:"Diamond",1:"Open circle",21:"Filled circle",22:"Filled square",24:"Filled triangle"}],
      ["point_size","Symbol size","number",1,6,.2],["line_width","Line width (mm)","number",.1,4,.1],
      ["line_type","Line pattern","select",{solid:"Solid",dashed:"Dashed",dotted:"Dotted",dotdash:"Dot dash",longdash:"Long dash",twodash:"Two dash"}]];
    if (baseStyle.point_shape === 19) baseStyle.point_shape = 16;
    const controls = [];
    for (const [key,label,type="text",a,b,step] of (individual ? seriesFields : fields[kind])) {
      const settings = source.settings, layout = settings.layout;
      if (individual && layout === "survival" && ["point_shape","point_size"].includes(key)) continue;
      if (key === "log_x" && layout !== "xy") continue;
      if (key === "log_y" && !["column","xy","grouped"].includes(layout)) continue;
      if (["x_min","x_max","x_tick_step","ref_x"].includes(key) && !["xy","survival","multiple"].includes(layout) && !["histogram","ecdf","qq","density"].includes(settings.graph)) continue;
      if (["y_min","y_max","y_tick_step","ref_y"].includes(key) && ["heatmap","groupheat"].includes(settings.graph)) continue;
      if (key === "error" && (!["column","xy","grouped"].includes(layout) || ["median","density","area","step","groupbox","groupviolin","groupheat","violinbox"].includes(settings.graph))) continue;
      const wrapper = document.createElement("label"), caption = document.createElement("span"); caption.textContent = label;
      let field;
      if(type === "select") {
        field = document.createElement("select");
        for(const [value,text] of Object.entries(a)) {const option=document.createElement("option");option.value=value;option.textContent=text;field.append(option);}
      } else {field=document.createElement("input");field.type=type;}
      field.dataset.setting=key; field.className=type === "checkbox" ? "" : "form-control";
      const value = individual ? (styles[seriesName]?.[key] ?? baseStyle[key]) : kind === "labels" ? source.labels[key] || "" : settings[key];
      if(type === "checkbox") field.checked=!!value;
      else field.value = kind === "canvas" ? Number((value/25.4).toFixed(4)) : value;
      if(type === "number") {field.min=a;field.max=b;field.step=step;}
      if(type === "text") field.maxLength=300;
      wrapper.append(caption,field);form.append(wrapper);controls.push({key,field,type});
    }
    const help=document.createElement("p");help.className="muted";
    help.textContent=individual ? "This series keeps its own color, symbol and line appearance in this linked view. Other series use their own styles or the defaults." : kind === "data" ? "Defaults apply to all series. Individual series overrides take priority; choose a series above to edit or reset it." : kind === "canvas" ? "Fit changes the screen view only. Width and height control the exported figure." : kind === "axes" ? "Entered limits are exact. Axis lengths measure the plotting area within the canvas; 0 uses automatic sizing. Layouts fit axes to their panel size." : "Changes apply only to this linked graph view.";
    form.append(help);
    if (individual) {
      const reset=document.createElement("button");reset.type="button";reset.className="btn btn-outline-secondary";reset.textContent="Reset this series to defaults";
      reset.onclick=()=>{delete styles[seriesName];commit({series_styles:JSON.stringify(styles)},source);};form.append(reset);
    }
    form.onsubmit=event => {
      event.preventDefault(); if(!form.reportValidity()) return;
      const changes={};
      for(const {key,field,type} of controls) changes[key]=type === "checkbox" ? field.checked : type === "number" || key === "point_shape" ? Number(field.value) : field.value;
      if(kind === "canvas") {changes.width *= 25.4; changes.height *= 25.4;}
      if(kind === "labels") {changes.override_x_title=true;changes.override_y_title=true;}
      if (individual) {styles[seriesName]=changes;commit({series_styles:JSON.stringify(styles)},source);}
      else commit(changes,source);
    };
    if (!dialog.open) dialog.showModal();
  }
  function button(node, kind, label) {
    node.dataset.graphKind=kind;node.setAttribute("role","button");node.setAttribute("aria-label",label);
    node.addEventListener("click",event => {event.stopPropagation();kind.startsWith("label:") ? editLabel(node,kind.slice(6)) : format(kind,node.dataset.series || "");});
    node.addEventListener("keydown",event => {if(event.key === "Enter" || event.key === " ") {event.preventDefault();node.dispatchEvent(new MouseEvent("click",{bubbles:true}));}});
  }
  async function mount() {
    const figure=document.getElementById("figure"), img=figure?.querySelector("img");
    if(!img || !img.src) return;
    // Shiny can replace the image output with identical SVG data, removing our
    // interactive sibling. A matching URL alone does not mean it is mounted.
    if(img.src === loaded && figure.querySelector("svg.graph-interactive")) return;
    if(mounting?.img === img && mounting.src === img.src) return;
    const src=img.src, request={img,src}; mounting=request; loaded=src; context=null;
    figure.querySelectorAll("svg.graph-interactive,.graph-label-editor").forEach(node=>node.remove()); editor=null;
    img.style.visibility="visible";
    try {
      const url=new URL(src,location.href);let source;
      if(/^data:image\/svg\+xml;base64,/.test(src) && src.length<60_000_000) {
        const bytes=atob(src.slice(src.indexOf(',')+1));source=new TextDecoder().decode(Uint8Array.from(bytes,char=>char.charCodeAt(0)));
      } else {
        if(url.origin !== location.origin) throw Error("Unexpected graph source.");
        const response=await fetch(url);if(!response.ok) throw Error("Graph loading failed.");source=await response.text();
      }
      const parsed=new DOMParser().parseFromString(source,"image/svg+xml");
      const svg=parsed.documentElement, metadata=svg.querySelector("#rdatacraft-interaction");
      if(svg.localName !== "svg" || !metadata || parsed.querySelector("parsererror")) throw Error("Graph metadata missing.");
      if(figure.querySelector("img") !== img || img.src !== src) return;
      context=JSON.parse(metadata.textContent); svg.classList.add("graph-interactive");svg.setAttribute("aria-label","Editable scientific graph");
      figure.append(document.importNode(svg,true));const inline=figure.querySelector("svg.graph-interactive");img.style.visibility="hidden";
      const seriesList=Array.isArray(context.series)?context.series:context.series?[context.series]:[];
      context.series=seriesList;
      const colorToHex=value=>{const c=document.createElement('canvas').getContext('2d');c.fillStyle=value;return c.fillStyle.toLowerCase();};
      const colors=context.colors || {};
      function identify(node){const cs=getComputedStyle(node),matches=seriesList.filter(g=>[cs.stroke,cs.fill].some(c=>colors[g] && colorToHex(c)===colors[g].toLowerCase()));if(matches.length===1)node.dataset.series=matches[0];}
      const texts=[...inline.querySelectorAll("text")];

      for(const key of ["title","x_label","y_label"]) {
        const value=context.labels[key];if(!value) continue;
        const candidates=texts.filter(node=>node.textContent === value && !node.dataset.graphKind);
        candidates.sort((a,b)=>key === "x_label" ? b.getBoundingClientRect().top-a.getBoundingClientRect().top : key === "y_label" ? a.getBoundingClientRect().left-b.getBoundingClientRect().left : a.getBoundingClientRect().top-b.getBoundingClientRect().top);
        if(candidates[0]) {button(candidates[0],"label:"+key,"Edit "+key);candidates[0].setAttribute("tabindex","0");}
      }
      for(const node of texts) if(!node.dataset.graphKind && seriesList.includes(node.textContent)) {node.dataset.series=node.textContent;button(node,"data","Format series "+node.textContent);node.setAttribute("tabindex","0");}
      const vb=inline.viewBox.baseVal, rects=[...inline.querySelectorAll("clipPath rect")].map(node=>({x:Number(node.getAttribute("x")),y:Number(node.getAttribute("y")),w:Number(node.getAttribute("width")),h:Number(node.getAttribute("height"))}));
      const panel=rects.filter(r=>r.w*r.h < vb.width*vb.height*.97 && r.w>20 && r.h>20).sort((a,b)=>b.w*b.h-a.w*a.h)[0];
      if(panel) for(const [axis,x,y,w,h] of [["x",panel.x,panel.y+panel.h-3,panel.w,14],["y",panel.x-10,panel.y,14,panel.h]]) {
        const strip=document.createElementNS("http://www.w3.org/2000/svg","rect");
        for(const [key,value] of Object.entries({x,y,width:w,height:h,fill:"transparent"})) strip.setAttribute(key,value);
        strip.classList.add("graph-axis-target");strip.dataset.axis=axis;strip.setAttribute("tabindex","0");button(strip,"axes","Format "+axis.toUpperCase()+" axis");inline.append(strip);
      }
      if(panel) for(const node of inline.querySelectorAll("path,line,polyline")) {
        if(node.closest("defs")) continue;
        const box=node.getBBox();
        if(box.x>panel.x+.5 && box.y>=panel.y-.5 && box.x+box.width<=panel.x+panel.w+.5 && box.y+box.height<=panel.y+panel.h+.5)
          {identify(node);button(node,"data","Format data appearance");}
      }
      let first=true;
      for(const node of inline.querySelectorAll("circle,ellipse,polygon,rect")) {
        if(node.closest("defs") || node.dataset.graphKind || node.classList.contains("graph-axis-target")) continue;
        const fill=getComputedStyle(node).fill;
        if(!["circle","ellipse"].includes(node.localName) && ["none","rgb(255, 255, 255)","rgba(0, 0, 0, 0)"].includes(fill)) continue;
        if(node.getAttribute("width") === "100%") continue;
        identify(node);button(node,"data","Format data appearance");node.setAttribute("tabindex",first?"0":"-1");first=false;
      }
      for(const node of texts) if(!node.dataset.graphKind && panel) {
        const box=node.getBBox();if(box.x<panel.x || box.y>panel.y+panel.h) button(node,"axes","Format axis labels");
      }
      status("Click a title to edit it. Click an axis or data symbol to format.");
    } catch(error) {if(figure.querySelector("img") === img && img.src === src) {loaded="";status("Graph interaction unavailable: "+error.message);}}
    finally {if(mounting === request) mounting=null;}
  }
  $(function () {
    const toolbar=document.querySelector(".graph-toolbars"), live=document.createElement("div");live.id="graph_edit_status";live.setAttribute("role","status");toolbar.after(live);
    const dialog=document.createElement("dialog");dialog.id="graph_format_dialog";
    dialog.innerHTML='<h2></h2><p class="graph-format-error" role="alert"></p><form id="graph_format_form"></form><div class="dialog-actions"><button type="button" class="btn btn-outline-secondary">Cancel</button><button type="submit" form="graph_format_form" class="btn btn-primary">Apply formatting</button></div>';
    dialog.querySelector('button[type="button"]').onclick=()=>dialog.close();document.body.append(dialog);
    document.addEventListener("click",event=>{
      const tool=event.target.closest("[data-graph-format]");if(tool) format(tool.dataset.graphFormat);
      const action=event.target.closest("[data-graph-action]");if(action) document.getElementById(action.dataset.graphAction)?.click();
      const remove=event.target.closest("[data-delete-view]");if(remove) send("delete_named_view",{sheet:remove.dataset.deleteSheet,view:remove.dataset.deleteView});
    });
    new MutationObserver(mount).observe(document.getElementById("figure"),{childList:true,subtree:true,attributes:true,attributeFilter:["src"]});
    $(document).on("shiny:idle",mount);
    Shiny.addCustomMessageHandler("rdatacraft-graph-context",value=>{expected=value;const figure=document.getElementById("figure");if(figure)figure.dataset.currentToken=value.token;});
    Shiny.addCustomMessageHandler("rdatacraft-graph-history",h=>{for(const k of ["undo","redo"])document.getElementById(k+"_graph").disabled=!h[k];});
    Shiny.addCustomMessageHandler("rdatacraft-graph-edit",result=>{pending=false;status(result.message);if(result.ok && dialog.open) dialog.close();else if(dialog.open) dialog.querySelector('.graph-format-error').textContent=result.message;});
    Shiny.addCustomMessageHandler("rdatacraft-vector",payload=>{
      if(native) window.webkit.messageHandlers.rdatacraft.postMessage({type:"vector",...payload});
      else {status("Vector clipboard is available in the desktop app. Use SVG or PDF export here.");}
    });
    Shiny.addCustomMessageHandler("rdatacraft-vector-error",message=>status(message));
    window.addEventListener("rdatacraft-vector-result",event=>status(event.detail.ok ? "Vector PDF and SVG copied. Paste into your design app." : event.detail.message));
  });
  window.RDataCraftGraph={format,ready(){return !!current() && !pending && !document.documentElement.classList.contains("shiny-busy") && document.querySelector("#figure img")?.src===loaded;},copyIfGraph(){
    if(!document.querySelector("#nav_figure.active") || document.querySelector("dialog[open],.modal.show") || document.activeElement?.matches('input,textarea,[contenteditable=true]')) return false;
    document.getElementById("copy_vector").click();return true;
  }};
})();
