pc_plot_raw <- function(normalized, settings, analysis = NULL) {
  n <- normalized; d <- n$data; s <- settings
  if (!s$graph %in% unname(pc_graphs(n$layout))) stop("Choose a graph compatible with this data table.", call. = FALSE)
  if(n$layout=="multiple") return(pc_plot_pca(n,s,analysis))
  if (!nrow(d)) stop("Enter observations to create a graph.", call. = FALSE)
  colors <- pc_series_colors(n, s)
  if (s$graph %in% c("mean","median","violinbox","density","step","area","groupbox","groupviolin","groupheat")) return(pc_plot_additional(n,s,analysis))
  if (n$layout == "column" && s$graph %in% c("points", "bar", "box", "violin", "paired")) return(pc_plot_basic(n, s, analysis))
  if (n$layout == "xy" && s$graph %in% c("scatter", "line")) {
    p <- pc_plot_basic(n, s, analysis)
    if (!is.null(analysis$curve)) {
      curve <- analysis$curve
      if (!"group" %in% names(curve)) curve$group <- s$group1
      if(all(c("lower","upper") %in% names(curve))) {
        if(s$log_y && any(curve$lower<=0, na.rm=TRUE)) stop("The fitted mean confidence interval crosses zero; use a linear Y axis.",call.=FALSE)
        p <- p + ggplot2::geom_ribbon(data=curve,ggplot2::aes(x=x,ymin=lower,ymax=upper,fill=group,group=group),inherit.aes=FALSE,alpha=.12,na.rm=TRUE,show.legend=FALSE) + ggplot2::scale_fill_manual(values=colors)
      }
      p <- p + ggplot2::geom_line(data=curve,ggplot2::aes(x=x,y=fit,color=group,group=group),inherit.aes=FALSE,linewidth=.9)
    }
    return(p)
  }
  if (s$log_y && n$layout %in% c("survival", "contingency")) stop("Use a linear axis for survival probabilities and counts.", call. = FALSE)
  if (s$log_y && any(d$value <= 0)) stop("A log Y axis requires positive observations.", call. = FALSE)
  if (s$log_x && n$layout == "xy" && any(d$x <= 0)) stop("A log X axis requires positive X values.", call. = FALSE)
  if (n$layout == "survival") {
    fit <- if (!is.null(analysis$survival_fit)) analysis$survival_fit else survival::survfit(survival::Surv(x, status) ~ group, data = d, conf.type = "log-log")
    ss <- summary(fit, censored = TRUE)
    groups <- if (is.null(ss$strata)) rep(n$groups[1], length(ss$time)) else sub("^group=", "", as.character(ss$strata))
    z <- data.frame(x = ss$time, survival = ss$surv, lower = ss$lower, upper = ss$upper, censored = ss$n.censor, group = groups)
    z <- rbind(data.frame(x = 0, survival = 1, lower = 1, upper = 1, censored = 0, group = n$groups), z)
    z <- z[order(match(z$group, n$groups), z$x), ]; z$group <- factor(z$group, levels = n$groups)
    p <- ggplot2::ggplot(z, ggplot2::aes(x = x, y = survival, color = group, group = group))
    if (s$graph == "km") p <- p + ggplot2::geom_ribbon(ggplot2::aes(ymin = lower, ymax = upper, fill = group), stat = StatStepribbon, alpha = 0.12, color = NA, na.rm = TRUE)
    p <- p + ggplot2::geom_step(linewidth = 0.85) + ggplot2::geom_point(data = z[z$censored > 0, ], shape = 3, size = s$point_size, stroke = 0.7) + ggplot2::scale_y_continuous(limits = c(0, 1), breaks = seq(0, 1, 0.2))
    # Risk counts at observed time landmarks are available in the analysis report.
  } else if (n$layout == "contingency") {
    d$category <- factor(d$category, levels = rownames(n$counts))
    if (s$graph == "heatmap") {
      p <- ggplot2::ggplot(d, ggplot2::aes(x = group, y = category, fill = value)) + ggplot2::geom_tile(color = "white", linewidth = 1) + ggplot2::geom_text(ggplot2::aes(label = value), color = "#263b32", size = s$font_size / ggplot2::.pt) + ggplot2::scale_fill_gradient(low = "#f1f5f2", high = "#5fa88f")
    } else {
      p <- ggplot2::ggplot(d, ggplot2::aes(x = group, y = value, fill = category)) + ggplot2::geom_col(position = if (s$graph == "proportions") "fill" else if (s$graph == "stacked") "stack" else "dodge", color = "#263b32", linewidth = 0.4, width = 0.7)
      if (s$graph == "proportions") p <- p + ggplot2::scale_y_continuous(labels = function(x) paste0(round(x * 100), "%"))
      p <- p + ggplot2::scale_fill_manual(values = rep(pc_palettes[[s$palette]], length.out = length(levels(d$category))))
    }
  } else if (n$layout == "grouped") {
    z <- pc_grouped_summary(n); z$group <- factor(z$group, levels = n$groups); z$condition <- factor(z$condition, levels = n$conditions)
    z$margin <- switch(s$error, sd = z$sd, sem = z$sem, ci = z$ci_high - z$mean, none = NA_real_)
    if (s$log_y && any(z$mean - z$margin <= 0, na.rm = TRUE)) stop("An error interval crosses zero; use a linear Y axis or turn off error bars.", call. = FALSE)
    position <- ggplot2::position_dodge(width = 0.72)
    p <- ggplot2::ggplot(z, ggplot2::aes(x = condition, y = mean, color = group, fill = group, group = group))
    if (s$graph == "groupbar") p <- p + ggplot2::geom_col(position = position, width = 0.65, alpha = 0.25, linewidth = 0.6)
    if (s$graph == "interaction") p <- p + ggplot2::geom_line(position = position, linewidth = 0.75)
    if (s$error != "none") p <- p + ggplot2::geom_errorbar(ggplot2::aes(ymin = mean - margin, ymax = mean + margin), position = position, width = 0.12, na.rm = TRUE)
    p <- p + ggplot2::geom_point(position = position, size = s$point_size + 0.3)
    if (s$show_points && s$graph != "interaction") p <- p + ggplot2::geom_point(data = d, ggplot2::aes(y = value), position = ggplot2::position_jitterdodge(jitter.width = 0.12, dodge.width = 0.72, seed = 42), size = s$point_size * 0.85, alpha = 0.8)
    if (s$show_p && !is.null(analysis) && nrow(analysis$comparisons)) p <- p + ggplot2::labs(caption = "Corrected within-level comparisons and confidence intervals: see Analysis results")
  } else if (n$layout == "xy") {
    if (s$graph == "residual") {
      if (is.null(analysis$diagnostics)) stop("Choose linear regression or four-parameter curve fitting to show residuals.", call. = FALSE)
      diagnostics <- analysis$diagnostics
      diagnostics$group <- if ("series" %in% names(diagnostics)) diagnostics$series else s$group1
      p <- ggplot2::ggplot(diagnostics, ggplot2::aes(x = fitted, y = residual, color = group)) + ggplot2::geom_hline(yintercept = 0, linetype = "dashed", color = "#68786e") + ggplot2::geom_point(size = s$point_size) + ggplot2::scale_color_manual(values = colors)
      if (s$log_y || s$log_x) stop("Use linear axes to inspect signed residuals.", call. = FALSE)
    } else {
      chunks <- split(d, list(d$group, d$x), drop = TRUE)
      z <- do.call(rbind, lapply(chunks, function(a) {nn <- nrow(a); sem <- stats::sd(a$value) / sqrt(nn); data.frame(x = a$x[1], group = a$group[1], mean = mean(a$value), sd = stats::sd(a$value), sem = sem, ci = if(nn > 1) qt(0.975, nn - 1) * sem else NA_real_)}))
      z$margin <- switch(s$error, sd = z$sd, sem = z$sem, ci = z$ci, none = NA_real_)
      if (s$log_y && any(z$mean - z$margin <= 0, na.rm = TRUE)) stop("An error interval crosses zero; use linear Y or turn off error bars.", call. = FALSE)
      z <- z[order(z$group,z$x),]
      p <- ggplot2::ggplot(z, ggplot2::aes(x = x, y = mean, color = group, group = group))
      if (s$graph == "xyband" && s$error != "none") {
        if (!any(is.finite(z$margin))) stop("Shaded SD / SEM intervals need at least two observations at a time point. Add Y replicates or choose None for the interval.",call.=FALSE)
        # Split at missing intervals so shading never bridges a time point whose
        # SD/SEM cannot be estimated from its replicates.
        z$segment <- interaction(z$group,ave(!is.finite(z$margin),z$group,FUN=cumsum),drop=TRUE)
        p <- p + ggplot2::geom_ribbon(data=z[is.finite(z$margin),],ggplot2::aes(ymin=mean-margin,ymax=mean+margin,fill=group,group=segment),colour=NA,alpha=.2,show.legend=FALSE) + ggplot2::scale_fill_manual(values=colors)
      }
      p <- p + ggplot2::geom_line(linewidth = 0.7) + ggplot2::geom_point(size = s$point_size)
      if (s$graph != "xyband" && s$error != "none") p <- p + ggplot2::geom_errorbar(ggplot2::aes(ymin = mean - margin, ymax = mean + margin), width = diff(range(d$x)) * 0.012, na.rm = TRUE)
      if (s$show_points) p <- p + ggplot2::geom_point(data = d, ggplot2::aes(y = value), size = s$point_size * 0.7, alpha = 0.45, show.legend = FALSE)
      if (s$graph == "xyband") p <- p + ggplot2::labs(caption=pc_xy_band_caption(n,s))
    }
  } else {
    p <- ggplot2::ggplot(d, ggplot2::aes(x = value, color = group, fill = group))
    if (s$graph == "histogram") p <- p + ggplot2::geom_histogram(bins = max(5, min(30, ceiling(sqrt(nrow(d))))), alpha = 0.35, position = "identity", linewidth = 0.5)
    if (s$graph == "ecdf") p <- p + ggplot2::stat_ecdf(linewidth = 0.8)
    if (s$graph == "qq") p <- ggplot2::ggplot(d, ggplot2::aes(sample = value, color = group)) + ggplot2::stat_qq(size = s$point_size) + ggplot2::stat_qq_line(linewidth = 0.6) + ggplot2::facet_wrap(~group, scales = "free")
    if (s$log_y) stop("Use linear axes for distribution diagnostic graphs.", call. = FALSE)
  }
  p <- p + pc_theme(base_size = s$font_size) +
    ggplot2::theme(legend.position = "top", axis.title = ggplot2::element_text(face = "bold"), plot.title = ggplot2::element_text(face = "bold", hjust = 0), plot.margin = ggplot2::margin(18, 22, 15, 18)) +
    ggplot2::labs(title = s$title, x = s$x_label, y = s$y_label, color = NULL, fill = NULL)
  if (n$layout != "contingency" && s$graph != "residual") p <- p + ggplot2::scale_color_manual(values = colors)
  if (s$graph %in% c("groupbar", "grouppoints", "interaction", "km", "histogram")) p <- p + ggplot2::scale_fill_manual(values = colors)
  if (s$show_p && n$layout %in% c("survival", "contingency", "grouped") && !is.null(analysis) && is.finite(analysis$p)) {
    prefix <- if (n$layout == "grouped") "Interaction P" else "P"
    label <- if(identical(s$annotation,'stars')) paste(prefix,pc_stars(analysis$p)) else pc_p_label(analysis$p,prefix)
    p <- p + ggplot2::labs(subtitle = label)
  }
  if (s$graph == "histogram") p <- p + ggplot2::labs(x = s$y_label, y = "Frequency")
  if (s$graph == "ecdf") p <- p + ggplot2::labs(x = s$y_label, y = "Cumulative probability")
  if (s$graph == "qq") p <- p + ggplot2::labs(x = "Theoretical normal quantiles", y = "Observed quantiles")
  if (s$graph == "residual") p <- p + ggplot2::labs(x = "Fitted response", y = "Residual")
  if (s$log_y) p <- p + ggplot2::scale_y_log10()
  if (s$log_x && n$layout == "xy") p <- p + ggplot2::scale_x_log10()
  p
}

pc_xy_band_caption <- function(n,s) {
  interval <- switch(s$error,sd="Shading: mean ± SD",sem="Shading: mean ± SEM",ci="Shading: 95% CI of the mean",none="Mean response; shading off")
  paste0(interval," at each X (not a fitted confidence band).",
    if (s$error!="none" && any(table(interaction(n$data$group,n$data$x,drop=TRUE))<2)) " Shading omitted where fewer than two replicates are available." else "")
}

# Convert survival intervals to explicit steps rather than interpolating across event times.
StatStepribbon <- ggplot2::ggproto("StatStepribbon", ggplot2::Stat,
  required_aes = c("x", "ymin", "ymax"),
  compute_group = function(data, scales) {
    data <- data[order(data$x), , drop = FALSE]
    if (nrow(data) < 2) return(data)
    idx <- rep(seq_len(nrow(data)), each = 2)[-(nrow(data) * 2)]
    out <- data[idx, , drop = FALSE]; out$x <- rep(data$x, each = 2)[-1]
    out
  })


pc_plot <- function(normalized, settings, analysis = NULL) {
  p <- pc_plot_raw(normalized, settings, analysis)
  p <- pc_format_details(pc_format_axes(p, normalized, settings), normalized, settings)
  if(normalized$layout!="multiple") p <- pc_format_series(p,normalized,settings)
  pc_validate_axis_lengths(p,settings)
  p
}
