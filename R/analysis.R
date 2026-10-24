pc_analyze_basic <- function(normalized, method = "descriptive", group1 = NULL, group2 = NULL) {
  if (!method %in% unname(pc_methods(normalized$layout))) stop("This analysis does not support the selected table layout.", call. = FALSE)
  d <- normalized$data
  result <- list(method = method, title = names(pc_methods(normalized$layout))[match(method, pc_methods(normalized$layout))],
                 metrics = data.frame(measure = character(), value = character()),
                 comparisons = data.frame(), p = NA_real_, notes = character(),
                 n = nrow(d), summary = pc_summary(normalized))
  add <- function(measure, value) data.frame(measure = measure, value = as.character(value))
  fmt <- function(x) format(signif(x, 7), trim = TRUE, scientific = NA)
  if (normalized$missing) result$notes <- c(result$notes, sprintf("%d blank Y cell(s) excluded from descriptive statistics.", normalized$missing))
  if (method == "descriptive") {
    result$metrics <- rbind(add("Observations", nrow(d)), add("Groups", length(normalized$groups)),
                            add("Confidence level", "95% (Student's t interval for the mean)"))
    return(result)
  }
  if (is.null(group1) || !group1 %in% normalized$groups) stop("Select a valid first group or series.", call. = FALSE)
  a <- d[d$group == group1, , drop = FALSE]
  if (method == "linear") {
    if (nrow(a) < 3 || length(unique(a$x)) < 2) stop("Linear regression needs at least three observations and two distinct X values.", call. = FALSE)
    model <- stats::lm(value ~ x, data = a)
    fit <- summary(model)
    ci <- stats::confint(model)
    result$p <- fit$coefficients["x", "Pr(>|t|)"]
    result$n <- nrow(a)
    result$metrics <- rbind(add("Series", group1), add("Observations", nrow(a)),
      add("Slope", fmt(stats::coef(model)["x"])), add("Slope 95% CI", paste(fmt(ci["x", ]), collapse = " to ")),
      add("Intercept", fmt(stats::coef(model)[1])), add("R squared", fmt(fit$r.squared)),
      add("P value (slope = 0)", fmt(result$p)))
    result$model <- model
    result$notes <- c(result$notes, "Ordinary least squares with an intercept; X is treated as measured without error.")
    return(result)
  }
  if (method == "anova") {
    counts <- table(d$group)
    if (length(counts) < 2 || any(counts < 2)) stop("ANOVA needs at least two groups with at least two observations in each group.", call. = FALSE)
    # Internal IDs make comparison names unambiguous even when user headers contain hyphens.
    ids <- sprintf("g%03d", seq_along(normalized$groups))
    d$id <- factor(ids[match(d$group, normalized$groups)], levels = ids)
    model <- stats::aov(value ~ id, data = d)
    tab <- summary(model)[[1]]
    result$p <- tab$`Pr(>F)`[1]
    if (!is.finite(result$p)) stop("ANOVA is undefined for these data (check within-group variation).", call. = FALSE)
    tukey <- stats::TukeyHSD(model, "id")$id
    labels <- strsplit(rownames(tukey), "-", fixed = TRUE)
    result$comparisons <- data.frame(
      group1 = vapply(labels, function(x) normalized$groups[match(x[1], ids)], character(1)),
      group2 = vapply(labels, function(x) normalized$groups[match(x[2], ids)], character(1)),
      estimate = tukey[, "diff"], ci_low = tukey[, "lwr"], ci_high = tukey[, "upr"],
      p = tukey[, "p adj"], row.names = NULL)
    result$metrics <- rbind(add("Observations", nrow(d)), add("F statistic", fmt(tab$`F value`[1])),
                            add("Degrees of freedom", paste(tab$Df, collapse = ", ")),
                            add("P value (omnibus)", fmt(result$p)),
                            add("Multiple comparisons", "Tukey HSD; family-wise 95% confidence"))
    result$notes <- c(result$notes, "Ordinary one-way ANOVA assumes independent observations, normally distributed errors, and equal population variances.")
    return(result)
  }
  if (is.null(group2) || !group2 %in% normalized$groups || group1 == group2) stop("Select two different groups to compare.", call. = FALSE)
  b <- d[d$group == group2, , drop = FALSE]
  x <- a$value; y <- b$value
  if (method == "paired") {
    paired <- merge(a[c("row_id", "value")], b[c("row_id", "value")], by = "row_id", suffixes = c(".a", ".b"))
    x <- paired$value.a; y <- paired$value.b
    excluded <- normalized$rows - nrow(paired)
    result$notes <- c(result$notes, sprintf("Matched by table row: %d complete pairs; %d incomplete pair(s) excluded. Each row must identify the same subject in both columns.", nrow(paired), excluded))
  }
  if (length(x) < 2 || length(y) < 2) stop("This comparison needs at least two observations per group (or two complete pairs).", call. = FALSE)
  if (method %in% c("welch", "paired")) {
    test <- stats::t.test(x, y, paired = method == "paired", var.equal = FALSE, conf.level = 0.95)
    difference <- mean(x - if (method == "paired") y else mean(y))
    result$metrics <- rbind(add("Comparison", paste(group1, "−", group2)),
      add(if (method == "paired") "Complete pairs" else "Sample sizes", if (method == "paired") length(x) else paste(length(x), length(y), sep = ", ")),
      add("Mean difference", fmt(difference)), add("Difference 95% CI", paste(fmt(test$conf.int[1:2]), collapse = " to ")),
      add("t statistic", fmt(test$statistic)), add("Degrees of freedom", fmt(test$parameter)), add("P value (two-sided)", fmt(test$p.value)))
    result$comparisons <- data.frame(group1 = group1, group2 = group2, estimate = difference,
                                    ci_low = test$conf.int[1], ci_high = test$conf.int[2], p = test$p.value)
    result$notes <- c(result$notes, if (method == "paired") "Paired t test assumes independent pairs and normally distributed within-pair differences." else "Welch's t test assumes independent observations and does not assume equal population variances.")
  } else {
    test <- stats::wilcox.test(x, y, paired = FALSE, exact = FALSE, correct = TRUE)
    result$metrics <- rbind(add("Comparison", paste(group1, "vs", group2)), add("Sample sizes", paste(length(x), length(y), sep = ", ")),
                            add("W statistic", fmt(test$statistic)), add("P value (two-sided)", fmt(test$p.value)))
    result$comparisons <- data.frame(group1 = group1, group2 = group2, p = test$p.value)
    result$notes <- c(result$notes, "Asymptotic Wilcoxon rank-sum (Mann–Whitney) test with continuity correction; compares distributions and is not generally a test of medians alone.")
  }
  if (!is.finite(test$p.value)) stop("The test is undefined for these data.", call. = FALSE)
  result$p <- test$p.value
  result$n <- length(x) + length(y)
  result$notes <- c(result$notes, "One selected comparison; no correction for additional comparisons outside this analysis.")
  result
}

source("R/regression.R", local = TRUE)
source("R/statistics.R", local = TRUE)

source("R/multifit.R", local = TRUE)
