pc_methods <- function(layout) switch(layout,
  multiple = c("Principal component analysis (PCA)"="pca","Descriptive statistics"="descriptive"),
  column = c("Descriptive statistics" = "descriptive", "Welch's unpaired t test" = "welch", "Student's unpaired t test (equal variances)" = "student", "Paired t test (match by row)" = "paired", "Mann–Whitney test" = "mann", "Wilcoxon matched-pairs signed rank" = "signedrank", "One-sample t test" = "onesample", "One-way ANOVA + Tukey comparisons" = "anova", "Welch's one-way ANOVA" = "welchanova", "Kruskal–Wallis + corrected rank comparisons" = "kruskal", "Repeated-measures one-way ANOVA" = "rm_anova", "Friedman matched-groups test" = "friedman", "Multiple unpaired Welch t tests" = "multiple", "Shapiro–Wilk normality by group" = "normality"),
  xy = c("Descriptive statistics" = "descriptive", "Linear regression" = "linear", pc_regression_methods(), "Pearson correlation" = "pearson", "Spearman rank correlation" = "spearman", "Four-parameter dose-response curve" = "fourpl", "Area under curve (trapezoidal)" = "auc"),
  grouped = c("Descriptive statistics" = "descriptive", "Ordinary two-way ANOVA (balanced design)" = "twoway", "Compare groups within each factor level" = "simpleeffects"),
  contingency = c("Count summary" = "descriptive", "Fisher's exact test (2 × 2)" = "fisher", "Chi-square independence test" = "chisquare"),
  survival = c("Kaplan–Meier estimates" = "kaplan", "Log-rank (Mantel–Cox) test" = "logrank"))

pc_result <- function(n, method) list(method = method, title = names(pc_methods(n$layout))[match(method, pc_methods(n$layout))], metrics = data.frame(measure = character(), value = character()), comparisons = data.frame(), p = NA_real_, notes = character(), n = nrow(n$data), summary = pc_summary(n))
pc_metric <- function(name, value) data.frame(measure = name, value = as.character(value), row.names = NULL)
pc_fmt <- function(x) format(signif(x, 7), trim = TRUE)
pc_p_value <- function(p) vapply(p,function(x) if(!is.finite(x)) '—' else if(x<1e-6) '< 10⁻⁶' else format(signif(x,4),scientific=FALSE,trim=TRUE),character(1))
pc_p_label <- function(p,prefix='p',stars=FALSE) {
  if(isTRUE(stars)) return(pc_stars(p))
  values<-pc_p_value(p)
  ifelse(!is.finite(p),'',ifelse(p<1e-6,paste(prefix,values),paste(prefix,'=',values)))
}
pc_stars <- function(p) ifelse(!is.finite(p), "", ifelse(p <= 0.0001, "****", ifelse(p <= 0.001, "***", ifelse(p <= 0.01, "**", ifelse(p <= 0.05, "*", "ns")))))

pc_analyze <- function(normalized, method = "descriptive", group1 = NULL, group2 = NULL, options = list()) {
  n <- normalized; d <- n$data
  if(n$layout=="multiple") return(pc_analyze_multiple(n,method,utils::modifyList(pc_defaults(),options)))
  if (n$layout == "xy" && identical(options$fit_scope, "all") && method %in% c("linear", "fourpl", unname(pc_regression_methods())))
    return(pc_multifit(n, method, options))
  if(n$layout=="xy" && (method %in% unname(pc_regression_methods()) || (method=="linear" &&
    ((!is.null(options$fit_weight) && options$fit_weight!="none") || (!is.null(options$fit_replicates) && options$fit_replicates!="individual")))))
    return(pc_regression(n,method,group1,options))
  if (!method %in% unname(pc_methods(n$layout))) stop("This analysis does not support the selected table layout.", call. = FALSE)
  correction <- if (is.null(options$correction)) "holm" else options$correction
  if (!correction %in% c("holm", "bonferroni", "BH")) stop("Choose Holm, Bonferroni, or Benjamini–Hochberg correction.", call. = FALSE)
  null <- if (is.null(options$null_mean)) 0 else options$null_mean
  if (!is.numeric(null) || length(null) != 1 || !is.finite(null)) stop("Enter a finite null mean.", call. = FALSE)
  if (n$layout %in% c("column", "xy") && method %in% c("descriptive", "welch", "paired", "mann", "anova", "linear")) {
    r <- pc_analyze_basic(n, method, group1, group2)
    if (!is.null(r$model) && inherits(r$model, "lm")) {
      r$diagnostics <- data.frame(x = stats::model.frame(r$model)$x, observed = stats::model.response(stats::model.frame(r$model)), fitted = fitted(r$model), residual = residuals(r$model))
      co <- coef(r$model);se <- sqrt(diag(vcov(r$model)));ci <- confint(r$model)
      r$parameters <- data.frame(parameter=names(co),estimate=as.numeric(co),se=as.numeric(se),ci_low=ci[,1],ci_high=ci[,2])
      if (n$layout == "xy") {
        a <- n$data[n$data$group == group1, ]
        grid <- data.frame(x=seq(min(a$x),max(a$x),length.out=240))
        band <- stats::predict(r$model,grid,interval="confidence")
        r$curve <- data.frame(x=grid$x,fit=band[,"fit"],lower=band[,"lwr"],upper=band[,"upr"],group=group1)
      }
      r$metrics <- rbind(r$metrics,pc_metric("SSE",pc_fmt(sum(residuals(r$model)^2))),pc_metric("Residual degrees of freedom",df.residual(r$model)),pc_metric("AIC",pc_fmt(AIC(r$model))))
      r$notes <- c(r$notes, "Inspect the residual graph for curvature and unequal spread. The displayed regression band is a 95% confidence interval for the mean, not a prediction interval.")
    }
    return(r)
  }
  r <- pc_result(n, method); m <- pc_metric; fmt <- pc_fmt
  adjust <- function(tab) { tab$p_raw <- tab$p; tab$p <- stats::p.adjust(tab$p, correction); tab$significance <- pc_stars(tab$p); tab }
  if (n$missing) r$notes <- c(r$notes, paste(n$missing, "blank replicate cells excluded; matched analyses use only complete subjects."))
  if (method == "descriptive") {
    r$metrics <- m("Table type", n$layout)
    if (n$layout == "grouped") r$summary <- pc_grouped_summary(n)
    return(r)
  }
  if (n$layout == "contingency") {
    counts <- n$counts
    if (any(rowSums(counts) == 0) || any(colSums(counts) == 0)) stop("Every row and column needs a positive total for this test.", call. = FALSE)
    if (method == "fisher") {
      if (!identical(dim(counts), c(2L, 2L))) stop("Fisher's exact test currently requires a 2 × 2 count table.", call. = FALSE)
      test <- stats::fisher.test(counts)
      r$metrics <- rbind(m("Odds ratio (conditional MLE)", fmt(test$estimate)), m("Odds ratio exact 95% CI", paste(fmt(test$conf.int), collapse = " to ")), m("P value (two-sided)", fmt(test$p.value)))
      r$notes <- c("Exact conditional test. Odds ratio uses row 1 versus row 2 in column 1 relative to column 2; changing category order changes its direction.")
    } else {
      test <- suppressWarnings(stats::chisq.test(counts, correct = FALSE))
      r$expected <- as.data.frame(test$expected)
      r$metrics <- rbind(m("Pearson chi-square", fmt(test$statistic)), m("Degrees of freedom", test$parameter), m("P value", fmt(test$p.value)), m("Minimum expected count", fmt(min(test$expected))))
      r$notes <- c("Pearson chi-square test without Yates continuity correction; observations must be independent.", if (any(test$expected < 5)) "Some expected counts are below 5: the asymptotic approximation may be poor. Consider Fisher's exact test for a 2 × 2 table." else "All expected cell counts are at least 5.")
    }
    r$p <- test$p.value; return(r)
  }
  if (n$layout == "survival") {
    if (!nrow(d)) stop("Enter complete survival subjects.", call. = FALSE)
    fit <- survival::survfit(survival::Surv(x, status) ~ group, data = d, conf.type = "log-log")
    r$survival_fit <- fit
    ticks <- pretty(c(0, max(d$x)), n = 5); ticks <- ticks[ticks >= 0 & ticks <= max(d$x)]
    risk <- summary(fit, times = ticks, extend = TRUE)
    r$at_risk <- data.frame(group = if (is.null(risk$strata)) rep(n$groups[1], length(risk$time)) else sub("^group=", "", as.character(risk$strata)), time = risk$time, at_risk = risk$n.risk, survival = risk$surv)
    tab <- summary(fit)$table
    if (is.null(dim(tab))) tab <- matrix(tab, nrow = 1, dimnames = list(paste0("group=", n$groups[1]), names(tab)))
    r$summary <- data.frame(group = sub("^group=", "", rownames(tab)), n = tab[, "records"], events = tab[, "events"], median = tab[, "median"], median_ci_low = tab[, "0.95LCL"], median_ci_high = tab[, "0.95UCL"], row.names = NULL)
    r$metrics <- rbind(m("Subjects", nrow(d)), m("Events / censored", paste(sum(d$status), sum(d$status == 0), sep = " / ")))
    if (method == "logrank") {
      if (length(n$groups) < 2 || !sum(d$status)) stop("Log-rank testing needs at least two groups and one observed event.", call. = FALSE)
      test <- survival::survdiff(survival::Surv(x, status) ~ group, data = d, rho = 0)
      r$p <- stats::pchisq(test$chisq, length(test$n) - 1, lower.tail = FALSE)
      if (!is.finite(r$p)) stop("The log-rank statistic is undefined for these event times.", call. = FALSE)
      r$metrics <- rbind(r$metrics, m("Log-rank chi-square", fmt(test$chisq)), m("Degrees of freedom", length(test$n) - 1), m("P value (overall)", fmt(r$p)))
    }
    r$notes <- "Right censoring only. Assumes independent subjects and noninformative censoring. Curves show Greenwood log-log 95% intervals; a median or limit is blank when not estimable. The log-rank test is most sensitive under proportional hazards."
    return(r)
  }
  if (n$layout == "grouped") {
    if (length(n$groups) < 2 || length(n$conditions) < 2) stop("Two-factor analysis needs at least two levels of each factor.", call. = FALSE)
    r$summary <- pc_grouped_summary(n)
    if (method == "twoway") {
      cells <- table(d$condition, d$group)
      if (any(cells < 2) || length(unique(as.vector(cells))) != 1) stop("This two-way ANOVA requires a complete balanced design with at least two independent replicates per cell. Use equal cell sizes; unbalanced Type II/III models are not yet supported.", call. = FALSE)
      fit <- stats::aov(value ~ condition * group, data = d); tab <- summary(fit)[[1]]
      r$p <- tab$`Pr(>F)`[3]
      if (!is.finite(r$p)) stop("ANOVA needs nonzero residual variation.", call. = FALSE)
      r$effects <- data.frame(effect = c(n$factor_names, paste(n$factor_names, collapse = " × "), "Residuals"), df = tab$Df, sum_squares = tab$`Sum Sq`, mean_square = tab$`Mean Sq`, F = tab$`F value`, p = tab$`Pr(>F)`)
      r$metrics <- rbind(m("Design", "Ordinary balanced two-way ANOVA with interaction"), m("P value (interaction)", fmt(r$p)), m("Replicates per cell", cells[1]))
      r$notes <- c("Independent replicates, normally distributed errors, and equal variances are assumed. Factor tests use sequential sums of squares, equivalent to conventional factorial tests for this balanced design. This is not a repeated-measures model.", "Interpret the interaction before main effects. No post hoc comparisons are implied by the omnibus P values.")
    } else {
      parts <- lapply(n$conditions, function(level) {
        dd <- d[d$condition == level, ]; pairs <- utils::combn(n$groups, 2, simplify = FALSE)
        do.call(rbind, lapply(pairs, function(pair) {
          a <- dd$value[dd$group == pair[1]]; b <- dd$value[dd$group == pair[2]]
          if (length(a) < 2 || length(b) < 2) stop("Each compared cell needs two or more replicates.", call. = FALSE)
          tt <- stats::t.test(a, b)
          data.frame(condition = level, group1 = pair[1], group2 = pair[2], estimate = mean(a) - mean(b), ci_low = tt$conf.int[1], ci_high = tt$conf.int[2], p = tt$p.value)
        }))
      })
      r$comparisons <- adjust(do.call(rbind, parts)); r$metrics <- m("Comparison family", paste(nrow(r$comparisons), "Welch tests;", correction, "correction across ALL displayed comparisons"))
      r$notes <- "Independent two-sided Welch tests within factor levels. P values are corrected as one family across all levels and pairs. Confidence intervals are individual 95% intervals, not simultaneous intervals."
    }
    return(r)
  }
  if (is.null(group1) || !group1 %in% n$groups) stop("Choose a valid group or series.", call. = FALSE)
  a <- d[d$group == group1, , drop = FALSE]; x <- a$value
  if (n$layout == "xy") {
    if (method %in% c("pearson", "spearman")) {
      if (nrow(a) < 3 || length(unique(a$x)) < 2 || length(unique(x)) < 2) stop("Correlation needs at least three observations and variation on both axes.", call. = FALSE)
      test <- if (method == "pearson") stats::cor.test(a$x, x, method = method) else stats::cor.test(a$x, x, method = method, exact = FALSE)
      r$p <- test$p.value
      r$metrics <- rbind(m("Series", group1), m("Observations", length(x)), m(if (method == "pearson") "Pearson r" else "Spearman rho", fmt(test$estimate)), m("P value (two-sided)", fmt(r$p)))
      if (!is.null(test$conf.int)) r$metrics <- rbind(r$metrics, m("Correlation 95% CI", paste(fmt(test$conf.int), collapse = " to ")))
      r$notes <- if (method == "pearson") "Independent (X,Y) pairs; Pearson inference assumes a bivariate normal population. Correlation does not establish causation." else "Spearman rank correlation with asymptotic P value; ties are handled using ranks. Independent observations are assumed."
    } else if (method == "auc") {
      r$summary <- do.call(rbind, lapply(n$groups, function(g) {
        z <- d[d$group == g, ]; z <- stats::aggregate(value ~ x, z, mean); z <- z[order(z$x), ]
        if (nrow(z) < 2) stop("AUC needs two distinct X values per series.", call. = FALSE)
        data.frame(group = g, x_min = min(z$x), x_max = max(z$x), auc = sum(diff(z$x) * (head(z$value, -1) + tail(z$value, -1)) / 2))
      }))
      r$metrics <- m("Integration", "Signed trapezoidal area above Y = 0 over each series' observed X range")
      r$notes <- "Repeated X values are averaged before integration. No extrapolation, baseline subtraction, confidence interval, or between-group test is performed. Compare AUCs only over the same X range."
    } else return(pc_fourpl(n, group1, options))
    return(r)
  }
  if (method == "normality") {
    r$summary <- do.call(rbind, lapply(n$groups, function(g) {
      y <- d$value[d$group == g]
      if (length(y) < 3 || length(y) > 5000 || length(unique(y)) < 2) return(data.frame(group = g, n = length(y), W = NA_real_, p = NA_real_, status = "Needs 3–5000 nonconstant values"))
      test <- stats::shapiro.test(y); data.frame(group = g, n = length(y), W = unname(test$statistic), p = test$p.value, status = "Tested")
    }))
    r$metrics <- m("Normality", "Shapiro–Wilk test for each group")
    r$notes <- "P values are unadjusted diagnostic results. A nonsignificant normality test does not demonstrate normality; use the Q–Q graph and consider sample size and study design. Do not automatically choose a test from this P value."
    return(r)
  }
  if (method %in% c("welchanova", "kruskal", "multiple")) {
    if (length(n$groups) < 2 || any(table(d$group) < 2)) stop("Each group needs at least two observations.", call. = FALSE)
    if (method == "welchanova") {
      test <- stats::oneway.test(value ~ group, d, var.equal = FALSE); r$p <- test$p.value
      r$metrics <- rbind(m("Welch F statistic", fmt(test$statistic)), m("Degrees of freedom", paste(fmt(test$parameter), collapse = ", ")), m("P value (omnibus)", fmt(r$p)))
      r$notes <- "Welch one-way ANOVA does not assume equal variances. Independent observations and approximately normal group distributions are assumed. No post hoc comparisons are included."
    } else {
      pairs <- utils::combn(n$groups, 2, simplify = FALSE)
      r$comparisons <- adjust(do.call(rbind, lapply(pairs, function(pair) {
        xx <- d$value[d$group == pair[1]]; yy <- d$value[d$group == pair[2]]
        if (method == "multiple") {
          tt <- stats::t.test(xx, yy)
          data.frame(group1 = pair[1], group2 = pair[2], estimate = mean(xx) - mean(yy), ci_low = tt$conf.int[1], ci_high = tt$conf.int[2], p = tt$p.value)
        } else {
          tt <- stats::wilcox.test(xx, yy, exact = FALSE, correct = TRUE)
          data.frame(group1 = pair[1], group2 = pair[2], p = tt$p.value)
        }
      })))
      r$metrics <- m("Multiple comparisons", paste(correction, "correction across", length(pairs), "pairwise tests"))
      if (method == "kruskal") {
        tt <- stats::kruskal.test(value ~ group, d); r$p <- tt$p.value
        r$metrics <- rbind(r$metrics, m("Kruskal–Wallis chi-square", fmt(tt$statistic)), m("Degrees of freedom", tt$parameter), m("P value (omnibus)", fmt(r$p)))
      }
      r$notes <- if (method == "multiple") "All pairwise two-sided Welch tests; corrected P values and individual (not simultaneous) 95% CIs. Requires independent observations." else "Kruskal–Wallis with tie correction, followed by pairwise asymptotic Mann–Whitney tests with continuity correction and corrected P values. These are not Dunn comparisons. Assumes independent observations; tests distributions, not necessarily medians."
    }
    if (method != "multiple" && !is.finite(r$p)) stop("The test statistic is undefined; check variation.", call. = FALSE)
    return(r)
  }
  if (method %in% c("rm_anova", "friedman")) {
    wide <- matrix(NA_real_, nrow = n$rows, ncol = length(n$groups), dimnames = list(NULL, n$groups))
    for (g in n$groups) { z <- d[d$group == g, ]; wide[z$row_id, g] <- z$value }
    wide <- wide[stats::complete.cases(wide), , drop = FALSE]
    if (nrow(wide) < 3 || ncol(wide) < 2) stop("Matched-group analyses need at least three complete subjects and two conditions.", call. = FALSE)
    if (method == "friedman") {
      tt <- stats::friedman.test(wide); r$p <- tt$p.value
      r$metrics <- rbind(m("Friedman chi-square", fmt(tt$statistic)), m("Degrees of freedom", tt$parameter), m("P value", fmt(r$p)))
      r$notes <- "Nonparametric blocked comparison. Subjects (rows) must be independent; columns are repeated conditions. Asymptotic chi-square P value. No post hoc tests."
    } else {
      dd <- data.frame(value = as.vector(wide), subject = factor(rep(seq_len(nrow(wide)), ncol(wide))), condition = factor(rep(n$groups, each = nrow(wide))))
      fit <- stats::aov(value ~ condition + Error(subject/condition), dd)
      tab <- summary(fit)[[2]][[1]]; r$p <- tab$`Pr(>F)`[1]
      r$metrics <- rbind(m("F statistic", fmt(tab$`F value`[1])), m("Degrees of freedom", paste(tab$Df, collapse = ", ")), m("P value (uncorrected)", fmt(r$p)))
      r$notes <- "Complete-case one-way repeated-measures ANOVA. Sphericity is assumed with three or more conditions. Greenhouse–Geisser correction, mixed effects, and repeated-measures post hoc comparisons are not yet provided. Use only when these assumptions are justified."
    }
    if (!is.finite(r$p)) stop("Matched-group test is undefined for these values.", call. = FALSE)
    r$metrics <- rbind(m("Complete subjects", nrow(wide)), m("Incomplete subjects excluded", n$rows - nrow(wide)), r$metrics)
    return(r)
  }
  if (method == "onesample") {
    if (length(x) < 2) stop("A one-sample t test needs two or more observations.", call. = FALSE)
    tt <- stats::t.test(x, mu = null); r$p <- tt$p.value
    r$metrics <- rbind(m("Group", group1), m("Null mean", null), m("Mean", fmt(mean(x))), m("Mean 95% CI", paste(fmt(tt$conf.int), collapse = " to ")), m("t statistic", fmt(tt$statistic)), m("Degrees of freedom", tt$parameter), m("P value (two-sided)", fmt(r$p)))
    r$notes <- "Assumes independent observations from an approximately normal population; one selected group and one prespecified null mean."
  } else {
    if (is.null(group2) || !group2 %in% n$groups || group2 == group1) stop("Choose two different groups.", call. = FALSE)
    b <- d[d$group == group2, ]; y <- b$value
    if (method == "signedrank") {
      z <- merge(a[c("row_id", "value")], b[c("row_id", "value")], by = "row_id"); x <- z$value.x; y <- z$value.y
      if (length(x) < 2 || !any(x != y)) stop("Need at least two complete pairs with a nonzero difference.", call. = FALSE)
      tt <- stats::wilcox.test(x, y, paired = TRUE, exact = FALSE, correct = TRUE)
      r$metrics <- rbind(m("Complete pairs", length(x)), m("Incomplete pairs excluded", n$rows - length(x)), m("V statistic", fmt(tt$statistic)), m("P value (two-sided)", fmt(tt$p.value)))
      r$notes <- "Asymptotic Wilcoxon signed-rank test with continuity correction. Zero differences excluded from ranking. Assumes independent pairs and a symmetric distribution of within-pair differences."
      r$comparisons <- data.frame(group1 = group1, group2 = group2, p = tt$p.value)
    } else {
      if (length(x) < 2 || length(y) < 2) stop("Each group needs two or more observations.", call. = FALSE)
      tt <- stats::t.test(x, y, var.equal = TRUE)
      r$metrics <- rbind(m("Mean difference", fmt(mean(x) - mean(y))), m("Difference 95% CI", paste(fmt(tt$conf.int), collapse = " to ")), m("t statistic", fmt(tt$statistic)), m("Degrees of freedom", tt$parameter), m("P value (two-sided)", fmt(tt$p.value)))
      r$comparisons <- data.frame(group1 = group1, group2 = group2, estimate = mean(x) - mean(y), ci_low = tt$conf.int[1], ci_high = tt$conf.int[2], p = tt$p.value)
      r$notes <- "Student's unpaired t test assumes independent observations, approximately normal errors, and equal population variances. One comparison, with no multiplicity correction."
    }
    r$p <- tt$p.value
  }
  if (!is.finite(r$p)) stop("The test is undefined for these data.", call. = FALSE)
  r
}

pc_grouped_summary <- function(n) {
  do.call(rbind, lapply(n$conditions, function(level) {
    dd <- n$data[n$data$condition == level, ]; fake <- n; fake$data <- dd
    cbind(condition = level, pc_summary(fake))
  }))
}

pc_fourpl <- function(n, group, options = list()) {
  r <- pc_result(n, "fourpl"); prep <- pc_fit_data(n,group,options);a <- prep$data
  if (nrow(a) < 6 || length(unique(a$x)) < 5 || any(a$x <= 0) || stats::sd(a$value) == 0) stop("A four-parameter fit needs at least six observations, five distinct positive concentrations, and variation in Y. Enter concentrations, not log concentrations.", call. = FALSE)
  logx <- log10(a$x); span <- diff(range(a$value)); mid <- median(logx)
  # Tiny nonzero starts can yield a zero finite-difference derivative in nls.
  if(abs(mid)<1e-8) mid<-0
  log_span<-log(span);if(abs(log_span)<1e-8) log_span<-0
  bottom_start<-min(a$value);if(abs(bottom_start)<max(span,1)*1e-8) bottom_start<-0
  fits <- lapply(c(1, -1), function(direction) tryCatch(stats::nls(value ~ bottom + exp(logSpan) * plogis(hill * (log10(x) - logEC50)), data = a,
    start = list(bottom = bottom_start, logSpan = log_span, hill = direction, logEC50 = mid), weights=a$.weight, algorithm = "port",
    lower = c(bottom = -Inf, logSpan = log(span) - 8, hill = if (direction > 0) 0.02 else -10, logEC50 = min(logx) - 3),
    upper = c(bottom = Inf, logSpan = log(span) + 8, hill = if (direction > 0) 10 else -0.02, logEC50 = max(logx) + 3),
    control = stats::nls.control(maxiter = 500, warnOnly = FALSE)), error = function(e) NULL))
  fits <- Filter(Negate(is.null), fits)
  if (!length(fits)) stop("The four-parameter curve did not converge. Check concentration range and whether both plateaus are sampled.", call. = FALSE)
  fit <- fits[[which.min(vapply(fits, deviance, numeric(1)))]]; co <- coef(fit); se <- summary(fit)$coefficients[, 2]; crit <- qt(0.975, df.residual(fit))
  if (any(!is.finite(se))) stop("Curve parameter uncertainty could not be estimated. Add concentrations spanning both plateaus.", call. = FALSE)
  ec <- 10^co["logEC50"]; ec_ci <- 10^(co["logEC50"] + c(-1, 1) * crit * se["logEC50"])
  grid <- data.frame(x = 10^seq(min(logx), max(logx), length.out = 200))
  r$curve <- data.frame(x = grid$x, fit = as.numeric(predict(fit, grid)))
  r$n <- nrow(a)
  r$diagnostics <- data.frame(x = a$x, observed = a$value, fitted = fitted(fit), residual = residuals(fit),weight=a$.weight)
  r$parameters <- data.frame(parameter = names(co), estimate = as.numeric(co), se = as.numeric(se), ci_low = as.numeric(co - crit * se), ci_high = as.numeric(co + crit * se))
  r$metrics <- rbind(pc_metric("Series", group), pc_metric("Bottom / top", paste(pc_fmt(c(co["bottom"], co["bottom"] + exp(co["logSpan"]))), collapse = " / ")), pc_metric("EC50 / IC50 (halfway between plateaus)", pc_fmt(ec)), pc_metric("EC50 / IC50 approximate 95% CI", paste(pc_fmt(ec_ci), collapse = " to ")), pc_metric("Hill coefficient (natural-logistic scale)", pc_fmt(co["hill"])), pc_metric("Conventional Hill slope (base 10)", pc_fmt(co["hill"] / log(10))), pc_metric("Residual SD", pc_fmt(summary(fit)$sigma)), pc_metric("Residual degrees of freedom", df.residual(fit)))
  r$notes <- c("Unweighted four-parameter least-squares fit on the original Y scale: bottom + (top − bottom) / (1 + exp(−h × (log10(X) − log10(EC50)))). Positive h gives an increasing curve; negative h gives inhibition. X must be concentrations, not their logarithms.", "Approximate local t/Wald intervals can be unreliable with poorly identified plateaus. No global fit comparison, weighting, robust fit, or profile-likelihood CI is provided. The graph shows the fitted curve without a confidence band.")
  r$notes[1] <- sub("Unweighted",if(prep$weighting=="none") "Unweighted" else paste("Weighted",prep$weighting),r$notes[1])
  r$metrics <- rbind(r$metrics,pc_metric("Replicates / weighting",paste(prep$mode,prep$weighting,sep=" / ")),
    pc_metric("SSE (original Y scale)",pc_fmt(sum(residuals(fit)^2))),pc_metric("Weighted SSE",pc_fmt(sum(a$.weight*residuals(fit)^2))),pc_metric("AIC",pc_fmt(AIC(fit))))
  r$notes[2] <- sub("weighting, ","",r$notes[2],fixed=TRUE)
  r$notes <- c(r$notes,paste("Replicate fitting:",prep$mode,"; source observations:",prep$raw_n,"; fitted points:",nrow(a)))
  if (co["logEC50"] < min(logx) || co["logEC50"] > max(logx) || abs(co["hill"]) > 9.9 || abs(co["hill"]) < 0.021) r$notes <- c(r$notes, "Fit warning: midpoint is outside the measured concentration range or the slope reached a fitting bound. Parameter estimates may be unreliable.")
  r
}
