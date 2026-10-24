source("R/views.R", local = TRUE)
source("R/advanced_r.R", local = TRUE)
source("R/prism_archive.R",local=TRUE)

pc_project <- function(tab, settings, worksheets = NULL, active = "D1", figure_layout = NULL, study_name = NULL, prism_sources = NULL, import_reports = NULL, r_analyses = NULL) {
  uses_replicates <- identical(settings$layout, "xy") && pc_xy_structure(tab)$n > 1L
  if (!is.null(worksheets)) uses_replicates <- uses_replicates || any(vapply(worksheets, function(sh)
    identical(sh$settings$layout, "xy") && pc_xy_structure(pc_read_text(sh$data_tsv, "\t"))$n > 1L, logical(1)))
  if (uses_replicates && is.null(worksheets)) {worksheets <- list(D1 = pc_sheet(tab, settings, "Observation table")); active <- "D1"}
  p <- list(format = "rdatacraft", schema_version = if (is.null(worksheets)) 1L else 3L, app_version = "0.3",
       saved_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
       data_tsv = pc_table_text(tab), settings = settings,
       environment = list(r_version = as.character(getRversion()),
         packages = setNames(lapply(c("shiny", "ggplot2", "survival"), function(x) as.character(utils::packageVersion(x))),
                             c("shiny", "ggplot2", "survival"))))
  if (!is.null(study_name)) p$study_name <- pc_study_name(study_name)
  if (uses_replicates) p$schema_version <- 4L
  if (!is.null(worksheets)) {p$worksheets <- worksheets; p$active <- active}
  modern <- function(s) !identical(s$series_styles, "{}") || identical(s$fit_scope, "all")
  if (modern(settings) || (!is.null(worksheets) && any(vapply(worksheets, function(sh) any(vapply(sh$views, function(v) modern(v$settings), logical(1))), logical(1))))) p$schema_version <- 5L
  if (!is.null(figure_layout)) p$figure_layout <- pc_layout_settings(figure_layout)
  advanced <- function(s) s$graph %in% c("mean","median","violinbox","density","step","area","groupbox","groupviolin","groupheat","stacked") ||
    any(vapply(c("x_tick_step","y_tick_step","ref_x","ref_y"),function(k) !is.null(s[[k]]) && nzchar(s[[k]]),logical(1))) || (!is.null(s$x_tick_angle) && s$x_tick_angle != 0)
  if (advanced(settings) || (!is.null(worksheets) && any(vapply(worksheets,function(sh) any(vapply(sh$views,function(v) advanced(v$settings),logical(1))),logical(1)))) ||
      (!is.null(p$figure_layout) && !isTRUE(all.equal(p$figure_layout,pc_layout_settings(p$figure_layout[c("selected","columns","title","width","height","dpi")]),check.attributes=FALSE)))) p$schema_version <- 6L
  sized <- function(s) identical(s$graph,"xyband") || isTRUE(s$x_axis_length > 0) || isTRUE(s$y_axis_length > 0)
  if (sized(settings) || (!is.null(worksheets) && any(vapply(worksheets,function(sh) any(vapply(sh$views,function(v) sized(v$settings),logical(1))),logical(1))))) p$schema_version <- 7L
  pca_used <- function(s) identical(s$layout,"multiple") || any(vapply(grep("^pca_",names(pc_defaults()),value=TRUE),function(k) !is.null(s[[k]]) && !isTRUE(all.equal(s[[k]],pc_defaults()[[k]])),logical(1)))
  if(pca_used(settings) || (!is.null(worksheets) && any(vapply(worksheets,function(sh) any(vapply(sh$views,function(v) pca_used(v$settings),logical(1))),logical(1))))) p$schema_version <- 8L
  if(p$schema_version>=5L && is.null(p$worksheets)) {p$worksheets <- list(D1=pc_sheet(tab,settings,"Observation table"));p$active <- "D1"}
  if(length(prism_sources)) {
    p$prism_sources<-pc_prism_archives(prism_sources);p$schema_version<-9L
    if(is.null(p$worksheets)) {p$worksheets<-list(D1=pc_sheet(tab,settings,"Observation table"));p$active<-"D1"}
  }
  variable_graph<-function(s) identical(s$graph,'variables')
  if(length(import_reports) || variable_graph(settings) || (!is.null(worksheets) && any(vapply(worksheets,function(sh) any(vapply(sh$views,function(v) variable_graph(v$settings),logical(1))),logical(1))))) {
    p$schema_version<-10L;p$import_reports<-pc_import_reports(import_reports)
    if(is.null(p$worksheets)) {p$worksheets<-list(D1=pc_sheet(tab,settings,'Observation table'));p$active<-'D1'}
  }
  if(length(r_analyses)) {
    p$r_analyses<-pc_r_records(r_analyses);p$schema_version<-11L
    if(is.null(p$worksheets)) {p$worksheets<-list(D1=pc_sheet(tab,settings,'Observation table'));p$active<-'D1'}
  }
  p
}
pc_import_reports <- function(reports=NULL) {
  if(is.null(reports) || !length(reports)) return(list())
  if(length(reports)>20 || !all(vapply(reports,function(x) is.character(x) && length(x)==1L && !is.na(x) && nchar(x)<=50000,logical(1)))) stop('Invalid or oversized import history.')
  unname(as.list(reports))
}

pc_load_project <- function(path) {
  if (file.info(path)$size > 30e6) stop("Project files must be smaller than 30 MB.", call. = FALSE)
  p <- jsonlite::read_json(path, simplifyVector = FALSE)
  pc_decode_project(p)
}

pc_decode_project <- function(p) {
  if (!p$format %in% c("rdatacraft", "plotcraft") || !p$schema_version %in% c(1L, 2L, 3L, 4L, 5L, 6L, 7L, 8L, 9L, 10L, 11L)) stop("This is not a supported RDataCraft project.", call. = FALSE)
  tab <- pc_read_text(p$data_tsv, "\t")
  defaults <- pc_defaults()
  settings <- defaults
  if (!is.list(p$settings)) stop("Project settings are missing.", call. = FALSE)
  choices <- list(layout = unname(pc_layouts()), method = unique(unlist(lapply(unname(pc_layouts()), function(x) unname(pc_methods(x))))),
                  graph = unique(unlist(lapply(unname(pc_layouts()), function(x) unname(pc_graphs(x))))),
                  correction = c("holm", "bonferroni", "BH"), annotation = c("p", "stars"),
                  error = c("none", "sd", "sem", "ci"), palette = names(pc_palettes), legend_position = c("auto", "top", "bottom", "left", "right", "none"), pca_missing=c("error","complete"),
                  fit_scope=c("selected","all"),fit_weight=c("none","inv_y2","replicate_sd"),fit_replicates=c("individual","mean"))
  bounds <- list(null_mean = c(-1e12, 1e12), font_size = c(4, 24), point_size = c(1, 6), width = c(25.4, 400), height = c(25.4, 300), dpi = c(72, 600),
    title_size = c(0,48), axis_title_size = c(0,48), axis_tick_size = c(0,48), axis_line_width = c(0.1,3), point_shape = c(0,25), line_width = c(0,4), x_tick_angle = c(0,90), x_axis_length = c(0,350), y_axis_length = c(0,250), pca_x=c(1,50), pca_y=c(1,50))
  for (name in names(defaults)) {
    v <- p$settings[[name]]
    if (is.null(v)) next
    if (name == "pca_variables") {if(!is.character(v) || length(v)!=1L || is.na(v) || nchar(v)>6000) stop("Invalid PCA variable selection.");settings[[name]]<-v;next}
    if (name == "series_styles") {pc_series_styles(v); settings[[name]] <- v; next}
    if (length(v) != 1L || is.list(v) || is.na(v)) stop("Invalid project setting: ", name, call. = FALSE)
    if (name %in% c("text_color", "axis_color") && (!is.character(v) || !grepl("^#[0-9a-fA-F]{6}$", v))) stop("Choose a valid color for ", name, call. = FALSE)
    if (name %in% names(choices)) {
      if (!is.character(v) || !v %in% choices[[name]]) stop("Invalid project setting: ", name, call. = FALSE)
    } else if (name %in% names(bounds)) {
      if (!is.numeric(v) || !is.finite(v) || v < bounds[[name]][1] || v > bounds[[name]][2]) stop("Invalid project setting: ", name, call. = FALSE)
    } else if (is.logical(defaults[[name]])) {
      if (!is.logical(v)) stop("Invalid project setting: ", name, call. = FALSE)
    } else if (!is.character(v) || nchar(v) > 300) stop("Invalid project setting: ", name, call. = FALSE)
    settings[[name]] <- v
  }
  if (!settings$method %in% unname(pc_methods(settings$layout))) stop("The saved analysis does not match the table layout.", call. = FALSE)
  valid_graphs <- unname(pc_graphs(settings$layout))
  if (!settings$graph %in% valid_graphs) stop("The saved graph does not match the table layout.", call. = FALSE)
  pc_validate_graph_details(settings)
  pc_validate_axes(settings)
  pc_validate_pca_settings(settings)
  pc_normalize(tab, settings$layout, allow_empty = TRUE, allow_incomplete = TRUE)
  if (!is.null(p$study_name)) p$study_name <- pc_study_name(p$study_name)
  out <- list(r_analyses=pc_r_records(p$r_analyses),import_reports=pc_import_reports(p$import_reports),prism_sources=pc_prism_archives(p$prism_sources),study_name = p$study_name, table = tab, settings = settings, environment = p$environment, figure_layout = pc_layout_settings(p$figure_layout))
  if (p$schema_version %in% c(2L, 3L, 4L, 5L, 6L, 7L, 8L, 9L, 10L, 11L)) {
    book <- p$worksheets
    if (!is.list(book) || !length(book) || length(book) > 100 || is.null(names(book)) || anyDuplicated(names(book)) || any(!grepl("^D[0-9]+$", names(book)))) stop("Invalid workbook worksheets.", call. = FALSE)
    for (id in names(book)) {
      sheet <- book[[id]]
      if (!is.character(sheet$name) || length(sheet$name) != 1 || !nzchar(sheet$name) || nchar(sheet$name) > 100) stop("Invalid worksheet name.", call. = FALSE)
      v <- pc_decode_project(list(format = "rdatacraft", schema_version = 1L, data_tsv = sheet$data_tsv, settings = sheet$settings))
      views <- sheet$views; vid <- sheet$active_view
      if (is.null(views)) {views <- list(V1 = pc_view(v$settings)); vid <- "V1"}
      if (!is.character(vid) || length(vid) != 1) stop("Invalid active graph view.", call. = FALSE)
      pc_views(v$settings, views, vid)
      for (key in names(views)) {
        view <- views[[key]]
        if (!is.character(view$name) || length(view$name) != 1 || is.na(view$name) || !nzchar(view$name) || nchar(view$name) > 100) stop("Invalid linked view name.", call. = FALSE)
        decoded <- pc_decode_project(list(format = "rdatacraft", schema_version = 1L, data_tsv = sheet$data_tsv, settings = view$settings))
        if (decoded$settings$layout != v$settings$layout) stop("Linked views must use the source worksheet's table type.", call. = FALSE)
        views[[key]] <- pc_view(decoded$settings, view$name)
      }
      if (!isTRUE(all.equal(views[[vid]]$settings, v$settings))) stop("Active linked view does not match worksheet settings.", call. = FALSE)
      book[[id]] <- pc_sheet(v$table, v$settings, sheet$name, views, vid)
    }
    if (!is.character(p$active) || length(p$active) != 1 || !p$active %in% names(book)) stop("Invalid active worksheet.", call. = FALSE)
    selected <- book[[p$active]]
    if (!identical(selected$data_tsv, pc_table_text(tab)) || !isTRUE(all.equal(selected$settings, settings))) stop("Active worksheet does not match project data.", call. = FALSE)
    if (any(!out$figure_layout$selected %in% pc_view_catalog(book)$key)) stop("The saved layout references a missing linked view.", call. = FALSE)
    out$worksheets <- book; out$active <- p$active
  }
  out
}

pc_sheet <- function(tab, settings, name, views = NULL, active_view = "V1") list(name = name, data_tsv = pc_table_text(tab), settings = settings, views = pc_views(settings, views, active_view), active_view = active_view)

pc_signature <- function(tab, settings, worksheets = NULL, active = "D1", figure_layout = NULL, study_name = NULL, prism_sources = NULL, import_reports = NULL, r_analyses = NULL) {
  payload <- list(data_tsv = pc_table_text(tab), settings = settings)
  if(length(r_analyses)) payload$r_analyses<-pc_r_records(r_analyses)
  if(length(import_reports)) payload$import_reports<-pc_import_reports(import_reports)
  if(length(prism_sources)) payload$prism_sources<-lapply(prism_sources,function(s) s[c("name","sha256","bytes")])
  if (!is.null(study_name)) payload$study_name <- pc_study_name(study_name)
  if (!is.null(worksheets)) {payload$worksheets <- worksheets; payload$active <- active}
  if (!is.null(figure_layout)) payload$figure_layout <- pc_layout_settings(figure_layout)
  jsonlite::toJSON(payload, auto_unbox = TRUE, digits = 15, na = "null")
}

pc_project_name <- function(path) sub("\\.(rdatacraft|plotcraft)(\\.json)?$|\\.json$", "", basename(path), ignore.case = TRUE)


pc_write_project <- function(project, file) {
  payload <- jsonlite::toJSON(project, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 15)
  if (nchar(payload, type = "bytes") > 30e6) stop("This workbook exceeds the 30 MB project limit. Save its worksheets as separate projects.", call. = FALSE)
  writeLines(payload, file, useBytes = TRUE)
}

# Study titles are document metadata, independent of the file's name.
pc_study_name <- function(name) {
  if (!is.character(name) || length(name) != 1L || is.na(name) ||
      !nzchar(trimws(name)) || nchar(trimws(name)) > 100 || grepl("[[:cntrl:]]", name))
    stop("Enter a study name of 1–100 characters, without line breaks.", call. = FALSE)
  trimws(name)
}
pc_study_filename <- function(name) paste0(gsub('[/:*?"<>|\\\\]', "-", pc_study_name(name)), ".rdatacraft")
