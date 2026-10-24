# Original workspace helpers: bounded table history and reusable graph formatting.
pc_history <- function() list(undo = list(), redo = list())
pc_history_bound <- function(stack, limit = 30L, bytes = 6e6) {
  while (length(stack) > 1L && (length(stack) > limit || sum(vapply(stack, function(x) nchar(x$data, type = "bytes"), numeric(1))) > bytes)) stack <- stack[-1L]
  stack
}
pc_history_record <- function(history, data, label, layout) {
  if (is.null(history)) history <- pc_history()
  history$undo <- pc_history_bound(c(history$undo, list(list(data = data, label = label, layout = layout))))
  history$redo <- list()
  history
}
pc_history_step <- function(history, current, direction, layout) {
  if (is.null(history)) history <- pc_history()
  if (!direction %in% c("undo", "redo")) stop("Invalid history direction.", call. = FALSE)
  stack <- history[[direction]]
  if (!length(stack)) return(NULL)
  item <- stack[[length(stack)]]
  if (!identical(item$layout, layout)) stop("Data history belongs to another table type.", call. = FALSE)
  other <- if (direction == "undo") "redo" else "undo"
  history[[direction]] <- head(stack, -1L)
  history[[other]] <- pc_history_bound(c(history[[other]], list(list(data = current, label = item$label, layout = layout))))
  list(history = history, table = pc_read_text(item$data, "\t"), label = item$label)
}
pc_graph_style <- function(source, target, size = FALSE) {
  keys <- c("palette", "font_size", "point_size", "legend_position", "grid_lines", "show_points", "annotation",
    "title_size","axis_title_size","axis_tick_size","text_color","axis_color","axis_line_width","point_shape","line_width","series_styles")
  if (isTRUE(size)) keys <- c(keys, "width", "height", "dpi", "x_axis_length", "y_axis_length")
  target[keys] <- source[keys]
  target
}
pc_copy_graph_style <- function(book, source, targets, size = FALSE) {
  keys <- pc_view_catalog(book)$key
  if (!is.character(source) || length(source) != 1L || !source %in% keys ||
      !is.character(targets) || !length(targets) || anyDuplicated(targets) ||
      any(!targets %in% keys) || source %in% targets) stop("Choose a source graph and at least one different target graph.", call. = FALSE)
  parts <- function(key) strsplit(key, ":", fixed = TRUE)[[1]]
  id <- parts(source); original <- book[[id[1]]]$views[[id[2]]]$settings
  for (key in targets) {
    id <- parts(key); sh <- book[[id[1]]]
    sh$views[[id[2]]]$settings <- pc_graph_style(original, sh$views[[id[2]]]$settings, size)
    if (sh$active_view == id[2]) sh$settings <- sh$views[[id[2]]]$settings
    book[[id[1]]] <- sh
  }
  book
}
pc_navigator_filter <- function(book, query = "") {
  query <- tolower(trimws(substr(query, 1, 100)))
  if (!nzchar(query)) return(book)
  out <- list()
  for (id in names(book)) {
    sh <- book[[id]]
    if (!grepl(query, tolower(paste(id, sh$name, sh$settings$layout)), fixed = TRUE)) {
      sh$views <- Filter(function(v) grepl(query, tolower(v$name), fixed = TRUE), sh$views)
      if (!length(sh$views)) next
    }
    out[[id]] <- sh
  }
  out
}
