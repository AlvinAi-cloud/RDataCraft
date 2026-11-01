# Graph interaction uses the same validated settings and vector device as export.
pc_comparison_p_available <- function(analysis) {
  any(vapply(list(analysis$comparisons,analysis$xy_comparisons),function(comparisons)
    is.data.frame(comparisons) && nrow(comparisons)>0L && "p" %in% names(comparisons) &&
      is.numeric(comparisons$p) && any(is.finite(comparisons$p) & comparisons$p>=0 & comparisons$p<=1),logical(1)))
}
pc_graph_token <- function(tab, settings, sheet, view, generation) digest::digest(jsonlite::toJSON(list(tab,settings,sheet,view,generation),auto_unbox=TRUE,digits=15,na="null"),serialize=FALSE,algo="xxhash64")
pc_graph_edit <- function(tab, settings, changes) {
  allowed <- c("title","x_label","y_label","override_x_title","override_y_title","font_size","title_size","axis_title_size","axis_tick_size",
    "text_color","axis_color","axis_line_width","palette","point_size","point_shape","line_width","xy_connections","xy_show_fit","xy_fit_band","xy_compare","xy_compare_group1","xy_compare_group2","xy_compare_correction","xy_compare_significant_only","error","show_points","show_p","annotation",
    "legend_position","series_styles","grid_lines","log_x","log_y","x_min","x_max","y_min","y_max","width","height","graph","x_tick_step","y_tick_step","x_tick_angle","ref_x","ref_y","x_axis_length","y_axis_length","pca_scale","pca_missing","pca_variables","pca_label_column","pca_group_column","pca_x","pca_y","pca_labels")
  if (!is.list(changes) || !length(changes) || is.null(names(changes)) || anyDuplicated(names(changes)) || any(!names(changes) %in% allowed))
    stop("Choose a supported graph formatting option.", call. = FALSE)
  settings[names(changes)] <- changes
  result <- pc_decode_project(list(format="rdatacraft",schema_version=1L,data_tsv=pc_table_text(tab),settings=settings))$settings
  if (result$point_shape != floor(result$point_shape)) stop("Choose a whole-number symbol shape.",call.=FALSE)
  n <- pc_normalize(tab,result$layout,allow_empty=TRUE)
  if (nrow(n$data)) ggplot2::ggplotGrob(pc_plot(n,result,tryCatch(pc_analyze(n,result$method,result$group1,result$group2,result),error=function(e) NULL)))
  result
}
pc_graph_svg <- function(plot, settings, context = NULL) {
  file <- tempfile(fileext=".svg"); on.exit(unlink(file))
  ggplot2::ggsave(file,plot,device=svglite::svglite,width=settings$width,height=settings$height,units="mm",bg="white")
  svg <- paste(readLines(file,warn=FALSE),collapse="\n")
  if (!is.null(context)) {
    context$labels <- list(title=plot$labels$title,x_label=plot$labels$x,y_label=plot$labels$y)
    context$settings <- settings
    context$comparison_p_available <- isTRUE(context$comparison_p_available)
    context$palettes <- pc_palettes
    context$palette_choices <- as.list(setNames(names(pc_palette_choices()),unname(pc_palette_choices())))
    if (!is.null(context$table)) context$series <- pc_normalize(context$table, settings$layout, allow_empty = TRUE)$groups
    if (identical(settings$layout,"multiple")) context$series <- character()
    if (!is.null(context$table)) context$colors <- as.list(pc_series_colors(pc_normalize(context$table,settings$layout,allow_empty=TRUE),settings))
    context$table <- NULL
    metadata <- paste0("<metadata id='rdatacraft-interaction'>",htmltools::htmlEscape(jsonlite::toJSON(context,auto_unbox=TRUE,null="null")),"</metadata>")
    match <- regexpr("<svg[^>]*>",svg); end <- as.integer(match)+attr(match,"match.length")-1L
    svg <- paste0(substr(svg,1,end),"\n",metadata,substr(svg,end+1,nchar(svg)))
  }
  svg
}
pc_vector_payload <- function(plot, settings) {
  file <- tempfile(fileext=".pdf");on.exit(unlink(file))
  ggplot2::ggsave(file,plot,device=pc_pdf_device,width=settings$width,height=settings$height,units="mm",bg="white")
  list(svg=pc_graph_svg(plot,settings),pdf=jsonlite::base64_enc(readBin(file,"raw",n=file.info(file)$size)))
}
