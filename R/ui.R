# Compact Craft-family chrome. Color tokens match the user's PlasmidCraft desktop UI.
pc_icon <- function(name) {
  paths <- list(
    help = '<circle cx="12" cy="12" r="9"/><path d="M9 9a3 3 0 1 1 5 2c-2 1-2 2-2 3M12 17h.01"/>',
    assistant = '<path d="M4 4h12v11H9l-5 4zM8 8h5M8 11h3M19 2v6M16 5h6"/>',
    new = '<path d="M12 5v14M5 12h14"/>',
    open = '<path d="M3 7h7l2 3h9l-2 10H3z"/><path d="M3 7V4h7l2 3h7v3"/>',
    save = '<path d="M4 3h13l3 3v15H4z"/><path d="M8 3v6h8V3M8 21v-8h9v8"/>',
    import = '<path d="M12 3v12m-5-5 5 5 5-5M4 15v6h16v-6"/>',
    export = '<path d="M12 15V3m-5 5 5-5 5 5M4 15v6h16v-6"/>',
    data = '<rect x="3" y="4" width="18" height="16" rx="1"/><path d="M3 9h18M3 14h18M9 4v16M15 4v16"/>',
    analysis = '<path d="M2 12h5l3-9 4 18 3-9h5"/>',
    graph = '<path d="M4 3v17h17M7 15l4-5 4 2 5-7"/><circle cx="7" cy="15" r="1"/><circle cx="15" cy="12" r="1"/>',
    layout = '<rect x="3" y="3" width="18" height="18" rx="1"/><path d="M3 12h18M12 3v18"/>',
    inspector = '<rect x="3" y="4" width="18" height="16" rx="1"/><path d="M15 4v16M18 8h1M18 11h1"/>',
    project = '<path d="M5 3h10l4 4v14H5zM15 3v5h4M8 12h8M8 16h8"/>')
  htmltools::HTML(paste0('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">', paths[[name]], '</svg>'))
}
pc_tool <- function(command, label, icon = command) {
  tags$button(type = "button", class = "toolbar-button", `data-command` = command,
              pc_icon(icon), span(label))
}
pc_chrome <- function() {
  tagList(
    div(class = "application-bar", div(class = "app-brand", pc_icon("graph"), strong("RDataCraft")),
        span("Scientific plotting & statistics", class = "application-description"),
        span(if(identical(Sys.getenv("RDATACRAFT_PORTABLE"),"1")) "v0.3 · Portable preview" else "v0.3 · Desktop preview", class = "version-label")),
    tags$dialog(id = "create_dialog", `aria-labelledby` = "create_heading",
      h2(id = "create_heading", "What would you like to create?"),
      p("A study holds your data tables, linked analyses, graphs, and figure layouts."),
      tags$button(type = "button", class = "create-choice", `data-create` = "worksheet",
        strong("Add data table…"), span("Add an experiment to this study. Choose Column, XY, Grouped, Contingency, Survival, or Multiple variables (PCA).")),
      tags$button(type = "button", class = "create-choice", `data-create` = "view",
        strong("Add linked analysis / graph…"), span("Use the current table with its own analysis and graph settings. Source data stay shared.")),
      tags$button(type = "button", class = "create-choice", `data-create` = "layout",
        strong("Arrange a figure layout"), span("Combine existing linked graphs into a publication figure.")),
      tags$button(type = "button", class = "create-choice", `data-create` = "duplicate",
        strong("Duplicate table & linked views…"), span("Copy the current experiment and its analysis / graph settings into an independent data table.")),
      tags$hr(),
      tags$button(type = "button", class = "create-choice", `data-create` = "study",
        strong("New study…"), span("Open a blank study in a new window. This study stays open.")),
      tags$button(type = "button", id = "close_create", class = "btn btn-outline-secondary", "Cancel")),
    div(class = "commandbar", role = "toolbar", `aria-label` = "Project commands",
        div(class = "toolbar-group", pc_tool("create", "Create…", "new"), pc_tool("open", "Open"),
            pc_tool("save", "Save"), pc_tool("import", "Import"), pc_tool("export", "Export")),
        div(class = "toolbar-group", pc_tool("data", "Data table", "data"),
            pc_tool("analysis", "Analyze", "analysis"), pc_tool("figure", "Graph", "graph"),
            tags$button(type="button",class="toolbar-button inspector-tool",`data-command`="inspector",`aria-pressed`="false",`aria-controls`="figure_settings",title="Show or hide settings for the active graph",pc_icon("inspector"),span("Figure settings")),
            pc_tool("layout","Figure layout","layout")),
        div(class = "toolbar-spacer"), pc_tool("help","Help","help"),
        tags$button(type="button",class="toolbar-button",`data-command`="assistant",`aria-expanded`="false",pc_icon("assistant"),span("AI Assistant"))))
}

pc_table_name_button <- function(id, name) tags$button(type = "button", class = "table-name",
  `data-rename-table` = id, title = "Click to rename data table. Enter saves; Escape cancels.",
  `aria-label` = paste("Rename data table", name), name)

pc_project_navigator <- function(book, active, view, page, query = "") {
  visible <- pc_navigator_filter(book, query)
  link <- function(label, id, vid = "", destination, icon) {
    selected <- id == active && destination == page && (destination == "data" || vid == view)
    tags$button(type = "button", class = paste("sheet-link", if (selected) "active" else ""),
      `data-sheet` = id, `data-view` = vid, `data-page` = destination,
      `aria-current` = if (selected) "page" else NULL,
      title = paste(label, "·", book[[id]]$name), pc_icon(icon), span(label))
  }
  tagList(div(class = "navigator-heading", span("PROJECT SHEETS"), span(length(book), class = "sheet-count")),
    if (!length(visible)) p(class = "navigator-empty", "No matching tables or views."),
    lapply(names(visible), function(id) {
      sh <- visible[[id]]
      tags$details(class = paste("navigator-family", if (id == active) "current-family" else ""),
        open = if (id == active || nzchar(trimws(query))) TRUE else NULL,
        tags$summary(span(class="navigator-summary-content",
          span(class="navigator-summary-labels",span(span(paste0(id," · ")),pc_table_name_button(id,sh$name),class="family-name"),span(sh$settings$layout,class="table-type")),
          tags$button(type="button",class="delete-table-button",`data-delete-table`=id,title=paste("Delete data table",sh$name),`aria-label`=paste("Delete data table",sh$name),"×"))),
        link("Data table", id, destination = "data", icon = "data"),
        lapply(names(sh$views), function(vid) div(class = "navigator-view",
          div(class = "view-name", span(sh$views[[vid]]$name),
            if(length(book[[id]]$views)>1L) tags$button(type="button",class="delete-view-button",`data-delete-sheet`=id,`data-delete-view`=vid,
              title=paste("Delete linked view",sh$views[[vid]]$name),`aria-label`=paste("Delete linked view",sh$views[[vid]]$name),"×")),
          div(class = "view-links", link("Analysis", id, vid, "analysis", "analysis"), link("Graph", id, vid, "figure", "graph")))))
    }))
}
pc_header_button <- function(name,column) tags$button(type="button",class="column-name-button",`data-rename-column`=column,
  `aria-label`=paste("Rename column",name),title="Click to rename. Enter saves; Escape cancels.",span(name),span(class="column-edit-mark",`aria-hidden`="true"))
pc_grid_header <- function(tab,layout) {
  if(layout=="xy") {header <- pc_xy_grid_header(tab); if(!is.null(header)) return(header)}
  tags$table(class="display",tags$thead(tags$tr(lapply(seq_along(tab),function(i) tags$th(pc_header_button(names(tab)[i],i))))))
}
pc_xy_grid_header <- function(tab) {
  spec <- pc_xy_structure(tab)
  if (spec$n == 1L) return(NULL)
  tags$table(class = "display", tags$thead(
    tags$tr(tags$th(pc_header_button(names(tab)[1],1), rowspan = 2), lapply(seq_along(spec$groups), function(i) tags$th(pc_header_button(spec$groups[i],2+(i-1)*spec$n), colspan = spec$n))),
    tags$tr(lapply(spec$replicate, function(i) tags$th(paste("Rep", i))))))
}

pc_template_preview <- function(layout, example = TRUE, xy_replicates = 1L) {
  if (is.null(layout) || !layout %in% unname(pc_layouts())) return(NULL)
  e <- pc_example(layout); tab <- if (isTRUE(example)) e$table else pc_blank(layout)
  if (layout == "xy") tab <- pc_xy_replicates(tab, xy_replicates)
  method <- if (isTRUE(example)) e$method else unname(pc_methods(layout))[1]
  div(class = "template-preview",
    div(class = "eyebrow", "TABLE STRUCTURE"), h3(sub(" ·.*", "", names(pc_layouts())[match(layout, pc_layouts())])),
    p(pc_layout_help(layout)),
    div(class = "template-table", tags$table(tags$thead(tags$tr(lapply(names(tab), tags$th))),
      tags$tbody(lapply(seq_len(min(4, nrow(tab))), function(i) tags$tr(lapply(tab[i, ], function(v) tags$td(if (is.na(v)) "—" else as.character(v)))))))),
    p(class = "template-foot", if (isTRUE(example)) "Preview of example observations." else "Blank template; — means missing. Category counts start at zero.",
      " The table creates a linked analysis and graph view."),
    p(class = "template-method", strong("Starting analysis: "), names(pc_methods(layout))[match(method, pc_methods(layout))]))
}
