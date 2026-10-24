# Table contracts and scientific workflow templates. Replicates remain explicit.
pc_layouts <- function() c("Column · groups / matched subjects" = "column", "XY · X and Y series" = "xy",
  "Grouped · two factors + replicates" = "grouped", "Contingency · category counts" = "contingency",
  "Survival · time, status, group" = "survival", "Multiple variables · PCA" = "multiple")
pc_graphs <- function(layout) switch(layout,
  multiple = c("Variable distributions"="variables", "PCA scores"="pcascores","PCA loadings"="pcaloadings","PCA scree / explained variance"="pcascree"),
  column = c("Individual points + mean" = "points", "Bars + observations" = "bar", "Box plot" = "box", "Violin plot" = "violin", "Paired observations" = "paired", "Histogram" = "histogram", "Cumulative distribution" = "ecdf", "Normal Q–Q plot" = "qq", "Mean + error bars" = "mean", "Median + interquartile range" = "median", "Violin + box plot" = "violinbox", "Density distribution" = "density"),
  xy = c("Scatter plot" = "scatter", "Connected points" = "line", "Mean + error bars at each X" = "xymean", "Mean + shaded SD / SEM band" = "xyband", "Regression residuals" = "residual", "Step plot" = "step", "Area under mean response" = "area"),
  grouped = c("Grouped bars + observations" = "groupbar", "Grouped individual points" = "grouppoints", "Interaction plot" = "interaction", "Grouped box plots" = "groupbox", "Grouped violin plots" = "groupviolin", "Mean response heatmap" = "groupheat"),
  contingency = c("Count bars" = "counts", "100% stacked proportions" = "proportions", "Count heatmap" = "heatmap", "Stacked count bars" = "stacked"),
  survival = c("Kaplan–Meier + 95% CI" = "km", "Kaplan–Meier curves" = "kmplain"))
pc_layout_help <- function(layout) switch(layout,
  multiple = "Rows are observations and numeric columns are variables. Text columns can supply sample labels or groups. In Analysis → PCA settings, select numeric variables and explicitly exclude numeric sample IDs/group codes. PCA mean-centers variables; SD scaling is on by default. Missing rows require an explicit exclusion choice.",
  column = "One numeric column per group. Rows identify matched subjects for paired / repeated-measures analyses. Blank cells remain missing.",
  xy = "First column = numeric X. Y series can have side-by-side replicate subcolumns (Y replicates…). Blank cells remain missing. Mean/error plots summarize each series at each X; fits use individual observations and assume independent replicates.",
  grouped = "First two columns = factor labels (e.g. Time, Treatment). Remaining columns = numeric independent replicates. Repeated factor combinations are combined. This layout currently supports ordinary, independent two-way ANOVA, not repeated measures.",
  contingency = "First column = unique category labels. Remaining columns = nonnegative integer counts, one population per column. All count cells are required; enter 0 for an observed zero.",
  survival = "Exactly three columns: Time (nonnegative), Status (1 = event, 0 = right-censored), Group (label). One complete row per subject. Do not enter aggregated counts.")
pc_example <- function(layout) {
  switch(layout,
    multiple = list(table=data.frame(Sample=sprintf("S%02d",1:12),Group=rep(c("Control","Treatment A","Treatment B"),each=4),Signal=c(8,10,9,11,16,19,18,20,25,27,29,26),Size=c(12,15,11,13,18,17,20,19,24,28,25,27),Marker=c(4,5,6,4,8,9,7,10,12,14,11,13),Response=c(32,30,33,31,24,27,23,26,18,15,17,19)),title="Principal component analysis",x_label="PC1",y_label="PC2",method="pca"),
    column = list(table = pc_read_text(paste(readLines("examples/treatment.csv"), collapse = "\n")), title = "Treatment response", x_label = "Condition", y_label = "Response (a.u.)", method = "welch"),
    xy = list(table = pc_read_text(paste(readLines("examples/xy.csv"), collapse = "\n")), title = "Response over time", x_label = "Time (hours)", y_label = "Response (a.u.)", method = "linear"),
    grouped = list(table = data.frame(Time = rep(c("Day 1", "Day 2", "Day 3"), each = 2), Treatment = rep(c("Control", "Drug"), 3), Replicate1 = c(9, 12, 11, 18, 12, 24), Replicate2 = c(10, 14, 12, 20, 14, 27), Replicate3 = c(12, 13, 10, 19, 13, 25)), title = "Treatment by time", x_label = "Time", y_label = "Response", method = "twoway"),
    contingency = list(table = data.frame(Outcome = c("Response", "No response"), Control = c(12, 28), Drug = c(25, 15)), title = "Treatment outcomes", x_label = "Population", y_label = "Count", method = "fisher"),
    survival = list(table = data.frame(Time = c(2, 4, 5, 7, 8, 10, 12, 14, 3, 6, 9, 11, 13, 15, 16, 18), Status = c(1, 1, 0, 1, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0), Group = rep(c("Control", "Drug"), each = 8)), title = "Time-to-event analysis", x_label = "Time", y_label = "Survival probability", method = "logrank"))
}
pc_blank <- function(layout) {
  e <- pc_example(layout); tab <- e$table
  if (layout == "multiple") tab[,3:ncol(tab)] <- NA_character_
  else if (layout %in% c("column", "xy")) {tab <- tab[seq_len(6), , drop = FALSE]; tab[,] <- NA_character_}
  else if (layout == "grouped") tab[, 3:ncol(tab)] <- NA_character_
  else if (layout == "contingency") tab[, 2:ncol(tab)] <- 0
  else tab <- data.frame(Time = NA_character_, Status = NA_character_, Group = NA_character_)
  pc_check_table(tab)
}
pc_transform <- function(tab, layout, operation, reference = NULL) {
  if (!layout %in% c("column", "xy", "grouped")) stop("Transforms apply to numeric column, XY, or grouped observations.", call. = FALSE)
  tab <- pc_check_table(tab)
  cols <- switch(layout, column = seq_len(ncol(tab)), xy = seq.int(2, ncol(tab)), grouped = seq.int(3, ncol(tab)))
  values <- lapply(cols, function(i) pc_numeric(tab[[i]], names(tab)[i]))
  if (operation == "percent_control") {
    if (layout != "column" || is.null(reference) || !reference %in% names(tab)) stop("Choose a control column for percent-of-control normalization.", call. = FALSE)
    base <- mean(pc_numeric(tab[[reference]], reference), na.rm = TRUE)
    if (!is.finite(base) || base == 0) stop("The control needs a finite nonzero mean.", call. = FALSE)
  }
  for (j in seq_along(cols)) {
    x <- values[[j]]
    if (operation %in% c("log10", "ln") && any(x <= 0, na.rm = TRUE)) stop("Log transforms require all nonmissing values to be positive.", call. = FALSE)
    if (operation == "zscore" && (!is.finite(stats::sd(x, na.rm = TRUE)) || stats::sd(x, na.rm = TRUE) == 0)) stop("Z scores need at least two values with nonzero SD in every numeric column.", call. = FALSE)
    tab[[cols[j]]] <- switch(operation, log10 = log10(x), ln = log(x), percent_control = 100 * x / base,
      zscore = (x - mean(x, na.rm = TRUE)) / stats::sd(x, na.rm = TRUE), stop("Unknown transform."))
  }
  pc_check_table(tab)
}
