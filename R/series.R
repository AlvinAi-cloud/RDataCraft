# Saved per-series appearance. Keys are source series names, never executable text.
pc_series_styles <- function(value = "{}") {
  if (!is.character(value) || length(value) != 1L || is.na(value) || nchar(value, type = "bytes") > 50000 || !grepl("^\\s*\\{", value))
    stop("Invalid series appearance settings.", call. = FALSE)
  styles <- tryCatch(jsonlite::fromJSON(value, simplifyVector = FALSE), error = function(e) NULL)
  if (!is.list(styles) || length(styles) > 50 || (length(styles) && (is.null(names(styles)) || anyDuplicated(names(styles)) || any(!nzchar(names(styles))) || any(nchar(names(styles)) > 300))))
    stop("Invalid series appearance settings.", call. = FALSE)
  bounds <- list(point_shape = c(1,25), point_size = c(1,6), line_width = c(.1,4))
  for (style in styles) {
    if (!is.list(style) || is.null(names(style)) || anyDuplicated(names(style)) || any(!names(style) %in% c("color", names(bounds), "line_type"))) stop("Invalid series appearance option.", call. = FALSE)
    for (key in names(style)) {
      v <- style[[key]]
      if (length(v) != 1L || is.list(v) || is.na(v)) stop("Invalid series appearance value.", call. = FALSE)
      if (key == "color") {
        if (!is.character(v) || !grepl("^#[0-9a-fA-F]{6}$", v)) stop("Choose a valid series color.", call. = FALSE)
      } else if (key == "line_type") {
        if (!is.character(v) || !v %in% c("solid","dashed","dotted","dotdash","longdash","twodash")) stop("Choose a valid line pattern.", call. = FALSE)
      } else if (!is.numeric(v) || !is.finite(v) || v < bounds[[key]][1] || v > bounds[[key]][2] || (key == "point_shape" && v != floor(v)))
        stop("Invalid series size or symbol.", call. = FALSE)
    }
  }
  styles
}
pc_series_colors <- function(n, s) {
  colors <- setNames(rep(pc_palettes[[s$palette]], length.out = length(n$groups)), n$groups)
  styles <- pc_series_styles(s$series_styles)
  for (g in intersect(names(styles), names(colors))) if (!is.null(styles[[g]]$color)) colors[g] <- styles[[g]]$color
  colors
}
pc_format_series <- function(plot, n, s) {
  styles <- pc_series_styles(s$series_styles)
  if (!length(styles) || n$layout == "contingency" || !length(n$groups)) return(plot)
  groups <- n$groups
  values <- function(key, fallback) setNames(vapply(groups, function(g) if (is.null(styles[[g]][[key]])) fallback else styles[[g]][[key]], fallback), groups)
  shapes <- values("point_shape", if(s$point_shape > 0) s$point_shape else if(n$layout == "column") 21 else 19)
  sizes <- values("point_size", s$point_size)
  widths <- values("line_width", if(s$line_width > 0) s$line_width else .75)
  types <- values("line_type", "solid")
  points_mapped <- FALSE; lines_mapped <- FALSE
  for (i in seq_along(plot$layers)) {
    layer <- plot$layers[[i]]
    # Preserve mean markers, censor crosses, pair connectors and annotation layers.
    has_group <- if (is.data.frame(layer$data)) "group" %in% names(layer$data) else isTRUE(layer$inherit.aes) && is.data.frame(plot$data) && "group" %in% names(plot$data)
    if (!has_group) next
    if (inherits(layer$geom,"GeomPoint") && !identical(layer$aes_params$shape,95) && n$layout != "survival") {
      points_mapped <- TRUE
      layer$mapping$shape <- ggplot2::aes(shape = group)$shape
      layer$mapping$size <- ggplot2::aes(size = group)$size
      layer$aes_params$shape <- NULL; layer$aes_params$size <- NULL
    }
    if ((inherits(layer$geom,"GeomLine") || inherits(layer$geom,"GeomStep")) && is.null(layer$aes_params$color) && is.null(layer$aes_params$colour)) {
      lines_mapped <- TRUE
      layer$mapping$linewidth <- ggplot2::aes(linewidth = group)$linewidth
      layer$mapping$linetype <- ggplot2::aes(linetype = group)$linetype
      layer$aes_params$linewidth <- NULL; layer$aes_params$linetype <- NULL
    }
    plot$layers[[i]] <- layer
  }
  if (points_mapped) plot <- plot + ggplot2::scale_shape_manual(values = shapes, name = NULL) + ggplot2::scale_size_manual(values = sizes, name = NULL)
  if (lines_mapped) plot <- plot + ggplot2::scale_linewidth_manual(values = widths, name = NULL) + ggplot2::scale_linetype_manual(values = types, name = NULL)
  plot + ggplot2::labs(color=NULL,fill=NULL,shape=NULL,size=NULL,linewidth=NULL,linetype=NULL)
}
