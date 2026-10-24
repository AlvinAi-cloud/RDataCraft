# Independent fits share a model family, never parameters or a pooled P value.
pc_multifit <- function(n, method, options) {
  options$fit_scope <- "selected"
  results <- lapply(n$groups, function(g) tryCatch(pc_analyze(n, method, g, options = options), error = identity))
  names(results) <- n$groups
  ok <- !vapply(results, inherits, logical(1), "error")
  status <- data.frame(series = n$groups, status = ifelse(ok, "Fitted", "Not fitted"),
    detail = vapply(seq_along(results), function(i) if (ok[i]) "Independent fit; individual parameter intervals" else conditionMessage(results[[i]]), character(1)))
  if (!any(ok)) stop(paste(paste(status$series, status$detail, sep = ": "), collapse = "\n"), call. = FALSE)
  fitted <- results[ok]
  r <- pc_result(n, method)
  combine <- function(key) {
    pieces <- lapply(names(fitted), function(g) {
      d <- fitted[[g]][[key]]
      if (is.null(d) || !nrow(d)) return(NULL)
      if (key == "curve") d$group <- NULL
      # The established unweighted linear fit keeps its lm object for prediction.
      cbind(series = g, d, stringsAsFactors = FALSE)
    })
    columns <- unique(unlist(lapply(pieces, names)))
    pieces <- lapply(Filter(Negate(is.null), pieces), function(d) {for (key in setdiff(columns, names(d))) d[[key]] <- NA; d[columns]})
    if (!length(pieces)) return(NULL)
    do.call(rbind, pieces)
  }
  for (g in names(fitted)) if (is.null(fitted[[g]]$curve) && inherits(fitted[[g]]$model, "lm")) {
    a <- n$data[n$data$group == g, ]
    grid <- data.frame(x = seq(min(a$x), max(a$x), length.out = 240))
    ci <- predict(fitted[[g]]$model, grid, interval = "confidence")
    fitted[[g]]$curve <- data.frame(x = grid$x, fit = ci[,"fit"], lower = ci[,"lwr"], upper = ci[,"upr"])
  }
  r$metrics <- combine("metrics"); r$parameters <- combine("parameters")
  r$diagnostics <- combine("diagnostics"); r$curve <- combine("curve")
  r$curve$group <- r$curve$series
  r$fit_status <- status; r$n <- sum(vapply(fitted, function(x) x$n, numeric(1)))
  r$notes <- unique(c("Each populated source series is fitted independently with the same model and weighting settings. Parameters are not shared; no between-series comparison or pooled significance test is performed.",
    "All confidence intervals and per-series P values are individual and unadjusted across series.",
    if (any(!ok)) paste("Some series could not be fitted:", paste(status$series[!ok], collapse = ", "), ". See fit status for reasons."),
    unlist(lapply(fitted, function(x) x$notes))))
  r
}
