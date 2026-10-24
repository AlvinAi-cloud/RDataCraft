(function () {
  const native = !!window.webkit?.messageHandlers?.rdatacraft;
  const post = (body) => { if (native) window.webkit.messageHandlers.rdatacraft.postMessage(body); };
  let announced = false, documentDirty = false;
  window.addEventListener("beforeunload", e => { if (!native && documentDirty) { e.preventDefault(); e.returnValue = ""; } });
  const input = (name, value) => Shiny.setInputValue(name, { ...value, nonce: Date.now() }, { priority: "event" });

  let grid = null, anchor = null, pastePending = false;
  function gridStatus(message) { const el = document.getElementById("grid_selection"); if (el) el.textContent = message; }
  function selectCell(cell, focus = true) {
    if (!grid) return;
    const index = grid.table.cell(cell).index();
    if (!index) return;
    // Ordering and filtering are disabled: server-side page start maps the local
    // DataTables row index to the source observation's absolute row.
    anchor = {sheet: grid.sheet, row: grid.table.page.info().start + index.row + 1, column: index.column + 1};
    document.querySelectorAll("#data_grid td.grid-anchor").forEach(el => {el.classList.remove("grid-anchor"); el.tabIndex = -1;});
    cell.classList.add("grid-anchor"); cell.tabIndex = 0;
    gridStatus(`Row ${anchor.row} · Column ${anchor.column} — ⌘V / Ctrl+V to paste`);
    if (focus && !cell.querySelector("input,textarea")) cell.focus({preventScroll: true});
  }
  function pasteGrid(text) {
    if (!grid || !anchor || anchor.sheet !== grid.sheet || !document.querySelector("#nav_data.active")) return false;
    if (pastePending) {gridStatus("Finishing the previous paste…"); return true;}
    // Discard an uncommitted inline editor before applying the rectangular block.
    // Removing its blur listener prevents an extra cell edit racing the paste.
    $("#data_grid td input,#data_grid td textarea").each(function () {
      const cell = this.closest("td"); $(this).off("blur");
      cell.textContent = grid.table.cell(cell).data();
    });
    pastePending = true; gridStatus("Pasting cells…");
    input("grid_paste", {sheet: grid.sheet, token: grid.token, row: anchor.row, column: anchor.column,
      text, headers: document.getElementById("grid_paste_headers").checked});
    return true;
  }
  window.RDataCraftGrid = {
    bind(table, identity) {
      grid = {table, ...identity};
      if (anchor?.sheet !== grid.sheet) {anchor = null; gridStatus("Select a cell to paste");}
      function draw() {
        if (grid.table !== table) return;
        $(table.table().body()).find("td").attr("tabindex", "-1");
        const start = table.page.info().start;
        input("grid_page", {sheet: grid.sheet, start});
        if (anchor?.sheet === grid.sheet) {
          const local = anchor.row - start - 1;
          const cell = local >= 0 && local < table.rows().count() && anchor.column <= table.columns().count()
            ? table.cell(local, anchor.column - 1).node() : null;
          if (cell) selectCell(cell, false);
        }
      }
      table.on("draw.dt.rdatacraft", draw);
      draw();
    },
    renameHeader(button) {
      if(!grid || button.querySelector("input")) return;
      const source={sheet:grid.sheet,token:grid.token}, original=button.querySelector("span")?.textContent || button.textContent;
      const savedMarkup=button.innerHTML;
      const field=document.createElement("input");field.type="text";field.value=original;field.maxLength=100;field.className="column-name-editor";
      field.setAttribute("aria-label","Column name");let done=false,cancel=false;
      function finish(){if(done)return;done=true;button.innerHTML=savedMarkup;
        if(!cancel && field.value.trim()!==original) {input("rename_column",{...source,column:Number(button.dataset.renameColumn),name:field.value});gridStatus("Renaming column…");}}
      field.addEventListener("click",e=>e.stopPropagation());
      field.addEventListener("keydown",e=>{e.stopPropagation();if(e.key==="Enter" || e.key==="Escape"){e.preventDefault();cancel=e.key==="Escape";finish();}});
      field.addEventListener("blur",finish);button.replaceChildren(field);field.focus();field.select();
    },
    pasteNative(text) {
      if (!document.activeElement?.closest("#data_grid") || document.activeElement?.closest(".column-name-editor")) return false;
      return pasteGrid(text);
    }
  };

  window.RDataCraftDesktop = {
    receive(message) {
      switch (message.type) {
        case "command": return command(message.name);
        case "ai-status": case "ai-result": return window.RDataCraftAssistant?.receive(message);
        case "examples": return input("show_examples", { });
        case "open": return input("desktop_open_project", { path: message.path });
        case "import": return input("desktop_import_data", { path: message.path });
        case "prism": return input("desktop_import_prism", {path:message.path});
        case "saved": return input("desktop_saved", { path: message.path });
        case "new": return input("desktop_action", { name: "new" });
        case "vector-result": return window.dispatchEvent(new CustomEvent("rdatacraft-vector-result",{detail:message}));
      }
    }
  };

  function click(id) { document.getElementById(id)?.click(); }
  function command(name) {
    if (name === "undo" || name === "redo") {
      if (document.activeElement?.matches('input:not([type=checkbox]),textarea,[contenteditable=true]')) document.execCommand(name);
      else if (document.querySelector("#nav_figure.active")) click(name+"_graph");
      else if (document.querySelector("#nav_layout.active")) click(name+"_layout");
      else if (document.querySelector("#nav_data.active")) { const button = document.getElementById(name + "_data"); if (button && !button.disabled) button.click(); }
      return;
    }
    if (name === "examples") return input("show_examples", {});
    if (name === "help") return input("show_help", {});
    if (name === "pca-guide") return input("show_pca_guide", {});
    if (name === "assistant") return window.RDataCraftAssistant?.toggle();
    if (name === "create") return document.getElementById("create_dialog").showModal();
    if (["data", "analysis", "figure", "layout", "project"].includes(name)) return click("nav_" + name);
    if (name === "save") return click("save_project");
    if (name === "export" || name === "export-svg") return click("export_svg");
    if (name === "export-pdf") return click("export_pdf");
    if (name.startsWith("export-layout-")) return click("export_layout_" + name.slice("export-layout-".length));
    if (name === "export-png") return click("export_png");
    if (name === "copy-vector") return click("copy_vector");
    if (name === "inspector") {
      const graphActive=!!document.querySelector("#nav_figure.active");
      if(!graphActive) {click("nav_figure");document.body.classList.remove("inspector-hidden");}
      const hidden = graphActive ? document.body.classList.toggle("inspector-hidden") : false;
      document.querySelector('[data-command="inspector"]')?.setAttribute("aria-pressed", String(!hidden));
      window.dispatchEvent(new Event("resize"));
      return;
    }
    if (native) return post({ type: "command", name });
    if (name === "open") return click("open_project");
    if (name === "import") return click("import_data");
    if (name === "new") {
      const url = new URL(window.location.href);
      url.search = ""; url.hash = ""; url.searchParams.set("rdatacraft_new_study", "1");
      const study = window.open(url.href, "_blank", "width=1320,height=870");
      if (study) study.opener = null;
      else window.alert("Allow pop-up windows for this local app, then choose New study again.");
    }
  }

  $(function () {
    Shiny.addCustomMessageHandler("rdatacraft-welcome", (open) => { document.body.classList.toggle("document-open", open); document.querySelectorAll('.create-choice[data-create="view"],.create-choice[data-create="layout"],.create-choice[data-create="duplicate"]').forEach(b => b.disabled = !open); document.querySelectorAll('[data-command="save"],[data-command="export"],[data-command="data"],[data-command="analysis"],[data-command="figure"],[data-command="inspector"],[data-command="layout"]').forEach(b => b.disabled = !open); });
    document.body.dataset.runtime = native ? "desktop" : "browser";
    $("#nav_data").addClass("active");
    document.querySelectorAll("[data-command]").forEach(button => {
      button.addEventListener("click", () => command(button.dataset.command));
    });
    const chooser = document.getElementById("create_dialog");
    document.getElementById("close_create").addEventListener("click", () => chooser.close());
    document.querySelectorAll("[data-create]").forEach(button => button.addEventListener("click", () => {
      chooser.close();
      const target = button.dataset.create;
      if (target === "worksheet") click("new_worksheet");
      else if (target === "view") click("new_view");
      else if (target === "duplicate") click("duplicate_worksheet");
      else if (target === "layout") command("layout");
      else command("new");
    }));
    document.addEventListener("click", event => {
      const header=event.target.closest("[data-rename-column]");if(header){event.preventDefault();window.RDataCraftGrid.renameHeader(header);return;}
      const remove=event.target.closest("[data-delete-table]");if(remove){event.preventDefault();event.stopPropagation();input("delete_named_table",{sheet:remove.dataset.deleteTable});return;}
      const choice=event.target.closest("[data-gallery-graph]");if(choice){input("graph_choice",{graph:choice.dataset.galleryGraph});return;}
      const name = event.target.closest("[data-rename-table]");
      if (name) {event.preventDefault(); event.stopPropagation(); editTableName(name); return;}
      const button = event.target.closest("button[data-sheet]");
      if (button) input("navigate_sheet", {table: button.dataset.sheet, view: button.dataset.view, page: button.dataset.page});
    });
    function editTableName(button) {
      const field = document.createElement("input"), original = button.textContent;
      field.type = "text"; field.className = "table-name-editor"; field.maxLength = 100;
      field.setAttribute("aria-label", "Data table name"); field.dataset.table = button.dataset.renameTable;
      field.value = original; let cancelled = false, finished = false;
      function finish() {
        if (finished) return; finished = true;
        const value = cancelled ? original : field.value;
        button.textContent = value; field.replaceWith(button);
        if (!cancelled && value !== original) input("rename_table", {table: button.dataset.renameTable, name: value});
      }
      field.addEventListener("click", event => {event.preventDefault(); event.stopPropagation();});
      field.addEventListener("blur", finish);
      field.addEventListener("keydown", event => {
        event.stopPropagation();
        if (event.key === "Enter" || event.key === "Escape") {
          event.preventDefault(); cancelled = event.key === "Escape"; finish(); button.focus({preventScroll:true});
        }
      });
      button.replaceWith(field); field.focus({preventScroll:true}); field.select();
    }
    Shiny.addCustomMessageHandler("rdatacraft-table-name", result => {
      document.querySelectorAll("[data-rename-table]").forEach(button => {
        if (button.dataset.renameTable === result.table) {button.textContent = result.name; button.setAttribute("aria-label", "Rename data table " + result.name);}
      });
    });
    document.addEventListener("click", event => {
      const cell = event.target.closest("#data_grid tbody td");
      if (cell && !event.target.matches("input,textarea")) selectCell(cell);
    });
    document.addEventListener("focusin", event => {
      const cell = event.target.closest("#data_grid tbody td");
      if (cell) selectCell(cell, false);
    });
    document.addEventListener("paste", event => {
      if (!event.target.closest("#data_grid") || event.target.closest(".column-name-editor") || !event.clipboardData) return;
      if (pasteGrid(event.clipboardData.getData("text/plain"))) event.preventDefault();
    });
    document.addEventListener("keydown", event => {
      if (!grid || !event.target.matches("#data_grid td")) return;
      const moves = {ArrowDown: [1, 0], ArrowUp: [-1, 0], ArrowLeft: [0, -1], ArrowRight: [0, 1]};
      const move = moves[event.key]; if (!move || event.metaKey || event.ctrlKey) return;
      const index = grid.table.cell(event.target).index();
      const row = index.row + move[0], col = index.column + move[1];
      const cell = row >= 0 && row < grid.table.rows().count() && col >= 0 && col < grid.table.columns().count()
        ? grid.table.cell(row, col).node() : null;
      if (cell) {event.preventDefault(); selectCell(cell);}
    });
    Shiny.addCustomMessageHandler("rdatacraft-paste-result", result => {
      pastePending = false; gridStatus(result.message);
    });
    function revealCurrentSheet() {
      const navigator = document.getElementById("project_navigator");
      const selected = navigator?.querySelector('[aria-current="page"]');
      if (!selected) return;
      const box = navigator.getBoundingClientRect(), item = selected.getBoundingClientRect();
      if (item.bottom > box.bottom) navigator.scrollTop += item.bottom - box.bottom + 8;
      else if (item.top < box.top) navigator.scrollTop += item.top - box.top - 8;
    }
    new MutationObserver(() => setTimeout(revealCurrentSheet, 0)).observe(document.querySelector(".sidebar"), {childList: true, subtree: true});
    $(document).on("shiny:idle", revealCurrentSheet);
    document.getElementById("navigator_search").addEventListener("input", event => {
      Shiny.setInputValue("navigator_query", event.target.value, {priority: "event"});
    });
    document.addEventListener("keydown", event => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "z" &&
          !event.target.matches('input,textarea,[contenteditable=true]') && !document.querySelector("dialog[open],.modal.show")) {
        event.preventDefault(); command(event.shiftKey ? "redo" : "undo");
      }
    });
    Shiny.addCustomMessageHandler("rdatacraft-history", state => {
      for (const kind of ["undo", "redo"]) {
        const button = document.getElementById(kind + "_data");
        button.disabled = !state[kind];
        button.title = state[kind] ? kind + " " + state[kind + "_label"] : "No data edit to " + kind;
      }
    });
    let figureSize = {width: 3, height: 3};
    const viewport = document.getElementById("figure_viewport"), stage = document.getElementById("figure_stage"), figure = document.getElementById("figure");
    function resizeFigure() {
      if (!viewport.clientWidth) return;
      const width = figureSize.width * 96, height = figureSize.height * 96;
      const zoom = document.getElementById("figure_zoom").value;
      const fit = zoom === "fit";
      const availableHeight = Math.max(120, Math.min(640, window.innerHeight - viewport.getBoundingClientRect().top - 75)) - 48;
      const scale = fit ? Math.min((viewport.clientWidth - 48) / width, availableHeight / height, 1) : (zoom === "200" ? 2 : 1);
      figure.style.width = width + "px"; figure.style.height = height + "px";
      figure.style.transform = `scale(${scale})`;
      stage.style.width = width * scale + "px"; stage.style.height = height * scale + "px";
      viewport.style.height = fit ? height * scale + 48 + "px" : Math.min(height * scale + 48, Math.max(360, window.innerHeight * 0.7)) + "px";
      document.getElementById("figure_dimensions").textContent = `${figureSize.width.toFixed(2)} × ${figureSize.height.toFixed(2)} in · ${Math.round(scale * 100)}%`;
      stage.dataset.scale = scale; stage.dataset.widthIn = figureSize.width; stage.dataset.heightIn = figureSize.height;
    }
    document.getElementById("figure_zoom").addEventListener("change", resizeFigure);
    new ResizeObserver(resizeFigure).observe(viewport);
    window.addEventListener("resize", resizeFigure);
    $(document).on("shiny:idle", resizeFigure);
    for (const dimension of ["width", "height"]) {
      const field = document.getElementById("figure_" + dimension + "_in");
      field.addEventListener("change", () => {
        const inches = Number(field.value), max = dimension === "width" ? 400/25.4 : 300/25.4;
        if (!field.value || !Number.isFinite(inches) || inches < 1 || inches > max) {
          field.setCustomValidity(`Enter a size from 1 to ${max.toFixed(2)} inches.`); field.reportValidity(); return;
        }
        field.setCustomValidity("");
        const internal = document.getElementById(dimension);
        internal.value = String(inches * 25.4); internal.dispatchEvent(new Event("change", {bubbles: true}));
      });
    }
    Shiny.addCustomMessageHandler("rdatacraft-figure-size", size => {
      figureSize = size;
      for (const dimension of ["width", "height"]) {
        const field = document.getElementById("figure_" + dimension + "_in");
        if (field !== document.activeElement) {field.value = Number(size[dimension].toFixed(4)); field.setCustomValidity("");}
      }
      resizeFigure();
    });
    const study = document.getElementById("study_name");
    let acceptedName = study.value;
    study.addEventListener("focus", () => { study.select(); });
    study.addEventListener("blur", () => {
      if (study.value !== acceptedName) input("rename_study", {name: study.value});
    });
    study.addEventListener("keydown", event => {
      if (event.key === "Enter") { event.preventDefault(); study.blur(); }
      else if (event.key === "Escape") { event.preventDefault(); study.value = acceptedName; study.blur(); }
    });
    Shiny.addCustomMessageHandler("rdatacraft-study-name", name => { acceptedName = name; study.value = name; });
    Shiny.addCustomMessageHandler("rdatacraft-page", function (page) {
      $(".nav-item").removeClass("active").removeAttr("aria-current");
      $("#nav_" + page).addClass("active").attr("aria-current", "page");
      document.querySelector('[data-command="inspector"]')?.setAttribute("aria-pressed",String(page === "figure" && !document.body.classList.contains("inspector-hidden")));
      window.scrollTo({ top: 0, behavior: "auto" });
      document.querySelector(".content")?.scrollTo({ top: 0, behavior: "auto" });
    });
    Shiny.addCustomMessageHandler("rdatacraft-document", body => { documentDirty = !!body.dirty; post({ type: "document", ...body }); });
    $(document).on("shiny:idle", function () {
      if (!announced) { announced = true; post({ type: "ready" }); }
    });
    window.addEventListener("error", event => post({ type: "error", message: String(event.message) }));
  });
})();

$(document).on('shiny:connected', function () {
  Shiny.addCustomMessageHandler('rdatacraft-sheet', function (id) {
    [['data', id], ['analysis', id.replace('D', 'R')], ['figure', id.replace('D', 'G')]].forEach(function (entry) {
      const el = document.querySelector('#nav_' + entry[0] + ' .nav-number');
      if (el) el.textContent = entry[1];
    });
  });
});
