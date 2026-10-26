# Offline, task-oriented help shared by the desktop and local browser interface.
pc_help_topics <- function() list(
  start=list(title='Getting started',keywords='new create study workflow first steps',
    body=shiny::tagList(shiny::p('Start with Create… → Data table, choose the table type, then paste measurements directly into the grid. Each study holds data tables, linked graph views, analyses and a figure layout.'),
      shiny::tags$ol(shiny::tags$li('Name the study by clicking its title. Click a data table name in the navigator to rename it.'),
        shiny::tags$li('Enter observations in Data table. Choose Analyze and select a method appropriate for your experimental design.'),
        shiny::tags$li('Review the results and assumptions. Open Graph to format a figure, then export SVG, PDF or PNG.'),
        shiny::tags$li('Save a .rdatacraft study to keep the data and settings. A figure export does not save the study.')),
      shiny::p('Examples & analysis guide adds original teaching data as a separate table; your existing observations stay in place.'))),
  tables=list(title='Paste data & choose a table type',keywords='clipboard excel csv xlsx replicate grouped column xy multiple survival count',
    body=shiny::tagList(shiny::p('Select the top-left destination cell and paste with Command-V on Mac or Ctrl-V on Windows. The grid expands within its 10,000-row / 50-column limit. Use the paste-with-headers option when the first copied row contains column names; otherwise paste measurements only. Undo reverses the paste. Click a column header to rename it.'),
      shiny::tags$ul(shiny::tags$li('Column: one group per column. For paired data, the same subject occupies the same row across columns.'),
        shiny::tags$li('XY: numeric X first, followed by Y series. Set the number of Y replicates when creating the table; replicate subcolumns belong to their series.'),
        shiny::tags$li('Grouped: two factor-label columns, then replicate measurement columns.'),
        shiny::tags$li('Contingency: category labels first, then nonnegative integer counts; enter observed zeros as 0.'),
        shiny::tags$li('Survival: Time, Status (1 = event, 0 = right-censored), Group.'),
        shiny::tags$li('Multiple variables: one sample per row, one variable per column; useful for PCA and custom R.')),
      shiny::p('Blank measurements represent missing values. Their treatment depends on the analysis. Do not use a blank to represent a measured zero. Import also accepts CSV, TSV and supported Excel workbooks.'))),
  analysis=list(title='Choose an analysis & interpret P values',keywords='statistics t test anova paired independent confidence exact stars significance',
    body=shiny::tagList(shiny::p('Choose the scientific question and experimental unit before selecting a test. Two independent groups can use Welch’s t test; matched subjects require a paired method. Ordinary one-way or two-way ANOVA assumes independent observations. Repeated-measures ANOVA and mixed-effects designs require a suitable Advanced R script.'),
      shiny::p('Inspect sample counts, effect estimates, confidence intervals, warnings and residuals alongside P values. A small P value does not measure effect size or establish the suitability of the model. Follow-up comparisons must account for multiplicity.'),
      shiny::p('Graph formatting offers numeric P labels or significance stars. Numeric labels use four significant digits; values below 0.000001 display as P < 10⁻⁶. Stars use * for P ≤ 0.05, ** for P ≤ 0.01, *** for P ≤ 0.001 and **** for P ≤ 0.0001; ns indicates larger P values. Display choices do not change stored statistics.'),
      shiny::p('Use Examples & analysis guide for a worked example and its assumptions.'))),
  regression=list(title='Regression & curve fitting',keywords='linear nonlinear dose response four parameter logistic weight residual model fit',
    body=shiny::tagList(shiny::p('Use an XY table, then choose a regression method in Analyze. Inspect the model equation and choose how replicates enter the fit. Fitting all observations and fitting means answer different weighting questions; do not treat repeated measurements as independent replicates.'),
      shiny::p('To fit several Y series, set Fit series to All Y series — separate fit per group in Analysis, or use Fit every Y series independently under Figure settings → XY lines & fitted curves. Each group gets its own parameters and curve; these are not shared-parameter or global fits. Mean/error and shaded-band graphs can show the same fitted curves as scatter plots. Choose No connecting lines to hide point-to-point connections while retaining fitted curves. Show fitted curves and Show fitted mean 95% CI control those overlays separately. Error bars summarize observations at each X; a fitted confidence band describes uncertainty in the model mean.'),
      shiny::p('Review convergence, parameter intervals and a residuals view before interpreting a curve. A four-parameter dose-response fit needs positive concentrations and adequate coverage of both plateaus. Poorly identified parameters can be misleading even when a curve looks smooth.'),
      shiny::p('For a formula, model family or dependency outside the presets, use Advanced R analysis and return coefficients, diagnostics and a figure. The app does not automatically establish that a selected model is scientifically appropriate.'))),
  power=list(title='Power & sample-size planning',keywords='power sample size planning n effect paired anova proportions dropout',
    body=shiny::tagList(shiny::p('Use Power analysis in the top toolbar beside Figure layout; Advanced R is next to it. Select a design, then calculate required sample size or power at a chosen N. Use anticipated effects from scientific requirements or independent pilot information, not a post-hoc observed P value.'),
      shiny::p('Two independent means assumes equal group sizes and a common population SD; it does not calculate Welch-test power. Enter Cohen d = mean difference / common SD. Paired designs use dz = mean within-pair difference / SD of within-pair differences; N is complete pairs. ANOVA uses balanced independent groups and Cohen f. Two proportions uses a normal approximation, not an exact test.'),
      shiny::p('Required N is rounded up and achieved power is recalculated at that integer. Dropout inflates recruitment; it does not change analyzable N. For paired designs, the dropout assumption is loss of complete pairs. Check assumptions, independence and multiplicity. Use active table as pilot data to review estimates from a frozen snapshot of the current worksheet and selected analysis. Choose groups/populations and the outcome where offered. Fill planning inputs explicitly, then review and edit the anticipated effect before Calculate. Column t tests/ANOVA and two-category independent counts can prefill compatible designs. XY slopes/residual SD/correlation, grouped cell summaries, survival event fractions and multiple-variable summaries are supplied without substituting a different power test for unsupported models. Manual entry clears the pilot context and remains available. Export the planning CSV to retain final assumptions, pilot context and results; this calculator does not modify observations.'),
      shiny::p('Reference: ',shiny::tags$a(href='https://stat.ethz.ch/R-manual/R-devel/library/stats/html/power.t.test.html',target='_blank',rel='noopener','R stats power calculations')),shiny::actionButton('power_help_open','Open power planning…'))),
  transformations=list(title='Transform observations & replace a whole table',keywords='transform log normalize z score x y columns replace text csv tsv',
    body=shiny::tagList(shiny::p('Data table → Transform observations creates a new worksheet. Column tables can transform all groups or selected columns. XY defaults to all Y observations and replicates, preserving X; choose X only or X and Y explicitly when needed. Grouped tables preserve both factor columns. Multiple-variable tables require you to select measurements; leave numeric IDs and group codes unselected.'),
      shiny::p('Log transforms require positive selected values. Z scores standardize each selected column independently. Percent-of-control uses a selected Column-table control mean. Count and survival tables have structural constraints and are not transformed here. Source observations and unselected cells remain unchanged.'),
      shiny::p('Advanced: replace the entire table from text accepts a header row followed by CSV, tabs or semicolons. Select the delimiter if detection is unsuitable, then choose Replace. Read the inline result or validation error. Invalid text leaves the table unchanged; Undo restores a successful replacement. A graph display log axis does not change observations.'))),
  pca=list(title='Principal component analysis (PCA)',keywords='multivariate score loading scree scaling missing variable',
    body=shiny::tagList(shiny::p('Use Multiple variables: rows are samples and numeric measurement columns are variables. In PCA settings, select measurements explicitly and keep sample IDs and group labels as metadata. Choose centering/scaling and a missing-value policy deliberately.'),
      shiny::p('Review explained variance, scores and loadings together. Group labels color points but do not enter the calculation. PCA is exploratory; apparent group separation is not a significance test.'),
      shiny::p('Open Examples & analysis guide and select Principal component analysis (PCA) for the 12-sample walkthrough, three linked views and scaling/missing-data exercises.'))),
  figures=list(title='Edit graphs, figure size & vector export',keywords='font title axis label points format canvas inch zoom fit clipboard illustrator affinity layout',
    body=shiny::tagList(shiny::p('Click a graph title or axis label to edit its text. Click or double-click an axis or data series to open the corresponding formatting controls; the format toolbar provides the same options. Each linked view keeps its own settings. Delete unwanted views from the navigator after reviewing the confirmation.'),
      shiny::p('New figures start at 3 × 3 inches with 7-point text and 200% screen zoom. Width and height control the exported canvas; zoom and Fit window change only its screen display. Physical screen inches depend on monitor scaling. Existing saved figure dimensions remain in effect.'),
      shiny::p('Export SVG or PDF for editable vector artwork. The desktop apps provide Copy vector in PDF/SVG formats. Clipboard support depends on the receiving application; use SVG or PDF file export when direct paste is unavailable. Fonts must be available in the receiving application.'),
      shiny::p('Figure layout arranges linked graph views into panels. Moving or resizing a panel changes the layout without changing source observations.'))),
  prism=list(title='Import Prism files & review conversion',keywords='prism pzfx pzf multiple input sheet baseline source snapshot warning',
    body=shiny::tagList(shiny::p('Choose Import and select .prism or .pzfx. Review the preview, selected source tables and conversion report before confirming. Supported multi-input analyses create separate editable result tables for each supported input.'),
      shiny::p('Source observations, explicitly converted analyses and saved-result snapshots have different meanings. A saved result is a historical table; editing its source will not recompute a snapshot. Read each import report before using the imported analysis.'),
      shiny::p('Unsupported binary graph formatting, analysis types and legacy .pzf files are not fully converted. Save .pzf as .pzfx or .prism in Prism first. Recreate unsupported graphs from imported observations and verify settings against the original.'),
      shiny::p('Keep original Prism file preserves a byte-for-byte attachment within the study when size limits allow. It does not make all original content editable. Save original Prism file exports the preserved attachment.'))),
  advanced=list(title='Advanced R: scripts, packages & results',keywords='custom code beyond preset package approval install glm r language',
    body=function() pc_r_help()),
  recovery=list(title='Package installation recovery',keywords='stuck lock interrupted crash stop permission network cran missing package',
    body=shiny::tagList(shiny::p('Choose Check / install packages in Advanced R. Review the exact package list and destination, then Approve & install. Package installation and script execution are separate actions.'),
      shiny::p('Stop cancels an app-managed installation and restores incomplete changes. After an app or computer crash, the next approved installation recovers a recorded transaction only when its owning process has ended. A live installer in another window is left alone.'),
      shiny::p('If the app reports an unrecognized lock or an interrupted recovery, close all RDataCraft windows. Back up the personal library and any adjacent .rdatacraft-install-* folders before making changes. Do not delete backup folders during an unfinished promotion. Keep the installation log and request support or inspect the transaction before removing its lock.'),
      shiny::p('Network failures: check your connection, retry Check / install packages and approve the fresh list. No compatible binary: the in-app workflow cannot build source packages or install from GitHub/Bioconductor. Use a suitable separately managed R environment for those methods.'),
      shiny::p('The package library is per user, R version and platform. Installing an add-on does not update the packages used by the main app. Logs are available under Package installation log.'))),
  assistant=list(title='AI Assistant & data privacy',keywords='accounts models ChatGPT OpenAI Claude Gemini API sign in offline prompt code draft network send consent',
    body=shiny::tagList(shiny::p('The assistant’s local tools work without a model. Open AI → Accounts and Models to connect your own ChatGPT account or an OpenAI, Claude, Gemini or compatible API service. Codex is not required. ChatGPT plan access depends on account eligibility and consent. Send shares your message, column names, graph settings and recent conversation. Table values and computed results are included only when Share active table values and computed results is checked. Review your data-sharing requirements before sending.'),
      shiny::p('A model response is a proposal. Review the preview before applying supported changes to a new table copy. Advanced R proposals open as drafts; only Run reviewed script executes code. Missing packages require a separate Approve & install action.'),
      shiny::p('Custom R and downloaded packages run with your account permissions. Process separation handles ordinary errors and Stop/time limits; it is not an operating-system security sandbox. Review code and its scientific assumptions before execution.'),
      shiny::p('Choose a model in Accounts and Models and use Test connection without sharing study data. API services use your own key and may charge separately from website subscriptions. Saved connections are local to RDataCraft and excluded from projects. Disconnect for now retains them; Forget saved API connection removes the saved API key. Sign out selected account removes its ChatGPT session and attempts remote revocation. Offline graph and statistical workflows remain available.'))),
  saving=list(title='Save, reopen & work in several windows',keywords='file study new window download unsaved results draft project',
    body=shiny::tagList(shiny::p('Save a .rdatacraft study to preserve tables, settings, linked views, layouts, imported-file reports and saved Advanced R records. Keep a separate backup before major edits. New study opens a separate desktop window on Mac and Windows, with its own analysis engine. The optional browser interface opens a separate workspace.'),
      shiny::p('The desktop apps use native Open and Save dialogs. Save updates the current study; Save as creates another file. Closing an edited window offers Save, Don’t save or Cancel. In the optional browser interface, Save uses browser downloads; check the filename and location.'),
      shiny::p('Advanced R results retain an input snapshot, code and package versions. Opening a study or loading a saved script never executes it. Use the saved snapshot to reproduce a run, or select the active table to run on current observations.'),
      shiny::p('SVG/PDF/PNG exports contain the figure. CSV exports contain a table. These exports do not replace saving the complete study.'))),
  troubleshooting=list(title='Troubleshooting & platform limits',keywords='engine log launch install mac windows silicon intel blank error report support',
    body=shiny::tagList(shiny::p('Use the installer matching your computer: Intel Mac, Apple Silicon Mac or Windows x64. R and the required packages are bundled. Mac and Windows editions open in dedicated desktop windows. The Windows installer includes the Microsoft WebView2 component used to display the interface; it does not open an external browser.'),
      shiny::p('If startup fails, Help → Show engine log opens the current window’s log. Each desktop window starts and stops its own local R engine. Close and reopen an affected window after saving available work.'),
      shiny::p('Before reporting a problem, note the app version, operating system, action taken and full error. Prefer a small synthetic example. Review logs and studies for private observations or personal paths before sharing them publicly.'),
      shiny::p('Development builds are not Apple-notarized or Windows code-signed. Platform validation and release status are documented with the download.'))))

pc_help_matches <- function(query='',topics=pc_help_topics()) {
  if(is.null(query)) query<-''
  words<-strsplit(tolower(trimws(query)),'[[:space:]]+')[[1]]
  names(topics)[vapply(topics,function(t) all(vapply(words,function(w) grepl(w,tolower(paste(t$title,t$keywords)),fixed=TRUE),logical(1))),logical(1))]
}
pc_help_body <- function(id) {
  topic<-pc_help_topics()[[id]]
  if(is.null(topic)) return(shiny::p('Choose a help topic.'))
  shiny::tagList(shiny::h3(topic$title),if(is.function(topic$body)) topic$body() else topic$body)
}
pc_help_server <- function(input,output,session) {
  topics<-pc_help_topics()
  open<-function() shiny::showModal(shiny::modalDialog(title='RDataCraft help',size='l',fade=FALSE,easyClose=TRUE,
    shiny::div(class='help-center',
      shiny::p('Find instructions by task. Help works offline; examples add separate teaching tables.'),
      shiny::div(class='help-actions',shiny::actionButton('help_examples','Examples & analysis guide…'),shiny::actionButton('r_help_from_examples','Advanced R guide…')),
      shiny::textInput('help_search','Search help topics',placeholder='Try paste, PCA, vector, packages or save'),
      shiny::selectInput('help_topic','Help topic',setNames(names(topics),vapply(topics,function(t)t$title,character(1))),selected='start'),
      shiny::uiOutput('help_content')),footer=shiny::modalButton('Close help')))
  shiny::observeEvent(input$show_help,open())
  shiny::observeEvent(input$help_search,{
    ids<-pc_help_matches(input$help_search,topics);old<-shiny::isolate(input$help_topic)
    shiny::updateSelectInput(session,'help_topic',choices=setNames(ids,vapply(topics[ids],function(t)t$title,character(1))),selected=if(length(old) && old %in% ids) old else if(length(ids)) ids[1] else character())
  },ignoreNULL=FALSE)
  output$help_content<-shiny::renderUI({
    ids<-pc_help_matches(if(is.null(input$help_search)) '' else input$help_search,topics)
    if(!length(ids)) return(shiny::p(role='status','No matching topics. Try fewer words or clear the search.'))
    id<-input$help_topic;if(is.null(id) || !id %in% ids) id<-ids[1]
    pc_help_body(id)
  })
  list(open=open)
}
