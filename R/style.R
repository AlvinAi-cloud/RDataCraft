# Original RDataCraft plotting helpers, GPL-3.0.
# Built from ggplot2 theme and geometry primitives; no ggprism code is used.
pc_theme <- function(base_size = 7, line_size = 0.55) {
  ggplot2::theme_classic(base_size = base_size, base_family = "sans") +
    ggplot2::theme(
      text = ggplot2::element_text(color = "black"),
      axis.text = ggplot2::element_text(size = base_size, color = "black"),
      axis.title = ggplot2::element_text(size = base_size, face = "bold"),
      axis.line = ggplot2::element_line(color = "black", linewidth = line_size),
      axis.ticks = ggplot2::element_line(color = "black", linewidth = line_size),
      axis.ticks.length = grid::unit(3.5, "pt"),
      legend.key = ggplot2::element_blank(),
      legend.text = ggplot2::element_text(size = base_size),
      legend.background = ggplot2::element_blank(),
      legend.title = ggplot2::element_blank(),
      strip.background = ggplot2::element_rect(fill = "white", color = "black", linewidth = line_size),
      strip.text = ggplot2::element_text(size = base_size, face = "bold", color = "black"),
      plot.background = ggplot2::element_rect(fill = "white", color = NA),
      panel.background = ggplot2::element_rect(fill = "white", color = NA))
}

pc_comparison_layers <- function(comparisons, groups, span, text_size = 3.2) {
  # Comparisons retain their reported order/direction; endpoints only locate the bracket.
  ann <- comparisons[is.finite(comparisons$p) & !is.na(comparisons$label), , drop = FALSE]
  if (!nrow(ann)) return(list())
  ann$left <- match(ann$group1, groups); ann$right <- match(ann$group2, groups)
  if (anyNA(ann$left) || anyNA(ann$right)) stop("A comparison refers to a group outside the plotted table.", call. = FALSE)
  tip <- span * 0.01
  lines <- rbind(
    data.frame(x = ann$left, xend = ann$right, y = ann$y.position, yend = ann$y.position),
    data.frame(x = ann$left, xend = ann$left, y = ann$y.position, yend = ann$y.position - tip),
    data.frame(x = ann$right, xend = ann$right, y = ann$y.position, yend = ann$y.position - tip))
  labels <- data.frame(x = (ann$left + ann$right) / 2, y = ann$y.position + span * 0.015, label = ann$label)
  list(
    ggplot2::geom_segment(data = lines, ggplot2::aes(x = x, xend = xend, y = y, yend = yend),
                          inherit.aes = FALSE, color = "#334550", linewidth = 0.4, show.legend = FALSE),
    ggplot2::geom_text(data = labels, ggplot2::aes(x = x, y = y, label = label),
                       inherit.aes = FALSE, color = "#334550", size = text_size, vjust = 0, show.legend = FALSE))
}

pc_axis_limits <- function(settings, axis) {
  values <- vapply(c("min", "max"), function(bound) {
    value <- settings[[paste(axis, bound, sep = "_")]]
    if (is.null(value) || !nzchar(trimws(value))) return(NA_real_)
    number <- suppressWarnings(as.numeric(value))
    if (length(number) != 1 || !is.finite(number)) stop("Enter a finite axis limit, or leave it blank for automatic scaling.", call. = FALSE)
    number
  }, numeric(1))
  if (all(is.finite(values)) && values[1] >= values[2]) stop("An axis minimum must be below its maximum.", call. = FALSE)
  values
}
pc_validate_axes <- function(settings) {
  x <- pc_axis_limits(settings, "x"); y <- pc_axis_limits(settings, "y")
  if (isTRUE(settings$log_x) && any(x <= 0, na.rm = TRUE)) stop("Logarithmic X limits must be positive.", call. = FALSE)
  if (isTRUE(settings$log_y) && any(y <= 0, na.rm = TRUE)) stop("Logarithmic Y limits must be positive.", call. = FALSE)
  invisible(list(x = x, y = y))
}
pc_format_axes <- function(plot, normalized, settings) {
  limits <- pc_validate_axes(settings)
  numeric_x <- normalized$layout %in% c("xy", "survival", "multiple") || settings$graph %in% c("histogram", "ecdf", "qq", "density")
  numeric_y <- !settings$graph %in% c("heatmap","groupheat")
  if (any(is.finite(limits$x)) && !numeric_x) stop("X range controls apply to numeric axes. Category positions follow the source table.", call. = FALSE)
  if (any(is.finite(limits$y)) && !numeric_y) stop("The heatmap Y axis contains category labels.", call. = FALSE)
  if (numeric_y) {
    scale <- plot$scales$get_scales("y")
    if (is.null(scale)) {plot <- plot + ggplot2::scale_y_continuous(); scale <- plot$scales$get_scales("y")}
    # Anchor the baseline at a readable tick, without padding below it. Explicit
    # limits are applied by the coordinate system and remain exact.
    if (is.null(scale$limits) && !is.finite(limits$y[1])) {
      logarithmic <- isTRUE(settings$log_y)
      scale$limits <- function(range) {
        if (!all(is.finite(range))) return(range)
        lower <- if (logarithmic) 10^floor(log10(range[1])) else min(pretty(range, n=5))
        c(lower, range[2])
      }
    }
  }
  if (numeric_y || any(is.finite(limits$x)) || any(is.finite(limits$y))) plot <- plot + ggplot2::coord_cartesian(
    xlim = if (numeric_x && any(is.finite(limits$x))) limits$x else NULL,
    ylim = if (numeric_y && any(is.finite(limits$y))) limits$y else NULL,
    expand = c(bottom = !numeric_y, top = !is.finite(unname(limits$y[2])),
               left = !is.finite(unname(limits$x[1])), right = !is.finite(unname(limits$x[2]))))
  if (settings$x_axis_length > 0) plot <- plot + ggplot2::theme(panel.widths=grid::unit(settings$x_axis_length,"mm"))
  if (settings$y_axis_length > 0) plot <- plot + ggplot2::theme(panel.heights=grid::unit(settings$y_axis_length,"mm"))
  position <- settings$legend_position
  if (!is.null(position) && position != "auto") plot <- plot + ggplot2::theme(legend.position = position)
  if (isTRUE(settings$grid_lines)) plot <- plot + ggplot2::theme(panel.grid.major = ggplot2::element_line(color = "#e6edE8", linewidth = 0.3), panel.grid.minor = ggplot2::element_blank())
  size <- function(key, fallback) if (is.null(settings[[key]]) || settings[[key]] == 0) fallback else settings[[key]]
  color <- if (is.null(settings$text_color)) "#000000" else settings$text_color
  axis <- if (is.null(settings$axis_color)) "#000000" else settings$axis_color
  line <- if (is.null(settings$axis_line_width)) 0.55 else settings$axis_line_width
  plot <- plot + ggplot2::theme(
    plot.title = ggplot2::element_text(size = size("title_size", settings$font_size), color = color),
    axis.title = ggplot2::element_text(size = size("axis_title_size", settings$font_size), color = color),
    axis.text = ggplot2::element_text(size = size("axis_tick_size", settings$font_size), color = color),
    axis.line = ggplot2::element_line(color = axis, linewidth = line), axis.ticks = ggplot2::element_line(color = axis, linewidth = line))
  if (isTRUE(settings$override_x_title)) plot <- plot + ggplot2::labs(x = settings$x_label)
  if (isTRUE(settings$override_y_title)) plot <- plot + ggplot2::labs(y = settings$y_label)
  for (i in seq_along(plot$layers)) {
    layer <- plot$layers[[i]]
    if (!is.null(settings$point_shape) && settings$point_shape > 0 && inherits(layer$geom, "GeomPoint") && !identical(layer$aes_params$shape, 95))
      plot$layers[[i]]$aes_params$shape <- settings$point_shape
    if (!is.null(settings$line_width) && settings$line_width > 0 && (inherits(layer$geom, "GeomLine") || inherits(layer$geom, "GeomStep")))
      plot$layers[[i]]$aes_params$linewidth <- settings$line_width
  }
  plot
}

pc_validate_axis_lengths <- function(plot, settings) {
  if (settings$x_axis_length == 0 && settings$y_axis_length == 0) return(invisible(TRUE))
  g <- ggplot2::ggplotGrob(plot)
  if (sum(grepl("^panel($|-)",g$layout$name)) != 1L)
    stop("Exact axis lengths apply to a single plotting panel. Use automatic lengths for faceted graphs.",call.=FALSE)
  w <- grid::convertWidth(sum(g$widths),"mm",valueOnly=TRUE)
  h <- grid::convertHeight(sum(g$heights),"mm",valueOnly=TRUE)
  if (w > settings$width || h > settings$height)
    stop(sprintf("The axes and labels need at least %.1f × %.1f mm. Increase the canvas size or shorten the axes.",w,h),call.=FALSE)
  invisible(TRUE)
}
