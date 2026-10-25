# RDataCraft — local scientific plotting and statistics, GPL-3.0.
library(shiny)
# Desktop dialogs change immediately so a closing dialog cannot remove its successor.
modalDialog <- function(...,fade=FALSE) shiny::modalDialog(...,fade=fade)
source("R/data.R", local = TRUE)
source("R/analysis.R", local = TRUE)
source("R/plot.R", local = TRUE)
source("R/project.R", local = TRUE)
source("R/session.R", local = TRUE)
source("R/ui.R", local = TRUE)
source("R/report.R", local = TRUE)
source("R/interaction.R", local = TRUE)
source("R/prism_import.R",local=TRUE)
source("R/tutorials.R",local=TRUE)
source("R/assistant.R",local=TRUE)
source("R/portable_ai.R",local=TRUE)
source("R/ai_connections.R",local=TRUE)
source("R/assistant_server.R",local=TRUE)
source("R/advanced_r_server.R",local=TRUE)
source("R/help.R",local=TRUE)
options(shiny.maxRequestSize = 32 * 1024^2)

nav_button <- function(id, number, label) actionButton(id,
  tagList(span(number, class = "nav-number"), span(label)), class = "nav-item")
field_section <- function(title, ...) div(class = "field-section", h4(title), ...)

ui <- fluidPage(
  theme = bslib::bs_theme(version = 5, base_font = "system-ui", primary = "#247763"),
  tags$head(tags$title("RDataCraft"),
            tags$link(rel = "stylesheet", href = "rdatacraft.css"),
            tags$link(rel = "stylesheet", href = "craft.css"),
            tags$script(src = "rdatacraft.js"), tags$script(src="graph-editor.js"), tags$script(src="layout-editor.js"),tags$script(src="assistant.js")),
  div(style="display:none", lapply(c("title_size","axis_title_size","axis_tick_size","text_color","axis_color","axis_line_width","point_shape","line_width","override_x_title","override_y_title","series_styles","x_tick_step","y_tick_step","x_tick_angle","ref_x","ref_y","pca_variables"),function(key) {
    value <- pc_defaults()[[key]]
    if(is.logical(value)) checkboxInput(key,key,value) else if(is.numeric(value)) numericInput(key,key,value) else textInput(key,key,value)
  })),
  pc_chrome(),
  pc_assistant_ui(),
  div(class="welcome-screen", h1("Welcome to RDataCraft"),p("Start a study, open a project, or explore an example. No file is open."),
    div(class="welcome-actions",
      tags$button(type="button",class="btn btn-primary",`data-command`="new","Create a study…"),
      tags$button(type="button",class="btn btn-outline-secondary",`data-command`="open","Open project…"),
      tags$button(type="button",class="btn btn-outline-secondary",`data-command`="examples","Examples & analysis guide…")),
    div(class="welcome-prism",fileInput("welcome_prism","Import a Prism file",accept=c(".prism",".pzfx"),placeholder="Choose a Prism project")),
    p(class="muted","Prism import creates editable tables and supported analysis / graph views. Review its conversion report before committing.")),
  div(class = "app-shell",
    tags$aside(class = "sidebar",
      div(class = "brand", div(class = "brand-mark", span(), span(), span()),
          div(strong("RDataCraft"), span("A clearer view of your science"))),
      div(class = "workspace-label", "STUDY"),
      div(class = "project-name", span(class = "project-dot"),
          tags$input(id = "study_name", type = "text", value = "Untitled study", maxlength = 100,
                     `aria-label` = "Study name", title = "Click to rename study. Enter to save; Escape to cancel."),
          span("✎", class = "rename-hint", `aria-hidden` = "true")),
      div(class = "sidebar-create", actionButton("new_worksheet", "+ Data table…", class = "btn-primary"),
          actionButton("new_view", "+ Linked view…", class = "btn-outline-secondary")),
      tags$label(`for` = "navigator_search", class = "navigator-label", "Find a table or view"),
      tags$input(id = "navigator_search", type = "search", class = "form-control", maxlength = 100,
                 placeholder = "Search this study", `aria-label` = "Search project sheets"),
      uiOutput("project_navigator"),
      tags$details(class = "sheet-options", tags$summary("Table & view options"),
        selectInput("worksheet", "Active data table", choices = c("D1 · Observation table" = "D1")),
        div(class = "sheet-actions", actionButton("rename_worksheet", "Rename table", class = "btn-outline-secondary"),
            actionButton("duplicate_worksheet", "Duplicate table…", class = "btn-outline-secondary")),
        selectInput("graph_view", "Active linked view", choices = c("Primary view" = "V1")),
        actionButton("rename_view", "Rename view", class = "btn-outline-secondary"),
        actionButton("delete_view", "Delete linked view…", class = "btn-outline-secondary")),
      tags$nav(class = "workspace-nav", `aria-label` = "Active table workspace",
               nav_button("nav_data", "D1", "Data"), nav_button("nav_analysis", "R1", "Analysis"),
               nav_button("nav_figure", "G1", "Graph"), nav_button("nav_layout", "L", "Figure layout"),
               nav_button("nav_project", "P", "Project & sources"), nav_button("nav_advanced", "R+", "Advanced R")),
      div(class = "sidebar-dataset", div(class = "eyebrow", "CURRENT DATASET"),
          uiOutput("dataset_info"), actionButton("edit_data", "Edit data →", class = "text-button")),
      div(class = "sidebar-bottom", div(class = "local-indicator", span(), "Runs on your computer"),
          p("Save your project to keep its data, analyses, and graph settings together."),
          div(class = "powered", "Built with R · ggplot2"))),
    div(class = "main-shell",
      tags$header(class = "topbar", div(span(class = "status-dot"), "Scientific workspace", span("/", class = "slash"),
        strong(textOutput("page_title", inline = TRUE))),
        div(class = "top-actions", downloadButton("save_project", "Save project", class = "btn-outline-secondary"))),
      div(class = "content",
        tabsetPanel(id = "workspace", type = "hidden", selected = "data",
          tabPanel("Advanced R", value="advanced",pc_r_ui()),
          tabPanel("Figure", value = "figure",
            div(class = "page-heading", div(div(class = "eyebrow", "FROM OBSERVATION TO UNDERSTANDING"),
                h1(textOutput("figure_heading", inline = TRUE)), p("Linked to the active worksheet. Styling and analysis annotations update with your data.")),
                span("LOCAL PREVIEW", class = "preview-badge")),
            div(class = "studio-layout",
              div(class = "figure-column",
                uiOutput("analysis_banner"),
                div(class = "canvas-card",
                  div(class = "graph-toolbars", role = "toolbar", `aria-label` = "Graph editing tools",
                    div(class = "graph-tool-group", span("FORMAT", class = "graph-tool-label"),
                      lapply(c(Labels="labels",Axes="axes",Data="data",Text="text",Canvas="canvas"), function(kind)
                        tags$button(type="button",class="btn btn-outline-secondary",`data-graph-format`=kind,names(c(Labels="labels",Axes="axes",Data="data",Text="text",Canvas="canvas"))[match(kind,c("labels","axes","data","text","canvas"))]))),
                    div(class = "graph-tool-group", span("GRAPH",class="graph-tool-label"),
                      actionButton("graph_gallery","Graph gallery…",class="btn-outline-secondary"),
                      actionButton("undo_graph","Undo format",class="btn-outline-secondary",disabled="disabled"),
                      actionButton("redo_graph","Redo format",class="btn-outline-secondary",disabled="disabled"),
                      actionButton("copy_vector","Copy vector",class="btn-primary"),
                      tags$button(type="button",class="btn btn-outline-secondary",`data-graph-action`="copy_graph_style","Reuse style…"),
                      tags$button(type="button",class="btn btn-outline-secondary",`data-graph-action`="new_view","+ View…"),
                      actionButton("fit_curve","Fit curve…",class="btn-outline-secondary"),
                      tags$button(type="button",class="btn btn-outline-secondary",`data-graph-action`="delete_view","Delete view…"))),
                  div(class = "canvas-toolbar", div(span(class = "mini-dot"), "Linked graph", span("Live preview", class = "muted")),
                      selectInput("graph", NULL, c("Individual points" = "points", "Bars + observations" = "bar", "Box plot" = "box", "Violin plot" = "violin", "Paired observations" = "paired"), width = "240px")),
                  div(class = "figure-view-tools",
                    span(id = "figure_dimensions", "3.00 × 3.00 in · 200%"),
                    tags$label(`for` = "figure_zoom", "View ", tags$select(id = "figure_zoom", class = "form-control",
                      tags$option(value = "actual", "100% — actual size"), tags$option(value = "200", selected = TRUE, "200%"), tags$option(value = "fit", "Fit to window")))),
                  div(class = "plot-wrap", id = "figure_viewport", div(id = "figure_stage", imageOutput("figure", width = "288px", height = "288px"))),
                  div(class = "canvas-caption", uiOutput("figure_caption"), span("Click titles to edit · Click axes or data to format", class = "muted"))),
                div(class = "metric-strip", uiOutput("figure_metrics")),
                div(class = "graph-reuse", actionButton("copy_graph_style", "Copy graph formatting…", class = "btn-outline-secondary"), span("Reuse a polished appearance across this study.")),
                div(class = "export-card", div(h3("Ready for the next step?"), p("Export your figure at its final size, or keep an editable project.")),
                    div(class = "export-actions", downloadButton("export_svg", "SVG", class = "btn-outline-secondary"),
                        downloadButton("export_pdf", "PDF", class = "btn-outline-secondary"),
                        downloadButton("export_png", "Export PNG", class = "btn-primary")))),
              tags$aside(id="figure_settings",class = "inspector", div(class = "inspector-title", h3("Figure settings"), span("01")),
                field_section("Labels", textInput("title", "Figure title", "Treatment response"),
                              textInput("x_label", "X axis", "Condition"), textInput("y_label", "Y axis", "Response (a.u.)")),
                field_section("Appearance", selectInput("palette", "Color palette", c("RDataCraft" = "craft", "Colorblind accessible" = "accessible", "Monochrome" = "monochrome")),
                              uiOutput("palette_swatches"),
                              conditionalPanel("['column','xy','grouped'].indexOf(input.layout) !== -1", selectInput("error", "Mean interval (bars / shading)", c("Standard error (SEM)" = "sem", "Standard deviation (SD)" = "sd", "95% confidence interval" = "ci", "None" = "none")),
                              checkboxInput("show_points", "Show individual observations", TRUE)),
                              checkboxInput("show_p", "Show comparison P values", TRUE),
                              selectInput("legend_position", "Legend", c("Automatic" = "auto", "Top" = "top", "Bottom" = "bottom", "Left" = "left", "Right" = "right", "Hidden" = "none")),
                              checkboxInput("grid_lines", "Show major grid lines", FALSE),
                              selectInput("annotation", "P-value labels", c("Numeric P (below 10⁻⁶: P < 10⁻⁶)" = "p", "Significance stars (ns, *, **, ***, ****)" = "stars")),
                              div(class = "two-fields", numericInput("font_size", "Text size (pt)", 7, 4, 24), numericInput("point_size", "Point size", 2.8, 1, 6, 0.2))),
                field_section("Axes & export", conditionalPanel("['column','xy','grouped'].indexOf(input.layout) !== -1", checkboxInput("log_y", "Logarithmic Y axis", FALSE)),
                              conditionalPanel("input.layout === 'xy'", checkboxInput("log_x", "Logarithmic X axis", FALSE)),
                              p(class = "muted", "Blank range limits use automatic scaling. Ranges crop the view; analysis still uses all source observations."),
                              conditionalPanel("['xy','survival','multiple'].indexOf(input.layout) !== -1 || ['histogram','ecdf','qq','density'].indexOf(input.graph) !== -1", div(class = "two-fields", textInput("x_min", "X minimum", ""), textInput("x_max", "X maximum", ""))),
                              conditionalPanel("input.graph !== 'heatmap'", div(class = "two-fields", textInput("y_min", "Y minimum", ""), textInput("y_max", "Y maximum", ""))),
                              div(class = "two-fields", numericInput("x_axis_length", "X axis length (mm; 0 = auto)", 0, 0, 350, .1), numericInput("y_axis_length", "Y axis length (mm; 0 = auto)", 0, 0, 250, .1)),
                              p(class="muted", "Axis lengths measure the plotting area. Leave room for labels within the canvas. Figure layouts fit axes to their panel size."),
                              div(class = "two-fields figure-size-inputs",
                                tags$label(`for` = "figure_width_in", "Width (in)", tags$input(id = "figure_width_in", type = "number", class = "form-control", value = 3, min = 1, max = 400/25.4, step = 0.1)),
                                tags$label(`for` = "figure_height_in", "Height (in)", tags$input(id = "figure_height_in", type = "number", class = "form-control", value = 3, min = 1, max = 300/25.4, step = 0.1))),
                              div(class = "figure-size-internal", numericInput("width", "Width (mm)", 76.2, 25.4, 400), numericInput("height", "Height (mm)", 76.2, 25.4, 300)),
                              selectInput("dpi", "PNG resolution", c("300 dpi" = 300, "600 dpi" = 600, "150 dpi" = 150))),
                div(class = "inspector-foot", "Tip: choose your test in Analysis. Figures and results update together.")))),
          tabPanel("Data", value = "data",
            div(class = "page-heading", div(div(class = "eyebrow", "START WITH YOUR OBSERVATIONS"), h1(uiOutput("data_heading", inline = TRUE)),
              p("Click column names to rename them. Select a cell and press ⌘V (Mac) or Ctrl+V (Windows) to paste; double-click a cell to edit."))),
            div(class = "data-toolbar card-surface",
              selectInput("layout", "Table layout", setNames(unname(pc_layouts()), sub(" ·.*", "", names(pc_layouts())))),
              fileInput("import_data", "Import data", accept = c(".csv", ".tsv", ".txt", ".xlsx"), buttonLabel = "Choose file", placeholder = "CSV, TSV or Excel"),
              fileInput("import_prism","Import Prism file",accept=c(".pzfx",".prism",".pzf"),buttonLabel="Choose Prism file",placeholder="PZFX or PRISM"),
              div(class = "example-buttons", span("Try an example"), actionButton("sample_column", "Treatment groups", class = "btn-outline-secondary"),
                  actionButton("sample_xy", "Time course", class = "btn-outline-secondary"), actionButton("sample_dose", "Dose response", class = "btn-outline-secondary"))),
            div(class = "card-surface data-card", div(class = "section-heading", h3("Source observations"),
                  div(class = "table-actions", actionButton("undo_data", "Undo", class = "btn-outline-secondary", disabled = "disabled", title = "Undo committed data edit"),
                      actionButton("redo_data", "Redo", class = "btn-outline-secondary", disabled = "disabled", title = "Redo committed data edit"), actionButton("manage_table", "Rows & series…", class = "btn-outline-secondary"), actionButton("add_row", "+ Row", class = "btn-outline-secondary"), actionButton("add_group", "+ Column", class = "btn-outline-secondary"),
                      conditionalPanel("input.layout === 'xy'", actionButton("setup_xy", "Y replicates…", class = "btn-outline-secondary")),
                      downloadButton("export_data", "Export CSV", class = "btn-outline-secondary"))),
                  uiOutput("data_note"),
                  div(class = "grid-paste-tools",
                    span(id = "grid_selection", role = "status", `aria-live` = "polite", "Select a cell to paste"),
                    tags$label(tags$input(id = "grid_paste_headers", type = "checkbox"), " First pasted row contains column names")),
                  DT::DTOutput("data_grid")),
            div(class = "card-surface transform-card", h3("Transform observations into a new worksheet"),
                p("The source worksheet is preserved. Choose a transform, then review its derived table and analysis."),
                selectInput("transform_kind", "Transform", c("Percent of selected control mean" = "percent_control", "Log10(Y)" = "log10", "Natural log(Y)" = "ln", "Z score within each numeric column" = "zscore")),
                selectInput("transform_control", "Control column (percent normalization)", c("Control", "Treatment A", "Treatment B")),
                actionButton("apply_transform", "Create transformed worksheet", class = "btn-outline-secondary")),
            tags$details(class = "card-surface paste-card", tags$summary("Advanced: replace the entire table from text"),
                p("Include a header row and follow the table-format guide above. Use a new worksheet template to start a different experiment type."),
                textAreaInput("paste_data", NULL, placeholder = "Control\tTreatment\n8.4\t12.6\n9.7\t14.2", rows = 6, width = "100%"),
                actionButton("apply_paste", "Replace table with pasted data", class = "btn-primary"))),
          tabPanel("Analysis", value = "analysis",
            div(class = "page-heading", div(div(class = "eyebrow", "UNDERSTAND THE DIFFERENCE"), h1(textOutput("analysis_heading", inline = TRUE)),
              p("Choose an analysis deliberately. Review its assumptions alongside the result."))),
            uiOutput("example_guide"),
            div(class="card-surface",actionButton("advanced_open","Advanced R analysis…",class="btn-outline-secondary"),p(class="muted","Use reviewed R scripts for methods beyond the presets. Open the guide for examples and package requirements.")),
            div(class = "card-surface analysis-controls", selectInput("method", "Analysis", pc_methods("column"), selected = "welch"),
                conditionalPanel("['welch','student','paired','mann','signedrank','onesample','linear','pearson','spearman','fourpl','origin','quadratic','cubic','logarithmic','power','exponential','decay','association','michaelis','gaussian'].indexOf(input.method) !== -1", selectInput("group1", "First group / regression series", choices = c("Control", "Treatment A", "Treatment B"))),
                conditionalPanel("input.layout === 'xy' && ['linear','fourpl','origin','quadratic','cubic','logarithmic','power','exponential','decay','association','michaelis','gaussian'].indexOf(input.method) !== -1",
                  selectInput("fit_scope","Fit series",c("Selected series"="selected","All series independently"="all")),
                  selectInput("fit_replicates","Fit replicates",c("Fit individual observations"="individual","Fit mean Y at each X"="mean")),
                  selectInput("fit_weight","Regression weighting",c("Equal weights"="none","1 / Y² (nonzero Y)"="inv_y2","Replicate SD (requires repeated X)"="replicate_sd")),
                  p(class="muted","Models fit the original Y scale. Choose Scatter/curve or Residuals on the Graph page to inspect the fit.")),
                conditionalPanel("['welch','student','paired','mann','signedrank'].indexOf(input.method) !== -1", selectInput("group2", "Second group", choices = c("Treatment A", "Control", "Treatment B"))),
                conditionalPanel("input.method === 'onesample'", numericInput("null_mean", "Hypothesized population mean", 0)),
                conditionalPanel("['multiple','kruskal','simpleeffects'].indexOf(input.method) !== -1", selectInput("correction", "Multiple-comparison correction", c("Holm (family-wise error)" = "holm", "Bonferroni (family-wise error)" = "bonferroni", "Benjamini–Hochberg (false discovery rate)" = "BH")))),
            conditionalPanel("input.layout === 'multiple'",div(class="card-surface pca-controls",h3("PCA settings"),
              actionButton("show_pca_guide","PCA example & analysis guide",class="btn-outline-secondary"),
              p("Rows are observations. Select numeric measurements; exclude sample IDs and group codes. Variables are always mean-centered."),
              selectizeInput("pca_variable_pick","Variables included in PCA",choices=NULL,multiple=TRUE,options=list(plugins=list("remove_button"))),
              div(class="pca-control-grid",
                checkboxInput("pca_scale","Scale each variable to unit SD",TRUE),
                selectInput("pca_missing","Missing values",c("Stop and ask me to resolve missing values"="error","Exclude incomplete rows (no imputation)"="complete")),
                selectInput("pca_label_column","Sample label column",c("None"="")),
                selectInput("pca_group_column","Group/color column (metadata only)",c("None"="")),
                numericInput("pca_x","Horizontal component (PC)",1,1,50,1),numericInput("pca_y","Vertical component (PC)",2,1,50,1),
                checkboxInput("pca_labels","Label score points with sample names",FALSE)),
              actionButton("add_pca_views","Add three linked PCA graph views",class="btn-outline-secondary"),
              p(class="muted","Group labels only color points; they do not affect the fit. Scores and loadings use the two selected components. Scree shows all components."))),
            div(class = "analysis-layout", div(class = "card-surface", h3("Analysis results"), uiOutput("analysis_status"), tableOutput("analysis_metrics")),
                div(class = "card-surface assumptions", h3("Method & assumptions"), uiOutput("analysis_notes"))),
            div(class = "card-surface", div(class = "section-heading", h3("Summary & diagnostics"), div(downloadButton("export_report", "Analysis report", class = "btn-outline-secondary"), downloadButton("export_summary", "Summary CSV", class = "btn-outline-secondary"), downloadButton("export_results", "Analysis JSON", class = "btn-outline-secondary"))),
                p(class = "muted", "Column/XY means use Student’s t 95% intervals. Survival estimates, AUC, and diagnostic summaries follow the chosen analysis."), tableOutput("descriptive_table")),
            conditionalPanel("input.layout === 'multiple' && input.method === 'pca'",div(class="card-surface pca-results",h3("PCA results"),
              h4("Explained variance"),downloadButton("export_pca_scree","Variance CSV",class="btn-outline-secondary"),tableOutput("pca_scree"),
              h4("Observation scores"),downloadButton("export_pca_scores","Scores CSV",class="btn-outline-secondary"),DT::DTOutput("pca_scores"),
              h4("Variable loadings (eigenvector coefficients)"),downloadButton("export_pca_loadings","Loadings CSV",class="btn-outline-secondary"),DT::DTOutput("pca_loadings"),
              h4("Centering and scaling"),downloadButton("export_pca_preprocessing","Preprocessing CSV",class="btn-outline-secondary"),tableOutput("pca_preprocessing"))),
            div(class = "card-surface", h3("Comparisons & model details"), p("P values marked as adjusted belong to the displayed comparison family. Only Tukey intervals are simultaneous; other comparison intervals are individual 95% intervals."), downloadButton("export_comparisons", "Comparisons CSV", class = "btn-outline-secondary"), downloadButton("export_residuals", "Fit residuals CSV", class="btn-outline-secondary"), tableOutput("comparison_table"), tableOutput("effects_table"), tableOutput("parameters_table"), tableOutput("fit_status_table"), tableOutput("risk_table"))),
          tabPanel("Layout", value = "layout",
            div(class = "page-heading", div(div(class = "eyebrow", "ASSEMBLE A FIGURE"), h1("Figure layout"), p("Arrange linked graph views into labeled panels. Source edits update every panel."))),
            div(class = "card-surface layout-controls",
              textInput("layout_title", "Layout title", "Figure layout"),
              selectInput("layout_columns", "Columns", c("1 column" = 1, "2 columns" = 2, "3 columns" = 3), selected = 2),
              numericInput("layout_width", "Width (mm)", 180, 60, 400), numericInput("layout_height", "Height (mm)", 220, 50, 400),
              selectInput("layout_dpi", "PNG resolution", c("150 dpi" = 150, "300 dpi" = 300, "600 dpi" = 600), selected = 300)),
            div(class = "card-surface", div(class = "section-heading", h3("Select panels (up to eight)"), actionButton("layout_use_views", "Use this worksheet’s views", class = "btn-outline-secondary")),
              checkboxGroupInput("layout_views", NULL, choices = character(), inline = TRUE),
              tags$details(tags$summary("All linked views"), tableOutput("view_catalog"))),
            div(class="layout-workspace",
              div(class="card-surface layout-preview",
                div(class="layout-tools",tags$button(type="button",class="btn btn-outline-secondary",`data-layout-template`="grid","Equal grid"),
                  tags$button(type="button",class="btn btn-outline-secondary",`data-layout-template`="hero","Large top panel"),
                  actionButton("undo_layout","Undo layout",class="btn-outline-secondary",disabled="disabled"),actionButton("redo_layout","Redo layout",class="btn-outline-secondary",disabled="disabled"),
                  tags$label(tags$input(id="layout_snap",type="checkbox",checked="checked")," Snap to 1 mm")),
                div(id="layout_edit_status",role="status","Select panels to start. Drag a panel to move it; drag its lower-right corner to resize."),
                div(id="layout_stage",imageOutput("layout_figure",height="auto"),div(id="layout_handles"))),
              tags$aside(class="card-surface panel-inspector",h3("Panel inspector"),p(id="layout_panel_name","Click a panel on the page."),
                tags$form(id="layout_panel_form",
                  tags$label("Panel label",tags$input(id="panel_label",class="form-control",maxlength=20)),
                  div(class="two-fields",lapply(c(x="Left",y="Top",w="Width",h="Height"),function(label) tags$label(paste(label,"(mm)"),tags$input(id=paste0("panel_",names(c(x="Left",y="Top",w="Width",h="Height"))[match(label,c("Left","Top","Width","Height"))]),type="number",class="form-control",step=.5,min=0)))),
                  tags$button(type="submit",class="btn btn-primary","Apply panel size / position")),
                div(class="layout-order-tools",tags$button(type="button",class="btn btn-outline-secondary",`data-layout-order`="earlier","Earlier"),tags$button(type="button",class="btn btn-outline-secondary",`data-layout-order`="later","Later")),
                numericInput("layout_gap","Panel gap (mm)",4,0,20,.5),numericInput("layout_margin","Page margin (mm)",4,0,30,.5),numericInput("layout_label_size","Panel label size (pt)",14,8,32),
                checkboxInput("layout_scale_text","Reduce graph text to fit columns",TRUE),
                p(class="muted","Page positions and sizes are saved in millimetres and used by SVG, PDF and PNG exports. Earlier/Later changes label and grid order; manual positions stay with their graphs."))),
            div(class = "card-surface export-actions", downloadButton("export_layout_svg", "Layout SVG", class = "btn-outline-secondary"), downloadButton("export_layout_pdf", "Layout PDF", class = "btn-outline-secondary"), downloadButton("export_layout_png", "Layout PNG", class = "btn-primary"))),
          tabPanel("Project", value = "project",
            div(class = "page-heading", div(div(class = "eyebrow", "MAKE YOUR WORK REPRODUCIBLE"), h1("Project information"),
              p("Save your original table, analysis settings, and figure styling together."))),
            div(class = "analysis-layout", div(class = "card-surface", h3("Open a saved project"),
                p("RDataCraft projects are readable JSON files. Opening one replaces the current table and settings."),
                fileInput("open_project", "Project file", accept = c(".json", ".rdatacraft", ".plotcraft"), placeholder = "Choose a RDataCraft project"),
                downloadButton("save_project_copy", "Save current project", class = "btn-primary")),
              div(class = "card-surface", h3("About this version"),
                  p("RDataCraft v0.31 · Scientific plotting and statistics"),
                  p("R-powered data analysis and publication-ready figures for Mac and Windows."),
                  p("Six table types including PCA, named worksheets, matched and independent group tests, factorial ANOVA, correlation, dose-response fitting, survival analysis, categorical tests, diagnostic graphs, and reproducible reports."),
                  p("Treat each row as an independent experimental unit unless using a paired test. Technical replicates must not be counted as independent biological replicates."),
                  p("This preview has automated numerical and workflow checks. Broader validation against reference scientific datasets remains ongoing."))),
            div(class="card-surface",h3("Prism import history"),p("This records the conversion performed at import time. Current analyses recompute from the editable working tables."),uiOutput("prism_import_history"),downloadButton("export_import_history","Save import report…",class="btn-outline-secondary")),
            div(class="card-surface",h3("Preserved Prism originals"),
              p("Original analyses, graphs and layouts remain in the attached Prism file. Supported conversions rerun in their RDataCraft working tables. Unsupported original outputs remain available in Prism."),
              uiOutput("prism_originals")),
            div(class = "card-surface", h3("Open source foundations"),
                p("RDataCraft application code is licensed under GNU GPL version 3. Third-party components retain their own licenses and authorship."),
                tags$ul(tags$li("Plot styling and significance annotations — original RDataCraft code; GPL v3."),
                        tags$li("R — R Core Team; GPL v2 or v3."), tags$li("ggplot2, Shiny, bslib, DT, readxl, jsonlite and svglite — see the included dependency manifest and licenses.")),
                p("RDataCraft is an independent project and is not affiliated with GraphPad."),
                verbatimTextOutput("environment_info"))))))))

server <- function(input, output, session) {
  sheets <- reactiveVal(list())
  active_sheet <- reactiveVal("D1")
  restoring_settings <- reactiveVal(NULL)
  views <- reactiveVal(NULL)
  active_view <- reactiveVal("V1")
  layout_pending <- reactiveVal(NULL)
  layout_revision <- reactiveVal(0L)
  layout_design <- reactiveVal(list(arrangement="grid",positions="{}",labels="{}"))
  layout_order <- reactiveVal(character())
  graph_history <- reactiveVal(list())
  graph_last <- reactiveVal(list())
  graph_skip <- reactiveVal(NULL)
  deleting_table <- reactiveVal(NULL)
  gallery_target <- reactiveVal(NULL)
  layout_history <- reactiveVal(list(undo=list(),redo=list()))
  sheet_name <- reactiveVal("Observation table")
  document_open <- reactiveVal(FALSE)
  prism_sources <- reactiveVal(list())
  import_reports <- reactiveVal(list())
  r_analyses <- reactiveVal(list())
  observe({session$sendCustomMessage("rdatacraft-welcome",document_open())})
  raw <- reactiveVal(data.frame(Control=rep(NA_character_,6),Treatment=rep(NA_character_,6)))
  grid_generation <- reactiveVal(0L)
  page <- reactiveVal("data")
  project_name <- reactiveVal("Untitled study")
  project_path <- reactiveVal("")
  saved_signature <- reactiveVal(NULL)
  document_revision <- reactiveVal(0L)
  data_history <- reactiveVal(list())
  history_layout <- reactiveVal(list())
  current_layout <- function() {target <- isolate(restoring_settings()); if (is.null(target)) isolate(input$layout) else target$layout}
  sync_header_refs <- function(before,after) {
    if(ncol(before)!=ncol(after) || identical(names(before),names(after)) || setequal(names(before),names(after))) return()
    all<-isolate(view_book())
    for(id in names(all)) all[[id]]$settings<-pc_rename_header_settings(all[[id]]$settings,before,after)
    views(all);update_settings(all[[isolate(active_view())]]$settings)
  }
  commit_data <- function(tab, label) {
    tab <- pc_check_table(tab)
    if (identical(pc_table_text(tab), pc_table_text(isolate(raw())))) return(invisible(FALSE))
    all <- isolate(data_history()); id <- isolate(active_sheet())
    all[[id]] <- pc_history_record(all[[id]], pc_table_text(isolate(raw())), label, current_layout())
    sync_header_refs(isolate(raw()),tab)
    document_open(TRUE)
    data_history(all); raw(tab)
    invisible(TRUE)
  }
  step_data <- function(direction) {
    all <- isolate(data_history()); id <- isolate(active_sheet())
    result <- pc_history_step(all[[id]], pc_table_text(isolate(raw())), direction, current_layout())
    if (is.null(result)) return()
    sync_header_refs(isolate(raw()),result$table)
    all[[id]] <- result$history; data_history(all); raw(result$table)
  }
  observeEvent(input$undo_data, tryCatch(step_data("undo"), error = notify_error))
  observeEvent(input$redo_data, tryCatch(step_data("redo"), error = notify_error))
  observeEvent(list(data_history(), active_sheet()), {
    h <- data_history()[[active_sheet()]]; if (is.null(h)) h <- pc_history()
    session$sendCustomMessage("rdatacraft-history", list(undo = length(h$undo) > 0, redo = length(h$redo) > 0,
      undo_label = if (length(h$undo)) tail(h$undo, 1)[[1]]$label else "", redo_label = if (length(h$redo)) tail(h$redo, 1)[[1]]$label else ""))
  })
  observeEvent(list(active_sheet(), input$layout, restoring_settings()), {
    id <- active_sheet(); layout <- current_layout(); if (is.null(layout)) return()
    layouts <- isolate(history_layout()); old <- layouts[[id]]
    if (!is.null(old) && !identical(old, layout)) {
      all <- isolate(data_history()); all[[id]] <- NULL; data_history(all)
    }
    layouts[[id]] <- layout; history_layout(layouts)
  })
  observeEvent(project_name(), session$sendCustomMessage("rdatacraft-study-name", project_name()))
  observeEvent(input$rename_study, {
    tryCatch(project_name(pc_study_name(input$rename_study$name)), error = function(e) {
      showNotification(conditionMessage(e), type = "error")
    })
    session$sendCustomMessage("rdatacraft-study-name", project_name())
  })
  output$data_heading <- renderUI(tagList(span(paste0(active_sheet(), " · ")), pc_table_name_button(active_sheet(), sheet_name())))
  output$analysis_heading <- renderText(paste(sub("D", "R", active_sheet()), sheet_name(), view_book()[[active_view()]]$name, sep = " · "))
  output$figure_heading <- renderText(paste(sub("D", "G", active_sheet()), sheet_name(), view_book()[[active_view()]]$name, sep = " · "))
  observeEvent(active_sheet(), session$sendCustomMessage("rdatacraft-sheet", active_sheet()))
  for (destination in c("figure", "data", "analysis", "layout", "project", "advanced")) local({
    dest <- destination
    observeEvent(input[[paste0("nav_", dest)]], {
      updateTabsetPanel(session, "workspace", selected = dest); page(dest)
      session$sendCustomMessage("rdatacraft-page", dest)
    })
  })
  observeEvent(input$edit_data, { updateTabsetPanel(session, "workspace", selected = "data"); page("data"); session$sendCustomMessage("rdatacraft-page", "data") })
  output$page_title <- renderText(switch(page(), figure = "Figure studio", data = "Data table", analysis = "Analysis", layout = "Figure layout", project = "Project & sources", advanced="Advanced R analysis"))
  notify_error <- function(e) showNotification(conditionMessage(e), type = "error", duration = 10)
  grid_identity <- reactive({
    target <- restoring_settings(); layout <- if (is.null(target)) input$layout else target$layout
    list(sheet = active_sheet(), token = digest::digest(list(raw(), active_sheet(), layout, grid_generation()), algo = "xxhash64"))
  })
  observeEvent(input$grid_paste, {
    paste <- input$grid_paste
    tryCatch({
      identity <- grid_identity()
      if (!identical(paste$sheet, identity$sheet) || !identical(paste$token, identity$token))
        stop("The table changed before the paste arrived. Select a cell and paste again.")
      tab <- pc_paste_cells(raw(), paste$text, paste$row, paste$column, current_layout(), isTRUE(paste$headers))
      commit_data(tab, "paste cells")
      session$sendCustomMessage("rdatacraft-paste-result", list(ok = TRUE, message = "Pasted cells. Undo restores the previous table."))
    }, error = function(e) {
      notify_error(e)
      session$sendCustomMessage("rdatacraft-paste-result", list(ok = FALSE, message = paste("Paste rejected:", conditionMessage(e))))
    })
  })
  observeEvent(input$apply_paste, tryCatch({ tab <- pc_read_text(input$paste_data); pc_normalize(tab, input$layout, allow_empty = TRUE); commit_data(tab, "replace pasted data"); showNotification("Table updated.", type = "message") }, error = notify_error))
  import_table <- function(path, name) {
    tab <- pc_import_file(path, name)
    pc_normalize(tab, input$layout, allow_empty = TRUE); commit_data(tab, "import data")
    showNotification(paste("Imported", name), type = "message")
  }
  observeEvent(input$import_data, tryCatch(import_table(input$import_data$datapath, input$import_data$name), error = notify_error))
  observeEvent(input$desktop_import_data, tryCatch(import_table(input$desktop_import_data$path, basename(input$desktop_import_data$path)), error = notify_error))
  table_edit_target <- reactiveVal(NULL)
  observeEvent(input$manage_table, {
    table_edit_target(grid_identity())
    groups <- pc_table_series(raw(), current_layout())
    showModal(modalDialog(title = "Manage rows and data series", size = "l",
      p(paste(nrow(raw()), "rows ·", ncol(raw()), "columns. Each change is one Undo action. Linked graphs and results update from the edited source.")),
      tabsetPanel(id = "table_edit_tab",
        tabPanel("Rows", value = "rows",
          selectInput("row_edit_action", "Action", c("Insert blank rows before"="insert", "Delete rows starting at"="delete")),
          numericInput("row_edit_first", "Starting row (1-based)", 1, min=1, max=nrow(raw())+1, step=1),
          numericInput("row_edit_count", "Number of rows", 1, min=1, max=10000, step=1),
          p(class="muted","Column rows preserve subject matching when inserted or deleted across every column. Grouped rows require factor labels; use + Row and fill labels to add a grouped observation.")),
        tabPanel("Data series", value = "series",
          if (!length(groups)) p("Series management is available for Column and XY source tables. Factor labels, count categories and survival fields can be edited in the grid.") else tagList(
            selectInput("series_edit_target", "Source series", groups),
            selectInput("series_edit_action", "Action", c("Rename"="rename", "Move left"="left", "Move right"="right", "Delete series and its observations"="delete")),
            textInput("series_edit_name", "New name (rename only)", groups[1]),
            p(class="muted","XY replicate subcolumns move, rename and delete together. X is preserved. Keep at least one Y series.")))),
      footer=tagList(modalButton("Cancel"),actionButton("confirm_table_edit","Apply table change",class="btn-primary"))))
  })
  observeEvent(input$confirm_table_edit, tryCatch({
    if (!identical(table_edit_target(),grid_identity())) stop("The source table changed. Reopen Rows & series before editing.")
    if (identical(input$table_edit_tab,"rows")) {
      if (current_layout()=="grouped" && input$row_edit_action=="insert") stop("Grouped rows need factor labels. Use + Row, then enter the labels and values.")
      candidate <- pc_edit_rows(raw(),current_layout(),input$row_edit_action,input$row_edit_first,input$row_edit_count)
      label <- paste(input$row_edit_action,input$row_edit_count,"rows")
    } else {
      candidate <- pc_edit_series(raw(),current_layout(),input$series_edit_action,input$series_edit_target,input$series_edit_name)
      label <- paste(input$series_edit_action,"series",input$series_edit_target)
    }
    commit_data(candidate,label);removeModal()
  }, error=notify_error))
  observeEvent(input$add_row, {
    tab <- raw(); if (nrow(tab) >= 10000) return()
    tab[nrow(tab) + 1L, ] <- NA_character_
    if (identical(current_layout(), "contingency")) {
      label <- paste("Category", nrow(tab)); while (label %in% head(tab[[1]], -1)) label <- paste0(label, " new")
      tab[nrow(tab), 1] <- label; tab[nrow(tab), -1] <- "0"
    }
    commit_data(tab, "add row")
  })
  observeEvent(input$add_group, showModal(modalDialog(title = if (current_layout() == "xy") "Add a Y series" else "Add a data column", textInput("new_group_name", "Column / series name", paste("Group", ncol(raw()) + 1L)), footer = tagList(modalButton("Cancel"), actionButton("confirm_add_group", "Add", class = "btn-primary")))))
  observeEvent(input$confirm_add_group, tryCatch({
    if (identical(current_layout(), "survival")) stop("Survival tables use exactly three columns: Time, Status, and Group.")
    tab <- raw(); name <- trimws(input$new_group_name)
    if (identical(current_layout(), "xy")) {
      spec <- pc_xy_structure(tab)
      if (!nzchar(name) || name %in% spec$groups || grepl(" \\[rep [0-9]+\\]$", name) || ncol(tab) + spec$n > 50) stop("Choose a new series name that fits the 50-column limit.")
      for (i in seq_len(spec$n)) tab[[if (spec$n == 1L) name else paste0(name, " [rep ", i, "]")]] <- NA_character_
      commit_data(tab, "add Y series"); removeModal(); return()
    }
    if (!nzchar(name) || name %in% names(tab) || ncol(tab) >= 50) stop("Choose a unique nonempty header (up to 50 columns).")
    tab[[name]] <- if (identical(current_layout(), "contingency")) "0" else NA_character_; commit_data(tab, "add column"); removeModal()
  }, error = notify_error))
  observeEvent(input$setup_xy, tryCatch({
    if (current_layout() != "xy") stop("Choose an XY table first.")
    spec <- pc_xy_structure(raw())
    showModal(modalDialog(title = "Y replicates per X value",
      p("Each Y series shares one X column and contains this many side-by-side replicate subcolumns. Existing values stay in their current replicate; new cells are blank."),
      numericInput("xy_replicates", "Replicate subcolumns per Y series", spec$n, min = 1, max = floor(49 / length(spec$groups)), step = 1),
      p(class = "muted", "Mean plots calculate SD, SEM or 95% CI from the observed replicates at each X. Fitting uses individual observations; technical repeats are not independent biological samples."),
      footer = tagList(modalButton("Cancel"), actionButton("confirm_xy_replicates", "Apply replicate columns", class = "btn-primary"))))
  }, error = notify_error))
  observeEvent(input$confirm_xy_replicates, tryCatch({
    if (current_layout() != "xy") stop("Choose an XY table first.")
    tab <- pc_xy_replicates(raw(), input$xy_replicates)
    commit_data(tab, "set Y replicate columns")
    if (input$xy_replicates > 1) updateSelectInput(session, "graph", selected = "xymean")
    removeModal()
  }, error = notify_error))
  load_example <- function(file, layout, title, x_label, y_label, method) {
    all <- isolate(data_history()); all[[active_sheet()]] <- NULL; data_history(all)
    document_open(TRUE)
    raw(pc_read_text(paste(readLines(file), collapse = "\n")))
    updateSelectInput(session, "layout", selected = layout)
    updateCheckboxInput(session, "log_x", value = FALSE); updateCheckboxInput(session, "log_y", value = FALSE)
    updateTextInput(session, "title", value = title); updateTextInput(session, "x_label", value = x_label); updateTextInput(session, "y_label", value = y_label)
    updateSelectInput(session, "method", choices = pc_methods(layout), selected = method)
  }
  observeEvent(input$sample_column, load_example("examples/treatment.csv", "column", "Treatment response", "Condition", "Response (a.u.)", "welch"))
  observeEvent(input$sample_dose, {
    load_example("examples/dose-response.csv", "xy", "Dose-response curve", "Concentration", "Response", "fourpl")
    updateCheckboxInput(session, "log_x", value = TRUE)
    updateSelectInput(session, "graph", selected = "scatter")
  })
  observeEvent(input$sample_xy, load_example("examples/xy.csv", "xy", "Response over time", "Time (hours)", "Response (a.u.)", "linear"))
  observeEvent(input$data_grid_cell_edit, tryCatch({
    edit <- input$data_grid_cell_edit
    tab <- raw()
    if (edit$row < 1 || edit$row > nrow(tab) || edit$col < 0 || edit$col >= ncol(tab)) stop("Invalid cell.")
    tab[edit$row, edit$col + 1] <- if (trimws(edit$value) == "") NA_character_ else edit$value
    pc_normalize(tab, input$layout, allow_empty = TRUE, allow_incomplete = identical(input$layout, "survival"))
    commit_data(tab, "edit cell")
  }, error = function(e) { notify_error(e); DT::replaceData(DT::dataTableProxy("data_grid"), raw(), resetPaging = FALSE, rownames = FALSE) }))
  observeEvent(input$rename_column,tryCatch({
    e <- input$rename_column; identity <- grid_identity()
    if(!identical(e$sheet,identity$sheet) || !identical(e$token,identity$token)) stop("The table changed. Select the current header again.")
    candidate <- pc_rename_header(raw(),current_layout(),e$column,e$name)
    commit_data(candidate,"rename column")
    session$sendCustomMessage("rdatacraft-header",list(ok=TRUE,message="Column name updated. Undo restores the previous name."))
  },error=function(e) {notify_error(e);session$sendCustomMessage("rdatacraft-header",list(ok=FALSE,message=conditionMessage(e)))}))
  output$data_grid <- DT::renderDT({
    position <- isolate(input$grid_page)
    start <- if (!is.null(position) && identical(position$sheet, active_sheet()) &&
      is.numeric(position$start) && length(position$start) == 1L && is.finite(position$start))
      max(0, min(floor(position$start / 12) * 12, floor((nrow(raw()) - 1) / 12) * 12)) else 0
    header <- pc_grid_header(raw(),current_layout())
    DT::datatable(raw(), rownames = FALSE, editable = "cell", selection = "none", escape = TRUE, container = header,
      callback = DT::JS(paste0("window.RDataCraftGrid.bind(table,", jsonlite::toJSON(grid_identity(), auto_unbox = TRUE), ");")),
      options = list(pageLength = 12, lengthChange = FALSE, searching = FALSE, ordering = FALSE,
                     displayStart = start, scrollX = TRUE, dom = "tip", language = list(emptyTable = "Add observations to begin.")))
  }, server = TRUE)
  normalized <- reactive({
    target <- restoring_settings()
    layout <- if (is.null(target)) input$layout else target$layout
    tryCatch(pc_normalize(raw(), layout, allow_empty = TRUE), error = function(e) validate(need(FALSE, conditionMessage(e))))
  })
  # One observer coordinates layout, methods, and group choices. Pending project settings
  # are applied after dynamic choices so restored settings are not overwritten.
  pending <- reactiveVal(NULL)
  restore_revision <- reactiveVal(0L)
  observeEvent(list(raw(), input$layout, restore_revision()), {
    restore <- isolate(pending())
    if (!is.null(restore) && !identical(input$layout, restore$layout)) return()
    n <- tryCatch(pc_normalize(raw(), input$layout, allow_empty = TRUE), error = function(e) NULL)
    req(n)
    method <- if (!is.null(restore)) restore$method else isolate(input$method)
    if (is.null(method) || !method %in% unname(pc_methods(n$layout))) method <- if(n$layout=="multiple") "pca" else "descriptive"
    graphs <- pc_graphs(n$layout)
    graph <- if (!is.null(restore)) restore$graph else isolate(input$graph)
    if (is.null(graph) || !graph %in% graphs) graph <- unname(graphs)[1]
    first <- if (!is.null(restore)) restore$group1 else isolate(input$group1)
    second <- if (!is.null(restore)) restore$group2 else isolate(input$group2)
    if (is.null(first) || !first %in% n$groups) first <- if (length(n$groups)) n$groups[1] else ""
    if (is.null(second) || !second %in% n$groups) second <- if (length(n$groups)) n$groups[min(2, length(n$groups))] else ""
    updateSelectInput(session, "graph", choices = graphs, selected = graph)
    updateSelectInput(session, "method", choices = pc_methods(n$layout), selected = method)
    updateSelectInput(session, "transform_control", choices = n$groups)
    updateSelectInput(session, "group1", choices = n$groups, selected = first)
    updateSelectInput(session, "group2", choices = n$groups, selected = second)
    if (!is.null(restore)) {
      restore$method <- method; restore$graph <- graph; restore$group1 <- first; restore$group2 <- second
      restoring_settings(restore); pending(NULL)
    }
  }, ignoreInit = FALSE)
  observeEvent(list(input$layout, input$graph), {
    numeric_x <- input$layout %in% c("xy", "survival", "multiple") || input$graph %in% c("histogram", "ecdf", "qq", "density")
    if (!numeric_x) {updateTextInput(session, "x_min", value = ""); updateTextInput(session, "x_max", value = "")}
    if (identical(input$graph, "heatmap")) {updateTextInput(session, "y_min", value = ""); updateTextInput(session, "y_max", value = "")}
  }, ignoreInit = TRUE)
  settings <- reactive({
    defaults <- pc_defaults()
    target <- restoring_settings()
    s <- if (is.null(target)) setNames(lapply(names(defaults), function(k) if (is.null(input[[k]])) defaults[[k]] else input[[k]]), names(defaults)) else target
    s$dpi <- as.numeric(s$dpi)
    for (k in c("width", "height", "font_size", "point_size", "dpi")) validate(need(is.numeric(s[[k]]) && length(s[[k]]) == 1 && is.finite(s[[k]]) && s[[k]] > 0, paste("Enter a positive", k)))
    validate(need(s$width <= 400 && s$height <= 300 && s$dpi <= 600, "Export is limited to 400 × 300 mm at 600 dpi."))
    tryCatch(pc_validate_axes(s), error = function(e) validate(need(FALSE, conditionMessage(e))))
    s
  })
  view_book <- reactive(pc_views(settings(), views(), active_view()))
  workbook <- reactive({
    book <- sheets(); book[[active_sheet()]] <- pc_sheet(raw(), settings(), sheet_name(), view_book(), active_view()); book
  })
  layout_settings <- reactive({
    selected <- intersect(if(is.null(input$layout_views)) character() else input$layout_views,pc_view_catalog(workbook())$key)
    selected <- c(intersect(layout_order(),selected),setdiff(selected,layout_order()))
    pc_layout_settings(c(list(selected=selected,
      columns=as.numeric(if(is.null(input$layout_columns)) 2 else input$layout_columns),title=if(is.null(input$layout_title)) "Figure layout" else input$layout_title,
      width=if(is.null(input$layout_width)) 180 else input$layout_width,height=if(is.null(input$layout_height)) 220 else input$layout_height,
      dpi=as.numeric(if(is.null(input$layout_dpi)) 300 else input$layout_dpi),gap=if(is.null(input$layout_gap)) 4 else input$layout_gap,
      margin=if(is.null(input$layout_margin)) 4 else input$layout_margin,label_size=if(is.null(input$layout_label_size)) 14 else input$layout_label_size,
      scale_text=if(is.null(input$layout_scale_text)) TRUE else input$layout_scale_text),layout_design()))
  })
  snapshot <- reactive({req(document_open());pc_project(raw(), settings(), workbook(), active_sheet(), layout_settings(), project_name(), prism_sources(), import_reports(), r_analyses())})
  signature <- reactive(pc_signature(raw(), settings(), workbook(), active_sheet(), layout_settings(), project_name(), prism_sources(), import_reports(), r_analyses()))
  catalog <- reactive(pc_view_catalog(workbook()))
  observeEvent(list(catalog(), layout_revision()), {
    c <- catalog(); requested <- isolate(layout_pending())
    selected <- if (is.null(requested)) isolate(input$layout_views) else requested
    updateCheckboxGroupInput(session, "layout_views", choices = setNames(c$key, paste(c$worksheet, c$name, sep = " · ")), selected = intersect(selected, c$key))
    if (!is.null(requested)) layout_pending(NULL)
  })
  observeEvent(input$layout_use_views, {
    c <- catalog(); updateCheckboxGroupInput(session, "layout_views", selected = head(c$key[c$worksheet == active_sheet()], 8))
  })
  output$view_catalog <- renderTable({d <- catalog()[, c("worksheet", "name", "method", "graph")]; names(d) <- c("Worksheet", "Linked view", "Analysis", "Graph"); d}, striped = TRUE)
  layout_token <- reactive(digest::digest(jsonlite::toJSON(list(layout_settings(),workbook(),grid_generation()),auto_unbox=TRUE,digits=15,na="null"),serialize=FALSE,algo="xxhash64"))
  layout_grob <- reactive({s <- layout_settings();pc_compose_layout(pc_layout_plots(workbook(),s$selected),s)})
  apply_layout <- function(s) {
    layout_order(s$selected);layout_design(s[c("arrangement","positions","labels")])
    updateCheckboxGroupInput(session,"layout_views",selected=s$selected)
    for(k in c("gap","margin","label_size","width","height")) updateNumericInput(session,paste0("layout_",k),value=s[[k]])
    updateTextInput(session,"layout_title",value=s$title);updateSelectInput(session,"layout_columns",selected=s$columns);updateSelectInput(session,"layout_dpi",selected=s$dpi)
    updateCheckboxInput(session,"layout_scale_text",value=s$scale_text)
  }
  observeEvent(input$layout_edit,tryCatch({
    e <- input$layout_edit;if(!identical(e$token,layout_token())) stop("The figure changed. Select its current panel again.")
    before <- layout_settings();after <- pc_layout_apply_edit(before,e)
    h <- layout_history();h$undo <- tail(c(h$undo,list(before)),30);h$redo <- list();layout_history(h);apply_layout(after)
    session$sendCustomMessage("rdatacraft-layout-edit",list(ok=TRUE,message="Layout updated."))
  },error=function(e) {notify_error(e);session$sendCustomMessage("rdatacraft-layout-edit",list(ok=FALSE,message=conditionMessage(e)))}))
  step_layout <- function(direction) {
    h <- layout_history();stack <- h[[direction]];if(!length(stack)) return()
    next_state <- tail(stack,1)[[1]];next_state$selected <- intersect(next_state$selected,catalog()$key)
    h[[direction]] <- head(stack,-1);other <- if(direction=="undo") "redo" else "undo";h[[other]] <- tail(c(h[[other]],list(layout_settings())),30)
    layout_history(h);apply_layout(next_state)
  }
  observeEvent(input$undo_layout,tryCatch(step_layout("undo"),error=notify_error))
  observeEvent(input$redo_layout,tryCatch(step_layout("redo"),error=notify_error))
  observeEvent(layout_history(),session$sendCustomMessage("rdatacraft-layout-history",list(undo=length(layout_history()$undo)>0,redo=length(layout_history()$redo)>0)))
  output$layout_figure <- renderImage({
    s <- layout_settings()
    svg <- tryCatch(pc_layout_svg(pc_layout_plots(workbook(),s$selected),s,list(token=layout_token(),names=setNames(as.list(catalog()$name),catalog()$key))),error=function(e) validate(need(FALSE,conditionMessage(e))))
    file <- tempfile(fileext=".svg");writeLines(svg,file,useBytes=TRUE)
    list(src=file,contentType="image/svg+xml",alt="Editable linked graph layout",width="100%")
  },deleteFile=TRUE)
  observeEvent(list(views(), active_view()), {
    all <- isolate(view_book()); updateSelectInput(session, "graph_view", choices = setNames(names(all), vapply(all, function(v) v$name, character(1))), selected = active_view())
  })
  observeEvent(list(sheets(), active_sheet(), sheet_name()), {
    book <- isolate(workbook()); choices <- setNames(names(book), vapply(names(book), function(id) paste(id, book[[id]]$name, sep = " · "), character(1)))
    updateSelectInput(session, "worksheet", choices = choices, selected = active_sheet())
  })
  observeEvent(c(list(restoring_settings()),lapply(names(pc_defaults()),function(key) input[[key]])), {
    target <- restoring_settings(); req(!is.null(target))
    scalar <- function(x) if (is.null(x) || !length(x)) "" else as.character(x)
    if (all(vapply(names(pc_defaults()), function(key) identical(scalar(input[[key]]), scalar(target[[key]])), logical(1)))) restoring_settings(NULL)
  })
  update_settings <- function(s) {
    restoring_settings(s); pending(s); restore_revision(isolate(restore_revision()) + 1L)
    for (key in names(s)) {
      v <- s[[key]]
      if (key %in% c("layout", "method", "graph", "error", "palette", "dpi", "group1", "group2", "correction", "annotation", "legend_position", "pca_missing", "pca_label_column", "pca_group_column")) updateSelectInput(session, key, selected = v)
      else if (key %in% c("fit_weight","fit_replicates","fit_scope")) updateSelectInput(session,key,selected=v)
      else if (is.logical(v)) updateCheckboxInput(session, key, value = v)
      else if (is.numeric(v)) updateNumericInput(session, key, value = v)
      else updateTextInput(session, key, value = v)
    }
  }
  apply_sheet <- function(tab, s, linked = NULL, vid = "V1") {
    views(linked); active_view(vid); raw(tab); update_settings(s)
  }
  observeEvent(input$graph_view, {
    id <- input$graph_view; if (id == active_view()) return()
    all <- isolate(view_book()); req(id %in% names(all))
    target <- all[[id]]$settings; views(all); active_view(id); update_settings(target)
  })
  observeEvent(input$new_view, showModal(modalDialog(title = "New linked analysis / graph view", p("This view shares the source observations. Its analysis and appearance settings can differ."), textInput("new_view_name", "View name", "Alternative view"), footer = tagList(modalButton("Cancel"), actionButton("confirm_new_view", "Create view", class = "btn-primary")))))
  observeEvent(input$confirm_new_view, tryCatch({
    name <- trimws(input$new_view_name); if (!nzchar(name) || nchar(name) > 100) stop("Enter a view name of 1–100 characters.")
    all <- isolate(view_book()); if (length(all) >= 12) stop("Each worksheet supports up to twelve linked views.")
    id <- paste0("V", max(as.integer(sub("V", "", names(all)))) + 1L)
    all[[id]] <- pc_view(settings(), name); views(all); active_view(id); removeModal()
  }, error = notify_error))
  observeEvent(input$rename_view, showModal(modalDialog(title = "Rename linked view", textInput("rename_view_name", "Name", view_book()[[active_view()]]$name), footer = tagList(modalButton("Cancel"), actionButton("confirm_rename_view", "Rename", class = "btn-primary")))))
  observeEvent(input$confirm_rename_view, {
    name <- trimws(input$rename_view_name)
    if (nzchar(name) && nchar(name) <= 100) {all <- isolate(view_book()); all[[active_view()]]$name <- name; views(all); removeModal()}
  })
  deleting_view <- reactiveVal(NULL)
  request_delete_view <- function(id,vid) {
    book <- workbook()
    if (!id %in% names(book) || !vid %in% names(book[[id]]$views)) stop("This view is no longer available.")
    if (length(book[[id]]$views) < 2L) stop("Keep at least one linked view for this data table.")
    deleting_view(list(sheet=id,view=vid,generation=grid_generation()))
    used <- paste(id,vid,sep=":") %in% layout_settings()$selected
    showModal(modalDialog(title="Delete linked view?",p(paste0('Delete “',book[[id]]$views[[vid]]$name,'”? Source observations and other linked views are preserved.')),
      if(used) p("This graph will also be removed from the figure layout."),
      footer=tagList(modalButton("Cancel"),actionButton("confirm_delete_view","Delete view",class="btn-danger"))))
  }
  observeEvent(input$delete_view,tryCatch(request_delete_view(active_sheet(),active_view()),error=notify_error))
  observeEvent(input$delete_named_view,tryCatch(request_delete_view(input$delete_named_view$sheet,input$delete_named_view$view),error=notify_error))
  observeEvent(input$confirm_delete_view,tryCatch({
    target <- deleting_view(); req(target)
    if(!identical(target$generation,grid_generation())) stop("The study changed. Select the view again before deleting it.")
    result <- pc_delete_view(workbook(),target$sheet,target$view,layout_settings())
    sheets(result$book)
    if(target$sheet == active_sheet()) {
      sh <- result$book[[target$sheet]]; views(sh$views); active_view(sh$active_view); update_settings(sh$settings)
    }
    updateCheckboxGroupInput(session,"layout_views",selected=result$layout$selected)
    deleting_view(NULL); removeModal()
  },error=notify_error))
  observeEvent(input$delete_named_table,tryCatch({
    id <- input$delete_named_table$sheet;book <- workbook();if(!is.character(id) || length(id)!=1L || !id %in% names(book)) stop("Select an existing data table.")
    sh <- book[[id]];deleting_table(list(sheet=id,generation=grid_generation(),data=sh$data_tsv))
    used <- sum(startsWith(layout_settings()$selected,paste0(id,":")))
    showModal(modalDialog(title=paste0('Delete data table “',sh$name,'”?'),
      p(paste("This removes its source observations and",length(sh$views),"linked analysis / graph view(s) from this study.")),
      if(used) p(paste(used,"panel(s) using this table will also be removed from the figure layout.")),
      if(length(book)==1) p("A blank data table will replace the last table."),
      p("This deletion cannot be undone in this session. Previously saved project files are unchanged until you save."),
      footer=tagList(modalButton("Cancel"),actionButton("confirm_delete_table","Delete data table",class="btn-danger"))))
  },error=notify_error))
  observeEvent(input$confirm_delete_table,tryCatch({
    target <- deleting_table();req(target)
    book <- workbook();if(!identical(target$generation,grid_generation()) || is.null(book[[target$sheet]]) || !identical(book[[target$sheet]]$data_tsv,target$data)) stop("The table changed. Cancel and select the table’s × again.")
    result <- pc_delete_table(book,target$sheet,active_sheet(),layout_settings());sheets(result$book)
    h <- data_history();h[[target$sheet]] <- NULL;data_history(h)
    gh <- graph_history();gh <- gh[!startsWith(names(gh),paste0(target$sheet,":"))];graph_history(gh)
    if(target$sheet==active_sheet()) {
      id <- result$active;sh <- result$book[[id]];active_sheet(id);sheet_name(sh$name);apply_sheet(pc_read_text(sh$data_tsv,"\t"),sh$settings,sh$views,sh$active_view)
    }
    apply_layout(result$layout);layout_history(list(undo=list(),redo=list()));deleting_table(NULL);removeModal()
    showNotification("Data table and its linked views deleted.",type="message")
  },error=notify_error))
  # Each linked graph has its own formatting history, including inspector changes.
  observeEvent(settings(),{
    key <- paste(active_sheet(),active_view(),sep=":");current <- settings();last <- isolate(graph_last());old <- last[[key]]
    skip <- isolate(graph_skip());if(!is.null(skip) && identical(skip$key,key) && identical(skip$settings,current)) graph_skip(NULL)
    else if(!is.null(old) && old$layout==current$layout && !identical(old[setdiff(names(old),c("method","group1","group2","fit_scope","fit_weight","fit_replicates","correction","null_mean","dpi"))],current[setdiff(names(current),c("method","group1","group2","fit_scope","fit_weight","fit_replicates","correction","null_mean","dpi"))])) {
      h <- isolate(graph_history());entry <- h[[key]];if(is.null(entry)) entry <- list(undo=list(),redo=list())
      entry$undo <- tail(c(entry$undo,list(old)),30);entry$redo <- list();h[[key]] <- entry;graph_history(h)
    }
    last[[key]] <- current;graph_last(last)
  },priority=-100)
  step_graph <- function(direction) {
    key <- paste(active_sheet(),active_view(),sep=":");h <- graph_history();entry <- h[[key]];if(is.null(entry) || !length(entry[[direction]])) return()
    target <- tail(entry[[direction]],1)[[1]]
    # Revalidate against the current observations before applying historical appearance.
    target <- pc_graph_edit(raw(),settings(),target[intersect(names(target),c("graph","title","x_label","y_label","override_x_title","override_y_title","font_size","title_size","axis_title_size","axis_tick_size","text_color","axis_color","axis_line_width","palette","point_size","point_shape","line_width","error","show_points","show_p","legend_position","series_styles","grid_lines","log_x","log_y","x_min","x_max","y_min","y_max","width","height","x_tick_step","y_tick_step","x_tick_angle","ref_x","ref_y","x_axis_length","y_axis_length"))])
    entry[[direction]] <- head(entry[[direction]],-1);other <- if(direction=="undo") "redo" else "undo";entry[[other]] <- tail(c(entry[[other]],list(settings())),30);h[[key]] <- entry
    graph_skip(list(key=key,settings=target));graph_history(h);all <- view_book();all[[active_view()]]$settings <- target;views(all);update_settings(target)
  }
  observeEvent(input$undo_graph,tryCatch(step_graph("undo"),error=notify_error))
  observeEvent(input$redo_graph,tryCatch(step_graph("redo"),error=notify_error))
  observeEvent(list(graph_history(),active_sheet(),active_view()),{
    h <- graph_history()[[paste(active_sheet(),active_view(),sep=":")]]
    session$sendCustomMessage("rdatacraft-graph-history",list(undo=length(h$undo)>0,redo=length(h$redo)>0))
  })
  observeEvent(input$graph_gallery,tryCatch({
    context <- graph_context();gallery_target(context);s <- settings();n <- normalized();a <- analysis_state()$value
    cards <- lapply(unname(pc_graphs(s$layout)),function(graph) {
      preview <- s;preview$graph <- graph;preview$x_axis_length <- 0;preview$y_axis_length <- 0;preview$width <- 75;preview$height <- 58;preview$font_size <- 8;preview$title <- "";preview$x_label <- "";preview$y_label <- "";preview$show_p <- FALSE
      label <- names(pc_graphs(s$layout))[match(graph,pc_graphs(s$layout))]
      svg <- tryCatch(pc_graph_svg(pc_plot(n,preview,a),preview),error=identity)
      tags$button(type="button",class=paste("graph-choice",if(graph==s$graph) "selected"),`data-gallery-graph`=if(!inherits(svg,"error")) graph else NULL,
        disabled=if(inherits(svg,"error")) "disabled" else NULL,
        if(inherits(svg,"error")) div(class="graph-choice-unavailable",conditionMessage(svg)) else tags$img(src=paste0("data:image/svg+xml;base64,",jsonlite::base64_enc(charToRaw(svg))),alt=""),strong(label),if(graph==s$graph) span("Current graph",class="graph-choice-current"))
    })
    showModal(modalDialog(title="Choose a graph",size="l",p("Previews use this table’s observations. Changing the graph preserves its analysis; unsupported combinations explain what to change."),div(class="graph-gallery",cards),footer=modalButton("Cancel")))
  },error=notify_error))
  observeEvent(input$graph_choice,tryCatch({
    if(!identical(gallery_target(),graph_context())) stop("The graph changed. Reopen the gallery.")
    candidate <- pc_graph_edit(raw(),settings(),list(graph=input$graph_choice$graph))
    all <- view_book();all[[active_view()]]$settings <- candidate;views(all);update_settings(candidate);removeModal()
  },error=notify_error))
  graph_context <- reactive(list(sheet=active_sheet(),view=active_view(),token=pc_graph_token(raw(),settings(),active_sheet(),active_view(),grid_generation())))
  observe({session$sendCustomMessage("rdatacraft-graph-context",graph_context())})
  observeEvent(input$graph_edit,tryCatch({
    edit <- input$graph_edit; context <- graph_context()
    if(!identical(edit$sheet,context$sheet) || !identical(edit$view,context$view) || !identical(edit$token,context$token)) stop("The graph changed. Click it again to edit its current settings.")
    next_settings <- pc_graph_edit(raw(),settings(),edit$changes)
    all <- view_book(); all[[active_view()]]$settings <- next_settings; views(all); update_settings(next_settings)
    session$sendCustomMessage("rdatacraft-graph-edit",list(ok=TRUE,message="Graph updated."))
  },error=function(e) {notify_error(e);session$sendCustomMessage("rdatacraft-graph-edit",list(ok=FALSE,message=conditionMessage(e)))}))
  observeEvent(input$copy_vector,tryCatch({
    s <- settings(); state <- analysis_state()
    if (!is.null(state$error) && s$show_p && s$method != "descriptive") stop("Resolve the analysis error or turn off P-value annotations before copying.")
    payload <- pc_vector_payload(pc_plot(normalized(),s,state$value),s)
    session$sendCustomMessage("rdatacraft-vector",payload)
  },error=function(e) {notify_error(e);session$sendCustomMessage("rdatacraft-vector-error",conditionMessage(e))}))
  observeEvent(input$fit_curve,tryCatch({
    if(current_layout()!="xy") stop("Create or select an XY table to fit a curve.")
    if(!settings()$method %in% c("linear","fourpl",unname(pc_regression_methods()))) updateSelectInput(session,"method",selected="linear")
    updateSelectInput(session,"graph",selected="scatter")
    updateTabsetPanel(session,"workspace",selected="analysis");page("analysis");session$sendCustomMessage("rdatacraft-page","analysis")
  },error=notify_error))
  prism_staging <- reactiveVal(NULL)
  stage_prism <- function(path,name) {
    parsed<-pc_prism_import(path,name);parsed$archive<-if(file.info(path)$size<=10e6) pc_prism_archive(path,name) else NULL;prism_staging(parsed)
    showModal(modalDialog(title="Import Prism file",size="l",
      p(parsed$note),
      checkboxInput("prism_keep_original","Keep original Prism file inside this project (analyses, graphs and layouts preserved for Prism)",!is.null(parsed$archive)),
      p(class="muted",if(is.null(parsed$archive)) "This file exceeds the 10 MB attachment limit; its source tables can still be imported." else "The original is kept byte-for-byte and can be saved from Project & sources. Supported JSON conversions are listed below; binary graph/analysis formats require explicit reconstruction."), selectInput("prism_table","Source or converted working table",setNames(seq_along(parsed$tables),vapply(parsed$tables,function(t) paste(t$name,"·",t$layout),character(1)))),
      if(length(parsed$report)) tags$details(open=TRUE,tags$summary("Conversion report"),tags$ul(lapply(parsed$report,tags$li))),
      uiOutput("prism_preview"),
      checkboxInput("prism_override","Reconstruct the previewed table with my analysis and graph choices",FALSE),
      p(class="muted","Only the previewed table uses these overrides. Other tables retain their displayed conversion plans. Edit a converted working table to rerun its analysis; separate source-table copies do not update the reshaped working table."),
conditionalPanel("input.prism_override",uiOutput("prism_rebuild_controls")),checkboxInput("prism_all",paste("Import all",length(parsed$tables),"source / working tables"),length(parsed$tables)>1),
      if(length(parsed$skipped)) tags$details(tags$summary(paste(length(parsed$skipped),"tables cannot be imported")),tags$ul(lapply(parsed$skipped,tags$li))),
      footer=tagList(modalButton("Cancel"),actionButton("confirm_prism_import","Import editable tables & views",class="btn-primary"))))
  }
  observeEvent(input$welcome_prism,tryCatch(stage_prism(input$welcome_prism$datapath,input$welcome_prism$name),error=notify_error))
  observeEvent(input$import_prism,tryCatch(stage_prism(input$import_prism$datapath,input$import_prism$name),error=notify_error))
  observeEvent(input$desktop_import_prism,tryCatch(stage_prism(input$desktop_import_prism$path,basename(input$desktop_import_prism$path)),error=notify_error))
  output$prism_preview <- renderUI({
    parsed<-prism_staging();req(parsed);index<-as.integer(input$prism_table);req(index>=1,index<=length(parsed$tables));t<-parsed$tables[[index]]
    s<-if(is.null(t$settings)) pc_prism_settings(t) else t$settings
    div(class="template-table",p(paste(nrow(t$table),"rows ·",ncol(t$table),"columns ·",t$layout)),
      p(paste("RDataCraft plan:",names(pc_methods(t$layout))[match(s$method,pc_methods(t$layout))],"/",names(pc_graphs(t$layout))[match(s$graph,pc_graphs(t$layout))])),
      if(!is.null(t$conversion)) p(class="inline-note",t$conversion),
      tags$table(tags$thead(tags$tr(lapply(names(t$table),tags$th))),tags$tbody(lapply(seq_len(min(8,nrow(t$table))),function(i) tags$tr(lapply(t$table[i,],function(v) tags$td(if(is.na(v)) "—" else v)))))))
  })
  output$prism_rebuild_controls<-renderUI({
    parsed<-prism_staging();req(parsed,input$prism_table);t<-parsed$tables[[as.integer(input$prism_table)]]
    s<-if(is.null(t$settings)) pc_prism_settings(t) else t$settings;n<-pc_normalize(t$table,t$layout,allow_empty=TRUE)
    tagList(selectInput("prism_method","Analysis to rerun in R",pc_methods(t$layout),s$method),
      selectInput("prism_graph","Editable graph family",pc_graphs(t$layout),s$graph),
      div(class="two-fields",selectInput("prism_group1","First group / series",n$groups,s$group1),selectInput("prism_group2","Second group",n$groups,s$group2)),
      selectInput("prism_error","Error interval",c("None"="none","SD"="sd","SEM"="sem","95% CI"="ci"),s$error),
      textInput("prism_title","Graph title",s$title),
      div(class="two-fields",textInput("prism_x_title","X title",s$x_label),textInput("prism_y_title","Y title",s$y_label)),
      p(class="muted","Choose the test from the experimental design, not from significance. Remaining graph formatting can be edited after import."))
  })
  output$prism_import_history<-renderUI({logs<-import_reports();if(!length(logs)) p(class="muted","No Prism conversion recorded in this study.") else tagList(lapply(rev(logs),function(x) tags$details(tags$summary(strsplit(x,"\n",fixed=TRUE)[[1]][1]),tags$pre(x))))})
  output$export_import_history<-downloadHandler(filename='rdatacraft-prism-import-report.txt',content=function(file) writeLines(unlist(import_reports()),file,useBytes=TRUE),contentType='text/plain')
  observeEvent(input$confirm_prism_import,tryCatch({
    parsed<-prism_staging();req(parsed)
    indices<-if(isTRUE(input$prism_all)) seq_along(parsed$tables) else as.integer(input$prism_table)
    if(!length(indices) || anyNA(indices) || any(!indices %in% seq_along(parsed$tables))) stop("Choose a source table.")
    originals<-prism_sources()
    if(isTRUE(input$prism_keep_original)) {
      if(is.null(parsed$archive)) stop("Uncheck original-file preservation for a file over 10 MB.")
      if(!any(vapply(originals,function(s) identical(s$sha256,parsed$archive$sha256),logical(1)))) originals<-c(originals,list(parsed$archive))
      originals<-pc_prism_archives(originals)
    }
    if((if(document_open()) length(workbook()) else 0L)+length(indices)>100) stop("This import would exceed 100 data tables.")
    # Validate every requested plan before any worksheet is added.
    plans<-lapply(indices,function(i) {
      t<-parsed$tables[[i]];s<-if(is.null(t$settings)) pc_prism_settings(t) else t$settings
      linked<-t$views
      if(isTRUE(input$prism_override) && i==as.integer(input$prism_table)) {
        req(input$prism_method,input$prism_graph)
        s$method<-input$prism_method;s$graph<-input$prism_graph;s$group1<-input$prism_group1;s$group2<-input$prism_group2;s$error<-input$prism_error
        s$title<-input$prism_title;s$x_label<-input$prism_x_title;s$y_label<-input$prism_y_title
        n<-pc_normalize(t$table,t$layout);a<-pc_analyze(n,s$method,s$group1,s$group2,s);ggplot2::ggplot_build(pc_plot(n,s,a))
        if(is.null(linked)) linked<-list(V1=pc_view(s,'Reconstructed in RDataCraft')) else linked$V1<-pc_view(s,'Reconstructed in RDataCraft')
        t$conversion<-paste(t$conversion,'User-selected reconstruction: analysis and graph family explicitly chosen in the import preview.')
      }
      pc_decode_project(pc_project(t$table,s,list(D1=pc_sheet(t$table,s,t$name,linked))))
      list(t=t,s=s,views=linked)
    })
    summary<-vapply(plans,function(p) paste('IMPORTED:',p$t$name,'|',p$s$method,'|',p$s$graph,if(!is.null(p$t$conversion)) paste('|',p$t$conversion) else '| Source observations; descriptive analysis.'),character(1))
    log<-substr(paste(c(paste('Prism import:',parsed$source),format(Sys.time(),tz='UTC',usetz=TRUE),summary,"CONVERSION CANDIDATES (the IMPORTED lines above identify selected tables):",parsed$report,parsed$skipped),collapse='\n'),1,50000)
    for(plan in plans) add_sheet(plan$t$table,plan$s,plan$t$name,plan$views)
    prism_sources(originals);import_reports(tail(c(import_reports(),list(log)),20L))
    prism_staging(NULL);removeModal();showNotification(paste("Imported",length(indices),"editable table(s). Review Analysis and the saved import report."),type="message",duration=10)
  },error=notify_error))
  observeEvent(input$layout, {
    all <- isolate(views()); req(length(all) > 1)
    shared <- all[[1]]$settings$layout
    if (!is.null(shared) && input$layout != shared) {
      updateSelectInput(session, "layout", selected = shared)
      showNotification("Linked views share a table type. Create a new worksheet for another type of experiment.", type = "message")
    }
  }, ignoreInit = TRUE)
  open_sheet <- function(id, vid = NULL, destination = NULL) {
    book <- isolate(workbook())
    if (!is.character(id) || length(id) != 1 || !id %in% names(book)) stop("That data table is not available.")
    sh <- book[[id]]; if (is.null(vid) || !nzchar(vid)) vid <- sh$active_view
    if (!is.character(vid) || length(vid) != 1 || !vid %in% names(sh$views)) stop("That linked view is not available.")
    if (id != isolate(active_sheet())) {
      sheets(book); active_sheet(id); sheet_name(sh$name)
      apply_sheet(pc_read_text(sh$data_tsv, "\t"), sh$views[[vid]]$settings, sh$views, vid)
    } else if (vid != isolate(active_view())) {
      views(isolate(view_book())); active_view(vid); update_settings(sh$views[[vid]]$settings)
    }
    if (!is.null(destination)) {
      if (!destination %in% c("data", "analysis", "figure")) stop("Invalid sheet destination.")
      updateTabsetPanel(session, "workspace", selected = destination); page(destination)
      session$sendCustomMessage("rdatacraft-page", destination)
    }
  }
  observeEvent(input$worksheet, {
    if (identical(input$worksheet, active_sheet())) return()
    tryCatch(open_sheet(input$worksheet), error = notify_error)
  })
  observeEvent(input$navigate_sheet, tryCatch({
    m <- input$navigate_sheet
    if (!m$page %in% c("data", "analysis", "figure")) stop("Invalid sheet destination.")
    open_sheet(m$table, m$view, m$page)
  }, error = notify_error))
  output$project_navigator <- renderUI({req(document_open());pc_project_navigator(workbook(), active_sheet(), active_view(), page(),
    if (is.null(input$navigator_query)) "" else input$navigator_query)})
  outputOptions(output, "project_navigator", suspendWhenHidden = FALSE)
  add_sheet <- function(tab, s, name, linked = NULL, vid = "V1") {
    tab <- pc_check_table(tab)
    book <- if(isolate(document_open())) isolate(workbook()) else list()
    if (length(book) >= 100) stop("A workbook supports up to 100 worksheets.")
    id <- paste0("D", if(length(book)) max(as.integer(sub("D", "", names(book)))) + 1L else 1L)
    document_open(TRUE)
    book[[id]] <- pc_sheet(tab, s, name, linked, vid); sheets(book); active_sheet(id); sheet_name(name)
    apply_sheet(tab, s, linked, vid)
    updateTabsetPanel(session, "workspace", selected = "data"); page("data"); session$sendCustomMessage("rdatacraft-page", "data")
  }
  show_example_guide <- function(selected="independent") {
    guides<-pc_tutorials()
    showModal(modalDialog(title="Examples & analysis guide",size="l",
      p("Choose by scientific question. Adding an example keeps your existing tables and creates a separate teaching table."),
      selectInput("tutorial_choice","What would you like to learn?",setNames(names(guides),vapply(guides,function(g) g$title,character(1))),selected=selected),
      actionButton("r_help_from_examples","Advanced R analysis guide…",class="btn-outline-secondary"),
      uiOutput("tutorial_preview"),footer=tagList(modalButton("Cancel"),actionButton("add_tutorial","Add example & open Analysis",class="btn-primary"))))
  }
  observeEvent(input$show_examples,show_example_guide())
  help_center<-pc_help_server(input,output,session)
  observeEvent(input$help_examples,show_example_guide())
  observeEvent(input$show_pca_guide,show_example_guide("pca"))
  output$tutorial_preview<-renderUI({req(input$tutorial_choice);pc_tutorial_guide(pc_tutorials()[[input$tutorial_choice]])})
  output$example_guide<-renderUI({
    guides<-pc_tutorials();matches<-vapply(guides,function(g) identical(sheet_name(),paste("Example ·",g$title)),logical(1))
    if(any(matches)) div(class="card-surface",tags$details(tags$summary("Example walkthrough"),pc_tutorial_guide(guides[[which(matches)[1]]])))
  })
  observeEvent(input$add_tutorial,tryCatch({
    e<-pc_tutorial(input$tutorial_choice);add_sheet(e$table,e$settings,e$name,e$views)
    if(input$tutorial_choice=="figures") {
      keys<-paste(active_sheet(),names(e$views),sep=":");layout_pending(keys);layout_order(keys);layout_revision(layout_revision()+1L)
      updateCheckboxGroupInput(session,"layout_views",selected=keys)
    }
    removeModal();open_sheet(active_sheet(),destination="analysis")
  },error=notify_error))
  output$prism_originals<-renderUI({
    sources<-prism_sources()
    if(!length(sources)) return(p(class="muted","No Prism originals attached. Select Keep original Prism file when importing."))
    tagList(lapply(seq_along(sources),function(i) div(class="prism-original",strong(sources[[i]]$name),
      p(paste(format(sources[[i]]$bytes,big.mark=","),"bytes · SHA-256",sources[[i]]$sha256)),
      downloadButton(paste0("prism_original_",i),"Save original Prism file…",class="btn-outline-secondary"))))
  })
  for(i in 1:10) local({index<-i;output[[paste0("prism_original_",index)]]<-downloadHandler(
    filename=function() {req(length(prism_sources())>=index);prism_sources()[[index]]$name},
    content=function(file) {req(length(prism_sources())>=index);writeBin(jsonlite::base64_dec(prism_sources()[[index]]$content),file)},contentType="application/octet-stream")})
  observeEvent(input$new_worksheet, showModal(modalDialog(title = "New data table & linked graph", size = "l",
    div(class = "template-dialog", div(class = "template-fields",
      textInput("worksheet_name", "Data table name", "New experiment"),
      selectInput("worksheet_layout", "What kind of data do you have?", pc_layouts()),
      conditionalPanel("input.worksheet_layout === 'xy'", numericInput("worksheet_xy_replicates", "Y replicate subcolumns per series", 1, min = 1, max = 24, step = 1)),
      checkboxInput("worksheet_example", "Fill with example observations", TRUE),
      p(class = "muted", "Start with examples to explore an analysis. Clear this option to enter your own observations.")),
      uiOutput("worksheet_template")),
    footer = tagList(modalButton("Cancel"), actionButton("confirm_worksheet", "Create table & graph", class = "btn-primary")))))
  output$worksheet_template <- renderUI(tryCatch(pc_template_preview(input$worksheet_layout, isTRUE(input$worksheet_example),
    if (is.null(input$worksheet_xy_replicates)) 1L else input$worksheet_xy_replicates), error = function(e) p(class = "inline-note", conditionMessage(e))))
  observeEvent(input$confirm_worksheet, tryCatch({
    layout <- input$worksheet_layout; req(layout %in% unname(pc_layouts()))
    name <- trimws(input$worksheet_name); if (!nzchar(name) || nchar(name) > 100) stop("Enter a worksheet name of 1–100 characters.")
    e <- pc_example(layout); tab <- if (isTRUE(input$worksheet_example)) e$table else pc_blank(layout)
    if (layout == "xy") tab <- pc_xy_replicates(tab, if (is.null(input$worksheet_xy_replicates)) 1L else input$worksheet_xy_replicates)
    s <- pc_defaults(); s$layout <- layout; s$graph <- unname(pc_graphs(layout))[1]; s$method <- if(isTRUE(input$worksheet_example)) e$method else unname(pc_methods(layout))[1]
    s$title <- e$title; s$x_label <- e$x_label; s$y_label <- e$y_label
    if(layout=="multiple") {s$pca_label_column<-"Sample";s$pca_group_column<-"Group";s$show_p<-FALSE}
    if (layout == "xy" && pc_xy_structure(tab)$n > 1L) s$graph <- "xymean"
    nn <- pc_normalize(tab, layout, allow_empty = TRUE); s$group1 <- if(length(nn$groups)) nn$groups[1] else ""; s$group2 <- if(length(nn$groups)) nn$groups[min(2, length(nn$groups))] else ""
    linked<-if(layout=="multiple") pc_pca_views(s) else NULL
    if(!is.null(linked)) s<-linked$V1$settings
    add_sheet(tab, s, name,linked); removeModal()
  }, error = notify_error))
  observeEvent(input$duplicate_worksheet, showModal(modalDialog(title = "Duplicate data table & linked views",
    p("Create an independent copy of the observations and every linked analysis / graph setting. Later data edits affect only the copy."),
    textInput("duplicate_sheet_name", "Name for the copy", paste0(substr(sheet_name(), 1, 94), " copy")),
    footer = tagList(modalButton("Cancel"), actionButton("confirm_duplicate_sheet", "Duplicate table & views", class = "btn-primary")))))
  observeEvent(input$confirm_duplicate_sheet, tryCatch({
    name <- pc_study_name(input$duplicate_sheet_name)
    add_sheet(raw(), settings(), name, view_book(), active_view()); removeModal()
  }, error = notify_error))
  observeEvent(input$copy_graph_style, {
    c <- catalog(); current <- paste(active_sheet(), active_view(), sep = ":")
    showModal(modalDialog(title = "Copy graph formatting", size = "l",
      p("Copy colors, text size, point size, legend placement, grid lines, and individual-point display. Analyses, graph types, error-bar definitions, labels, and axis ranges stay specific to each view."),
      selectInput("format_source", "Copy appearance from", setNames(c$key, c$name), selected = current),
      checkboxGroupInput("format_targets", "Apply to linked graphs", setNames(c$key[c$key != current], c$name[c$key != current])),
      checkboxInput("format_size", "Also copy figure dimensions and export resolution", FALSE),
      if (nrow(c) < 2) p(class = "inline-note", "Add another linked view or data table to create a formatting target."),
      footer = tagList(modalButton("Cancel"), actionButton("confirm_format", "Apply formatting", class = "btn-primary"))))
  })
  observeEvent(input$format_source, {
    c <- catalog(); keep <- c$key != input$format_source
    updateCheckboxGroupInput(session, "format_targets", choices = setNames(c$key[keep], c$name[keep]), selected = intersect(isolate(input$format_targets), c$key[keep]))
  })
  observeEvent(input$confirm_format, tryCatch({
    book <- pc_copy_graph_style(workbook(), input$format_source, input$format_targets, isTRUE(input$format_size))
    sheets(book)
    key <- paste(active_sheet(), active_view(), sep = ":")
    if (key %in% input$format_targets) {
      sh <- book[[active_sheet()]]; views(sh$views); update_settings(sh$views[[active_view()]]$settings)
    }
    removeModal(); showNotification(paste("Formatting applied to", length(input$format_targets), "graph view(s)."), type = "message")
  }, error = notify_error))
  observeEvent(input$rename_worksheet, showModal(modalDialog(title = "Rename worksheet", textInput("rename_sheet", "Name", sheet_name()), footer = tagList(modalButton("Cancel"), actionButton("confirm_rename_sheet", "Rename", class = "btn-primary")))))
  rename_table <- function(id, name) {
    if (!is.character(name) || length(name) != 1L || is.na(name) || !nzchar(trimws(name)) ||
        nchar(trimws(name)) > 100 || grepl("[[:cntrl:]]", name)) stop("Enter a data table name of 1–100 characters, without line breaks.")
    name <- trimws(name)
    if (identical(id, isolate(active_sheet()))) sheet_name(name)
    else {
      book <- isolate(sheets())
      if (!is.character(id) || length(id) != 1L || !id %in% names(book)) stop("This data table is no longer in the study.")
      book[[id]]$name <- name; sheets(book)
    }
    invisible(name)
  }
  observeEvent(input$rename_table, {
    request <- input$rename_table
    tryCatch(rename_table(request$table, request$name), error = notify_error)
    name <- if (identical(request$table, active_sheet())) sheet_name() else sheets()[[request$table]]$name
    if (!is.null(name)) session$sendCustomMessage("rdatacraft-table-name", list(table = request$table, name = name))
  })
  observeEvent(input$confirm_rename_sheet, tryCatch({
    rename_table(active_sheet(), input$rename_sheet); removeModal()
  }, error = notify_error))
  observeEvent(input$apply_transform, tryCatch({
    s <- settings(); tab <- pc_transform(raw(), s$layout, input$transform_kind, input$transform_control)
    s$method <- "descriptive"; s$log_y <- FALSE; s$title <- paste(s$title, input$transform_kind); s$y_label <- paste(input$transform_kind, s$y_label)
    add_sheet(tab, s, paste(substr(sheet_name(), 1, 65), input$transform_kind))
  }, error = notify_error))
  signature_state <- reactive(tryCatch(list(value = signature()), error = function(e) list(value = NULL)))
  document_dirty <- reactive({
    current <- signature_state()$value
    document_open() && (is.null(current) || (!is.null(saved_signature()) && !identical(current, saved_signature())))
  })
  observeEvent(list(signature_state(),document_open()), {
    current <- signature_state()$value
    if (!is.null(current) && is.null(isolate(saved_signature()))) saved_signature(current)
    document_revision(isolate(document_revision()) + 1L)
    session$sendCustomMessage("rdatacraft-document", list(dirty = document_dirty(),
      name = if(document_open()) project_name() else "RDataCraft", path = project_path(), open=document_open(), revision = isolate(document_revision())))
  })
  observeEvent(saved_signature(), {
    session$sendCustomMessage("rdatacraft-document", list(dirty = document_dirty(),
      name = if(document_open()) project_name() else "RDataCraft", path = project_path(), open=document_open(), revision = isolate(document_revision())))
  }, ignoreNULL = TRUE)
  analysis_state <- reactive({
    n <- normalized(); s <- settings()
    tryCatch(list(value = pc_analyze(n, s$method, s$group1, s$group2, s), error = NULL),
             error = function(e) list(value = NULL, error = conditionMessage(e)))
  })
  observe({
    s <- settings()
    session$sendCustomMessage("rdatacraft-figure-size", list(width = s$width / 25.4, height = s$height / 25.4))
  })
  output$figure <- renderImage({
    s <- settings(); file <- tempfile(fileext = ".svg")
    tryCatch({
      writeLines(pc_graph_svg(pc_plot(normalized(), s, analysis_state()$value),s,c(graph_context(),list(table=raw()))),file,useBytes=TRUE)
      list(src = file, contentType = "image/svg+xml", alt = s$title)
    }, error = function(e) {unlink(file); validate(need(FALSE, conditionMessage(e)))})
  }, deleteFile = TRUE)
  output$dataset_info <- renderUI({ n <- normalized(); tagList(strong(paste(n$rows, "rows ·", length(n$groups), "groups")), p(names(pc_layouts())[match(n$layout, pc_layouts())])) })
  output$palette_swatches <- renderUI({ req(input$palette); div(class = "palette-swatches", lapply(head(pc_palettes[[input$palette]], 5), function(color) span(style = paste0("background:", color)))) })
  output$data_note <- renderUI({ n <- normalized(); p(class = "inline-note", pc_layout_help(n$layout)) })
  output$figure_caption <- renderUI({s <- settings();n <- normalized();span(
    if(s$graph=="variables") "Descriptive distributions of numeric candidate variables. Each facet uses its own Y scale; no PCA is computed for this graph."
    else if(n$layout=="multiple") "PCA scores, eigenvector loadings and variance use the selected variables and preprocessing settings. Group colors are descriptive."
    else if(s$graph=="xyband") pc_xy_band_caption(n,s)
    else if(s$graph=="median") "Median with interquartile range (25th–75th percentiles). The selected analysis is unchanged."
    else if(s$graph %in% c("step","area")) "Mean response at each X. Select Scatter or Connected points to inspect the fitted curve."
    else if(s$graph=="density") "Descriptive kernel density estimate; not a normality test."
    else if(s$graph=="groupheat") "Colors and labels show arithmetic mean response for each factor combination."
    else if(n$layout=="survival") "Step curves show Kaplan–Meier estimates; + marks right-censored subjects."
    else if(n$layout=="contingency") "Counts and population proportions; inference uses the original count table."
    else if(n$layout=="xy") "Regression uses the original data scale. Repeated X values are averaged for the mean/error graph."
    else if(s$graph %in% c("box","violin","violinbox","groupbox","groupviolin")) "Distribution and individual observations"
    else paste("Arithmetic mean",switch(s$error,sd="± SD",sem="± SEM",ci="with 95% CI",none="")),
    if(s$show_p && s$log_y) " · P-value brackets hidden on logarithmic axes." else "")})
  output$figure_metrics <- renderUI({
    n <- normalized(); state <- analysis_state()
    metric <- function(value, label) div(class = "metric", strong(value), span(label))
    if(n$layout=="multiple") return(tagList(metric(if(is.null(state$value$pca)) n$rows else nrow(state$value$pca$scores),"observations"),metric(if(is.null(state$value$pca)) length(n$groups) else length(state$value$pca$variables),"variables"),metric(if(is.null(state$value$pca)) "—" else paste0(round(sum(state$value$pca$scree$variance_percent[1:2]),1),"%"),"PC1 + PC2 variance")))
    tagList(metric(nrow(n$data), "observations"), metric(length(n$groups), "groups / series"),
      metric(if (!is.null(state$error)) "Check analysis" else if (is.finite(state$value$p)) pc_p_value(state$value$p) else "—", "selected analysis P value"))
  })
  output$analysis_status <- renderUI({ state <- analysis_state(); if (!is.null(state$error)) div(class = "analysis-error", state$error) else div(class = "analysis-success", state$value$title) })
  output$analysis_banner <- renderUI({
    state <- analysis_state()
    if (!is.null(state$error)) return(div(class="analysis-error",strong("Check your analysis: "),state$error))
    status <- state$value$fit_status
    if (!is.null(status) && any(status$status != "Fitted")) div(class="analysis-error",strong("Some series were not fitted: "),paste(status$series[status$status != "Fitted"],collapse=", "),". Open Analysis for the reason for each series.")
  })
  output$analysis_metrics <- renderTable({ req(analysis_state()$value); analysis_state()$value$metrics }, colnames = FALSE, striped = FALSE, bordered = FALSE, spacing = "m")
  output$analysis_notes <- renderUI({ state <- analysis_state(); if (is.null(state$value)) p("Adjust the selected groups or table to run the analysis.") else tags$ul(lapply(state$value$notes, tags$li)) })
  output$descriptive_table <- renderTable({ state <- analysis_state(); if (!is.null(state$value)) state$value$summary else pc_summary(normalized()) }, digits = 4, na = "—", striped = TRUE)
  observeEvent(input$add_pca_views,tryCatch({
    if(settings()$layout!="multiple") stop("Choose a Multiple variables table first.")
    all<-view_book();if(length(all)>9L) stop("Make room for three more views; each table supports up to twelve.")
    start<-max(as.integer(sub("V","",names(all))))+1L
    added<-pc_pca_views(settings(),start)
    for(v in added) pc_analyze(normalized(),"pca",options=v$settings)
    all<-c(all,added);views(all);active_view(names(added)[1]);update_settings(added[[1]]$settings)
    showNotification("Added linked scores, loadings and explained-variance views.",type="message")
  },error=notify_error))
  pc_pca_controls(input,session,raw,settings)
  output$pca_scree <- renderTable({req(analysis_state()$value$pca);analysis_state()$value$pca$scree},digits=5,striped=TRUE)
  output$pca_preprocessing <- renderTable({req(analysis_state()$value$pca);analysis_state()$value$pca$preprocessing},digits=6,striped=TRUE)
  for(key in c("scores","loadings")) local({k<-key;output[[paste0("pca_",k)]]<-DT::renderDT({req(analysis_state()$value$pca);DT::datatable(analysis_state()$value$pca[[k]],rownames=FALSE,options=list(pageLength=10,scrollX=TRUE))},server=TRUE)})
  for(key in c("scores","loadings","scree","preprocessing")) local({k<-key;output[[paste0("export_pca_",k)]]<-downloadHandler(filename=function() paste0("rdatacraft-pca-",k,".csv"),content=function(file) {req(analysis_state()$value$pca);write.csv(analysis_state()$value$pca[[k]],file,row.names=FALSE,na="")},contentType="text/csv")})
  output$risk_table <- renderTable({ req(analysis_state()$value); analysis_state()$value$at_risk }, digits = 4, na = "—")
  output$effects_table <- renderTable({ req(analysis_state()$value); analysis_state()$value$effects }, digits = 6, na = "—")
  output$fit_status_table <- renderTable({ req(analysis_state()$value); analysis_state()$value$fit_status }, striped = TRUE)
  output$parameters_table <- renderTable({ req(analysis_state()$value); analysis_state()$value$parameters }, digits = 6, na = "—")
  output$comparison_table <- renderTable({ req(analysis_state()$value); analysis_state()$value$comparisons }, digits = 6, na = "—", striped = TRUE)
  output$environment_info <- renderText(paste(R.version.string, paste("ggplot2", packageVersion("ggplot2")), paste("survival", packageVersion("survival")), sep = "\n"))
  save_handler <- function() downloadHandler(filename = function() pc_study_filename(project_name()), content = function(file) {
    pc_write_project(snapshot(), file)
  }, contentType = "application/json")
  output$save_project <- save_handler(); output$save_project_copy <- save_handler()
  outputOptions(output, "save_project", suspendWhenHidden = FALSE)
  outputOptions(output, "save_project_copy", suspendWhenHidden = FALSE)
  restore_project <- function(p, name, path = "") {
    advanced$reset();r_analyses(pc_r_records(p$r_analyses))
    document_open(TRUE);prism_sources(pc_prism_archives(p$prism_sources));import_reports(pc_import_reports(p$import_reports))
    grid_generation(isolate(grid_generation()) + 1L)
    book <- p$worksheets
    id <- if (is.null(p$active)) "D1" else p$active
    if (is.null(book)) book <- list(D1 = pc_sheet(p$table, p$settings, "Observation table"))
    data_history(list()); history_layout(list()); graph_history(list()); graph_last(list()); graph_skip(NULL); layout_history(list(undo=list(),redo=list()))
    sheets(book); active_sheet(id); sheet_name(book[[id]]$name)
    selected <- book[[id]]
    apply_sheet(p$table, p$settings, selected$views, selected$active_view)
    ls <- pc_layout_settings(p$figure_layout); apply_layout(ls); layout_pending(ls$selected); layout_revision(isolate(layout_revision()) + 1L)
    updateTextInput(session, "layout_title", value = ls$title)
    updateSelectInput(session, "layout_columns", selected = ls$columns); updateSelectInput(session, "layout_dpi", selected = ls$dpi)
    updateNumericInput(session, "layout_width", value = ls$width); updateNumericInput(session, "layout_height", value = ls$height)
    name <- if (is.null(p$study_name)) name else p$study_name
    project_name(name); project_path(path)
    saved_signature(pc_signature(p$table, p$settings, book, id, ls, name,prism_sources(),import_reports(),r_analyses()))
    showNotification("Project opened. Data and settings restored.", type = "message", id = "project-opened", duration = 3)
  }
  observeEvent(input$open_project, tryCatch(restore_project(pc_load_project(input$open_project$datapath), pc_project_name(input$open_project$name)), error = notify_error))
  observeEvent(input$desktop_open_project, tryCatch({
    path <- input$desktop_open_project$path
    restore_project(pc_load_project(path), pc_project_name(path), path)
  }, error = notify_error))
  observeEvent(input$desktop_saved, tryCatch({
    path <- input$desktop_saved$path
    p <- pc_load_project(path)
    project_path(path)
    saved_signature(pc_signature(p$table, p$settings, if (is.null(p$worksheets)) list(D1 = pc_sheet(p$table, p$settings, "Observation table")) else p$worksheets, if (is.null(p$active)) "D1" else p$active, pc_layout_settings(p$figure_layout), if (is.null(p$study_name)) project_name() else p$study_name,p$prism_sources,p$import_reports,p$r_analyses))
  }, error = notify_error))
  create_blank_study <- function() {
      s <- pc_defaults(); s$method <- "descriptive"; s$group2 <- "Treatment"; s$title <- "Untitled figure"
      tab <- data.frame(Control = rep(NA_character_, 6), Treatment = rep(NA_character_, 6))
      restore_project(list(table = tab, settings = s), "Untitled study")
      updateTabsetPanel(session, "workspace", selected = "data"); page("data"); session$sendCustomMessage("rdatacraft-page", "data")
  }
  observeEvent(input$desktop_action, {
    if (identical(input$desktop_action$name, "new")) create_blank_study()
  })
  observeEvent(session$clientData$url_search, {
    query<-shiny::parseQueryString(session$clientData$url_search)
    if(identical(query$rdatacraft_new_study,"1")) create_blank_study()
  },once=TRUE)
  output$export_data <- downloadHandler(filename = "rdatacraft-data.csv", content = function(file) write.csv(raw(), file, row.names = FALSE, na = ""), contentType = "text/csv")
  output$export_residuals <- downloadHandler(filename="rdatacraft-fit-residuals.csv",content=function(file) {
    state<-analysis_state();if(is.null(state$value$diagnostics)) stop("Choose a fitted regression model first.")
    write.csv(state$value$diagnostics,file,row.names=FALSE,na="")
  },contentType="text/csv")
  output$export_results <- downloadHandler(filename = "rdatacraft-analysis.json", content = function(file) {
    result <- analysis_state(); if (!is.null(result$error)) stop(result$error)
    payload <- pc_public_result(result$value)
    jsonlite::write_json(list(analysis = payload, project = snapshot()), file,
                         auto_unbox = TRUE, pretty = TRUE, na = "null", digits = 15)
  }, contentType = "application/json")
  output$export_report <- downloadHandler(filename = "rdatacraft-report.html", content = function(file) {
    state <- analysis_state(); if (!is.null(state$error)) stop(state$error)
    s <- settings(); figure <- tempfile(fileext = ".svg"); on.exit(unlink(figure), add = TRUE)
    ggplot2::ggsave(figure, pc_plot(normalized(), s, state$value), device = svglite::svglite, width = s$width, height = s$height, units = "mm", bg = "white")
    svg <- paste(readLines(figure, warn = FALSE), collapse = "\n")
    svg <- sub("(?s)^.*?(<svg)", "\\1", svg, perl = TRUE)
    writeLines(pc_report(state$value, raw(), s, figure_svg = svg), file, useBytes = TRUE)
  }, contentType = "text/html")
  output$export_summary <- downloadHandler(filename = "rdatacraft-summary.csv", content = function(file) {
    state <- analysis_state(); if (!is.null(state$error)) stop(state$error)
    write.csv(state$value$summary, file, row.names = FALSE, na = "")
  }, contentType = "text/csv")
  output$export_comparisons <- downloadHandler(filename = "rdatacraft-comparisons.csv", content = function(file) {
    state <- analysis_state(); if (!is.null(state$error)) stop(state$error)
    write.csv(state$value$comparisons, file, row.names = FALSE, na = "")
  }, contentType = "text/csv")
  for (format in c("svg", "pdf", "png")) local({
    fmt <- format
    output[[paste0("export_layout_", fmt)]] <- downloadHandler(filename = function() paste0("rdatacraft-layout.", fmt), content = function(file) {
      s <- layout_settings(); device <- switch(fmt, svg = svglite::svglite, pdf = pc_pdf_device, png = pc_png_device)
      ggplot2::ggsave(file, layout_grob(), device = device, width = s$width, height = s$height, units = "mm", dpi = s$dpi, bg = "white")
    }, contentType = switch(fmt, svg = "image/svg+xml", pdf = "application/pdf", png = "image/png"))
    outputOptions(output, paste0("export_layout_", fmt), suspendWhenHidden = FALSE)
  })
  for (format in c("svg", "pdf", "png")) local({
    fmt <- format
    output[[paste0("export_", fmt)]] <- downloadHandler(filename = function() paste0("rdatacraft-figure.", fmt),
      content = function(file) {
        s <- settings(); state <- analysis_state()
        if (!is.null(state$error) && s$show_p && s$method != "descriptive") stop("Resolve the analysis error or turn off P-value annotations before exporting.")
        device <- switch(fmt, svg = svglite::svglite, pdf = pc_pdf_device, png = pc_png_device)
        ggplot2::ggsave(file, pc_plot(normalized(), s, state$value), device = device,
                        width = s$width, height = s$height, units = "mm", dpi = s$dpi, bg = "white")
      }, contentType = switch(fmt, svg = "image/svg+xml", pdf = "application/pdf", png = "image/png"))
    outputOptions(output, paste0("export_", fmt), suspendWhenHidden = FALSE)
  })

  advanced <- pc_r_server(input,output,session,
    capture=function() list(open=document_open(),table=raw(),name=sheet_name()),
    records=r_analyses,set_records=function(x) r_analyses(pc_r_records(x)),
    open_page=function() {removeModal();updateTabsetPanel(session,'workspace',selected='advanced');page('advanced');session$sendCustomMessage('rdatacraft-page','advanced')},
    add_result=function(tab,name) {s<-pc_defaults();s$layout<-'multiple';s$method<-'descriptive';s$graph<-'variables';s$show_p<-FALSE;add_sheet(tab,s,substr(name,1,100))})
  assistant <- pc_assistant_server(input,output,session,open_r=function(r) advanced$draft(r),
    capture=function() list(sheet=active_sheet(),view=active_view(),table=raw(),settings=settings(),name=sheet_name()),
    apply_result=function(result) {
      before <- layout_settings()
      add_sheet(result$table,result$settings,result$name,result$views,result$active_view)
      if(!is.null(result$layout)) {
        target<-result$layout;target$selected<-paste0(active_sheet(),":",names(result$views))
        h<-layout_history();h$undo<-tail(c(h$undo,list(before)),30);h$redo<-list();layout_history(h)
        apply_layout(target);layout_pending(target$selected);layout_revision(layout_revision()+1L)
      }
      destination<-if(!is.null(result$layout)) "layout" else "figure"
      updateTabsetPanel(session,"workspace",selected=destination);page(destination);session$sendCustomMessage("rdatacraft-page",destination)
    })

}

shinyApp(ui, server)
