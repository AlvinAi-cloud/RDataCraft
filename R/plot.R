source("R/devices.R", local = TRUE)
source("R/style.R", local = TRUE)
source("R/series.R", local = TRUE)

pc_defaults <- function() list(layout = "column", method = "welch", graph = "points",
  error = "sem", palette = "craft", title = "Treatment response", x_label = "Condition",
  y_label = "Response (a.u.)", font_size = 7, point_size = 2.8, show_points = TRUE,
  show_p = TRUE, log_y = FALSE, log_x = FALSE, width = 76.2, height = 76.2, dpi = 300,
  group1 = "Control", group2 = "Treatment A", correction = "holm", null_mean = 0, annotation = "p",
  x_min = "", x_max = "", y_min = "", y_max = "", legend_position = "auto", grid_lines = FALSE,
  title_size = 0, axis_title_size = 0, axis_tick_size = 0, text_color = "#000000", axis_color = "#000000",
  axis_line_width = 0.55, point_shape = 0, line_width = 0, override_x_title = FALSE, override_y_title = FALSE,
  xy_connections = "auto", xy_show_fit = TRUE, xy_fit_band = TRUE,
  xy_compare = FALSE, xy_compare_group1 = "", xy_compare_group2 = "", xy_compare_correction = "holm", xy_compare_significant_only = TRUE,
  fit_constraints = "{}", fit_mode = "independent", fit_weight = "none", fit_replicates = "individual", fit_scope = "selected", series_styles = "{}", x_tick_step = "", y_tick_step = "", x_tick_angle = 0, ref_x = "", ref_y = "", x_axis_length = 0, y_axis_length = 0,
  pca_scale = TRUE, pca_missing = "error", pca_variables = "", pca_label_column = "", pca_group_column = "", pca_x = 1, pca_y = 2, pca_labels = FALSE)

pc_palettes <- list(craft = c("#247763", "#D6A64D", "#6B9CC3", "#A18AB9", "#D18491", "#5FA88F"),
  accessible = c("#0072B2", "#D55E00", "#009E73", "#CC79A7", "#E69F00", "#56B4E9", "#000000"),
  monochrome = c("#233C49", "#536C79", "#849AA5", "#B6C5CC", "#D6E0E5"),
  vivid = c("#3569B0", "#D34F4F", "#36A184", "#9B5DA8", "#E6A12B", "#4CA7B9", "#A77351", "#D67AA8"),
  ocean = c("#174A70", "#2483A0", "#40A99D", "#789BC5", "#5266A0", "#82B7A5", "#546C83", "#A1BBD1"),
  warm = c("#AD3B41", "#D87535", "#C49B2B", "#A35B78", "#D79477", "#8C4A35", "#BC7B9F", "#D3AB68"),
  earth = c("#506C45", "#AB743C", "#78709A", "#398A83", "#B55F59", "#9A963F", "#627A98", "#96624A"),
  pastel = c("#80B5CC", "#DCA0A0", "#93BFA5", "#B3A1CC", "#DDC183", "#83BCBB", "#C8AD94", "#CFA7C7"),
  contrast = c("#245A91", "#B73D46", "#23764A", "#8C469A", "#B77912", "#127F91", "#763E2D", "#51545B"))
pc_palette_choices <- function() setNames(names(pc_palettes),c("RDataCraft","Colorblind accessible","Monochrome","Vivid","Ocean","Warm","Earth","Pastel","High contrast"))

# Identify observation and summary layers without relying on their symbol shape.
pc_observation_points <- function(...) {
  layer <- ggplot2::geom_point(...,alpha=.55)
  layer$pc_role <- "observations"
  layer
}
pc_summary_points <- function(...) {
  layer <- ggplot2::geom_point(...)
  layer$pc_role <- "summary"
  layer
}

pc_plot_basic <- function(normalized, settings, analysis = NULL) {
  d <- normalized$data
  if (!nrow(d)) stop("Enter observations in D1 to create a graph.", call. = FALSE)
  if (settings$log_y && any(d$value <= 0)) stop("A log Y axis requires every plotted observation to be greater than zero.", call. = FALSE)
  if (settings$log_x && normalized$layout == "xy" && any(d$x <= 0)) stop("A log X axis requires every X value to be greater than zero.", call. = FALSE)
  colors <- pc_series_colors(normalized, settings)
  names(colors) <- normalized$groups
  if (normalized$layout == "xy") {
    p <- ggplot2::ggplot(d, ggplot2::aes(x = x, y = value, color = group))
    if (pc_xy_connects(settings)) p <- p + ggplot2::geom_line(data = stats::aggregate(value ~ x + group, d, mean), linewidth = 0.65)
    if(settings$show_points) p <- p + pc_observation_points(size = settings$point_size)

  } else {
    p <- ggplot2::ggplot(d, ggplot2::aes(x = group, y = value, color = group, fill = group))
    if (settings$graph == "violin") {
      if (any(table(d$group) < 2)) stop("Violin plots need at least two observations in each group.", call. = FALSE)
      p <- p + ggplot2::geom_violin(trim = TRUE, alpha = 0.16, linewidth = 0.65, width = 0.8)
    }
    if (settings$graph == "box") p <- p + ggplot2::geom_boxplot(width = 0.42, alpha = 0.15, outlier.shape = NA, linewidth = 0.6)
    if (settings$graph == "paired" && settings$show_points) p <- p + ggplot2::geom_line(ggplot2::aes(group = row_id), color = "#A6B4BC", linewidth = 0.5, alpha = 0.65)
    summary <- pc_summary(normalized)
    summary$group <- factor(summary$group, levels = normalized$groups)
    summary$margin <- switch(settings$error, sd = summary$sd, sem = summary$sem,
                             ci = summary$ci_high - summary$mean, none = NA_real_)
    if (settings$graph == "bar") p <- p + ggplot2::geom_col(data = summary,
      ggplot2::aes(y = mean), width = 0.6, alpha = 0.23, linewidth = 0.65)
    if (settings$show_points) {
      position <- if (settings$graph == "paired") ggplot2::position_identity() else ggplot2::position_jitter(width = 0.1, height = 0, seed = 42)
      p <- p + pc_observation_points(position = position, size = settings$point_size, shape = 21, stroke = 0.6)
    }
    if (settings$graph %in% c("points", "bar", "paired")) {
      if (settings$log_y && any(summary$mean - summary$margin <= 0, na.rm = TRUE)) {
        stop("The error interval crosses zero and cannot be shown on a log axis. Choose 'None' for error bars or use a linear axis.", call. = FALSE)
      }
      if (settings$error != "none") p <- p + ggplot2::geom_errorbar(data = summary,
        ggplot2::aes(y = mean, ymin = mean - margin, ymax = mean + margin), width = 0.14, linewidth = 0.7, na.rm = TRUE)
      if (settings$graph != "bar") p <- p + ggplot2::geom_point(data = summary,
        ggplot2::aes(y = mean), shape = 95, size = 8, show.legend = FALSE, na.rm = TRUE)
    }
    if (settings$show_p && !is.null(analysis) && nrow(analysis$comparisons) && !settings$log_y) {
      ann <- analysis$comparisons
      span <- diff(range(d$value))
      if (!span) span <- max(abs(d$value), 1)
      ann$y.position <- max(d$value, summary$mean + summary$margin, na.rm = TRUE) + span * 0.14 * seq_len(nrow(ann))
      prefix <- if (analysis$method %in% c("anova", "multiple", "kruskal")) "adj. p" else "p"
      ann$label <- pc_p_label(ann$p,prefix,identical(settings$annotation,'stars'))
      p <- p + pc_comparison_layers(ann, normalized$groups, span, text_size = settings$font_size / ggplot2::.pt)
    }
  }
  p <- p + ggplot2::scale_color_manual(values = colors, drop = FALSE) +
    pc_theme(base_size = settings$font_size) +
    ggplot2::theme(legend.position = if (normalized$layout == "xy") "top" else "none",
                   axis.title = ggplot2::element_text(face = "bold"),
                   plot.title = ggplot2::element_text(hjust = 0, face = "bold", margin = ggplot2::margin(b = 20)),
                   plot.margin = ggplot2::margin(20, 25, 15, 20)) +
    ggplot2::labs(title = settings$title, x = settings$x_label, y = settings$y_label)
  if (normalized$layout == "column") p <- p + ggplot2::scale_fill_manual(values = colors, drop = FALSE) + ggplot2::scale_x_discrete(limits = normalized$groups, drop = FALSE)
  if (settings$log_y) p <- p + ggplot2::scale_y_log10(expand = ggplot2::expansion(mult = c(0.08, 0.15)))
  else p <- p + ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0.08, 0.12)))
  if (settings$log_x && normalized$layout == "xy") p <- p + ggplot2::scale_x_log10()
  p
}

source("R/graph_options.R", local = TRUE)
source("R/xy_comparisons.R", local = TRUE)
source("R/graphs.R", local = TRUE)
