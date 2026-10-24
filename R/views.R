# Original linked-view and layout helpers. GPL-3.0.
pc_view <- function(settings, name = "Primary view") list(name = name, settings = settings)
pc_delete_view <- function(book, sheet, view, layout) {
  if (!is.character(sheet) || length(sheet) != 1 || !sheet %in% names(book) ||
      !is.character(view) || length(view) != 1 || !view %in% names(book[[sheet]]$views)) stop("This linked view is no longer available.", call. = FALSE)
  sh <- book[[sheet]]
  if (length(sh$views) == 1L) stop("Keep at least one linked view for each data table.", call. = FALSE)
  sh$views[[view]] <- NULL
  if (sh$active_view == view) sh$active_view <- names(sh$views)[1]
  sh$settings <- sh$views[[sh$active_view]]$settings; book[[sheet]] <- sh
  layout$selected <- setdiff(layout$selected, paste(sheet, view, sep = ":"))
  list(book = book, layout = layout)
}
pc_views <- function(settings, views = NULL, active = "V1") {
  if (is.null(views)) views <- list(V1 = pc_view(settings))
  if (!is.list(views) || !length(views) || length(views) > 12 || is.null(names(views)) || anyDuplicated(names(views)) || any(!grepl("^V[0-9]+$", names(views))) || !active %in% names(views)) stop("Invalid linked views.", call. = FALSE)
  views[[active]]$settings <- settings
  views
}
source("R/layout_editor.R",local=TRUE)
pc_layout_defaults <- function() c(list(selected = character(), columns = 2, title = "Figure layout", width = 180, height = 220, dpi = 300),pc_layout_design_defaults())
pc_layout_settings <- function(value = NULL) {
  s <- pc_layout_defaults()
  if (is.null(value)) return(s)
  if (!is.list(value)) stop("Invalid figure layout settings.", call. = FALSE)
  for (key in names(s)) if (!is.null(value[[key]])) s[[key]] <- value[[key]]
  s$selected <- as.character(unlist(s$selected, use.names = FALSE))
  if (length(s$selected) > 8 || anyDuplicated(s$selected) || any(!grepl("^D[0-9]+:V[0-9]+$", s$selected))) stop("Choose up to eight distinct linked graph views.", call. = FALSE)
  for (key in c("columns", "width", "height", "dpi")) if (!is.numeric(s[[key]]) || length(s[[key]]) != 1 || !is.finite(s[[key]])) stop("Invalid layout size or resolution.", call. = FALSE)
  if (!s$columns %in% 1:3 || s$width < 60 || s$width > 400 || s$height < 50 || s$height > 400 || s$dpi < 72 || s$dpi > 600) stop("Layout limits: 1–3 columns, 60–400 mm wide, 50–400 mm high, 72–600 dpi.", call. = FALSE)
  if (!is.character(s$title) || length(s$title) != 1 || is.na(s$title) || nchar(s$title) > 300) stop("Invalid layout title.", call. = FALSE)
  if(!is.character(s$arrangement) || length(s$arrangement)!=1L || !s$arrangement %in% c("grid","hero","manual")) stop("Choose a valid panel arrangement.",call.=FALSE)
  for(k in c("gap","margin","label_size")) if(!is.numeric(s[[k]]) || length(s[[k]])!=1L || !is.finite(s[[k]])) stop("Invalid layout spacing.",call.=FALSE)
  if(s$gap<0 || s$gap>20 || s$margin<0 || s$margin>30 || s$label_size<8 || s$label_size>32 || !is.logical(s$scale_text) || length(s$scale_text)!=1L || is.na(s$scale_text)) stop("Choose valid layout spacing and label sizes.",call.=FALSE)
  positions <- pc_layout_map(s$positions); labels <- pc_layout_map(s$labels,"labels")
  positions <- positions[intersect(names(positions),s$selected)];labels <- labels[intersect(names(labels),s$selected)]
  s$positions <- if(length(positions)) jsonlite::toJSON(positions,auto_unbox=TRUE,digits=10) else "{}"
  s$labels <- if(length(labels)) jsonlite::toJSON(labels,auto_unbox=TRUE) else "{}"
  s
}
pc_view_catalog <- function(book) {
  rows <- lapply(names(book), function(id) {
    sh <- book[[id]]; views <- pc_views(sh$settings, sh$views, if(is.null(sh$active_view)) "V1" else sh$active_view)
    do.call(rbind, lapply(names(views), function(vid) data.frame(key = paste(id, vid, sep = ":"), worksheet = id, view = vid,
      name = paste(sh$name, views[[vid]]$name, sep = " / "), method = names(pc_methods(views[[vid]]$settings$layout))[match(views[[vid]]$settings$method, pc_methods(views[[vid]]$settings$layout))], graph = names(pc_graphs(views[[vid]]$settings$layout))[match(views[[vid]]$settings$graph, pc_graphs(views[[vid]]$settings$layout))])))
  })
  do.call(rbind, rows)
}
pc_layout_plots <- function(book, selected) {
  if (!length(selected)) stop("Select linked graph views for the layout.", call. = FALSE)
  if (length(selected) > 8) stop("A layout supports up to eight panels.", call. = FALSE)
  lapply(selected, function(key) {
    ids <- strsplit(key, ":", fixed = TRUE)[[1]]
    if (length(ids) != 2 || is.null(book[[ids[1]]])) stop("A selected layout worksheet is missing.", call. = FALSE)
    sh <- book[[ids[1]]]; v <- sh$views[[ids[2]]]
    if (is.null(v)) stop("A selected linked view is missing.", call. = FALSE)
    s <- v$settings
    tryCatch({
      n <- pc_normalize(pc_read_text(sh$data_tsv, "\t"), s$layout)
      a <- pc_analyze(n, s$method, s$group1, s$group2, s)
      pc_plot(n, s, a)
    }, error = function(e) stop(paste(sh$name, v$name, conditionMessage(e), sep = " · "), call. = FALSE))
  })
}
pc_layout_grob <- function(plots, columns = 2, title = "Figure layout") {
  if (!length(plots) || length(plots) > 8 || !columns %in% 1:3) stop("Choose 1–8 panels and 1–3 columns.", call. = FALSE)
  rows <- ceiling(length(plots) / columns)
  result <- gtable::gtable(widths = grid::unit(rep(1, columns), "null"),
    heights = grid::unit(c(10, rep(1, rows)), c("mm", rep("null", rows))))
  result <- gtable::gtable_add_grob(result, grid::textGrob(title, x = grid::unit(3, "mm"), just = "left", gp = grid::gpar(fontsize = 14, fontface = "bold")), t = 1, l = 1, r = columns, name = "layout-title")
  for (i in seq_along(plots)) {
    row <- 2 + (i - 1) %/% columns; col <- 1 + (i - 1) %% columns
    font <- plots[[i]]$theme$axis.text$size
    if (is.null(font) || !is.numeric(font)) font <- 13
    font <- max(7, font / sqrt(columns))
    p <- plots[[i]] + ggplot2::theme(panel.widths=NULL,panel.heights=NULL) + ggplot2::labs(tag = LETTERS[i]) + ggplot2::theme(
      axis.text = ggplot2::element_text(size = font), axis.title = ggplot2::element_text(size = font, face = "bold"),
      legend.text = ggplot2::element_text(size = font), plot.title = ggplot2::element_text(size = font + 1, face = "bold"),
      plot.subtitle = ggplot2::element_text(size = font), plot.tag = ggplot2::element_text(size = font + 1, face = "bold"),
      plot.margin = ggplot2::margin(12, 10, 10, 12))
    result <- gtable::gtable_add_grob(result, ggplot2::ggplotGrob(p), t = row, l = col, name = paste0("panel-", i))
  }
  result
}

pc_delete_table <- function(book,sheet,active,layout) {
  if(!is.character(sheet) || length(sheet)!=1L || !sheet %in% names(book)) stop("This data table is no longer available.",call.=FALSE)
  book[[sheet]] <- NULL
  layout$selected <- layout$selected[!startsWith(layout$selected,paste0(sheet,":"))]
  layout <- pc_layout_settings(layout)
  if(!length(book)) {
    s <- pc_defaults();s$title <- "Untitled figure";s$method <- "descriptive";s$show_p <- FALSE
    book <- list(D1=pc_sheet(pc_blank("column"),s,"Untitled data"));active <- "D1"
  } else if(active==sheet) active <- names(book)[1]
  list(book=book,active=active,layout=layout)
}
