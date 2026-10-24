source("R/data.R")
source("R/analysis.R")
source("R/plot.R")
source("R/project.R")
checks <- 0L
check <- function(condition, label) {
  if (!isTRUE(condition)) stop("FAIL: ", label, call. = FALSE)
  checks <<- checks + 1L
  cat("PASS:", label, "\n")
}
near <- function(x, y, tolerance = 1e-10) isTRUE(all.equal(as.numeric(x), as.numeric(y), tolerance = tolerance))
errors <- function(expr) inherits(tryCatch(force(expr), error = identity), "error")

# Fixed benchmark: the paired Student sleep dataset, documented in base R.
sleep <- datasets::sleep
sleep_table <- data.frame(First = sleep$extra[sleep$group == 1], Second = sleep$extra[sleep$group == 2])
n <- pc_normalize(sleep_table)
paired <- pc_analyze(n, "paired", "First", "Second")
check(near(paired$p, 0.00283289019738427), "paired sleep benchmark P value")
check(near(paired$comparisons$estimate, -1.58), "paired mean difference and direction")
check(near(paired$comparisons$ci_low, -2.4598857633, 1e-8), "paired benchmark confidence interval")
welch <- pc_analyze(n, "welch", "First", "Second")
check(near(welch$p, 0.07939414, 1e-7), "unpaired sleep benchmark P value")

# Missing values must match original row identity, rather than independently compact columns.
with_missing <- data.frame(A = c(2, NA, 7, 10, 13), B = c(1, 5, NA, 8, 9))
paired_missing <- pc_analyze(pc_normalize(with_missing), "paired", "A", "B")
check(near(paired_missing$comparisons$estimate, 7 / 3), "paired missing cells retain row matching")
check(any(grepl("3 complete pairs; 2 incomplete", paired_missing$notes)), "incomplete pairs reported explicitly")
check(errors(pc_normalize(data.frame(A = c("1", "typo")))), "nonnumeric cells rejected")
check(errors(pc_normalize(data.frame(A = c(1, Inf)))), "infinite values rejected")
check(errors(pc_read_text("A,A\n1,2")), "duplicate column headers rejected")
check(errors(pc_read_text("A,B\n1,2,3")), "extra cells cannot silently become row names")
check(errors(pc_normalize(data.frame(X = c(1, NA), Y = c(2, 3)), "xy")), "Y values without X rejected")
check(errors(pc_analyze(n, "welch", "First", "First")), "comparing a group to itself rejected")
check(errors(pc_analyze(pc_normalize(data.frame(A = 1, B = 2)), "welch", "A", "B")), "insufficient sample sizes rejected")
mann <- pc_analyze(pc_normalize(data.frame(A = 1:5, B = 6:10)), "mann", "A", "B")
check(near(mann$p, 0.01218578, 1e-7), "Mann–Whitney asymptotic benchmark with continuity correction")

# Published base R PlantGrowth example: F = 4.8461 and P ≈ 0.01591.
pg <- datasets::PlantGrowth
wide <- as.data.frame(split(pg$weight, pg$group))
anova_result <- pc_analyze(pc_normalize(wide), "anova", "ctrl", "trt1")
check(near(anova_result$p, 0.0159099583256229), "PlantGrowth ANOVA benchmark P value")
check(nrow(anova_result$comparisons) == 3L, "Tukey reports the three-comparison family")
check(near(anova_result$comparisons$p[3], 0.01200642, 1e-6), "PlantGrowth Tukey adjusted P value")
names(wide) <- c("Control-A", "Drug-B", "Drug-C")
check(all(pc_analyze(pc_normalize(wide), "anova", "Control-A", "Drug-B")$comparisons$group1 %in% names(wide)), "hyphenated group labels stay intact")

xy <- pc_normalize(data.frame(X = 1:6, Y = c(2, 4, 5, 8, 9, 13)), "xy")
linear <- pc_analyze(xy, "linear", "Y")
check(near(stats::coef(linear$model)["x"], 2.08571428571429), "linear regression fixed slope benchmark")
check(errors(pc_analyze(xy, "paired", "Y", "Y")), "incompatible layout and analysis rejected")

# Durable project round-trip and strict schema validation.
dir.create("artifacts/tests", recursive = TRUE, showWarnings = FALSE)
s <- pc_defaults()
raw <- pc_check_table(read.csv("examples/treatment.csv", check.names = FALSE))
jsonlite::write_json(pc_project(raw, s), "artifacts/tests/project.json", pretty = TRUE, auto_unbox = TRUE, na = "null")
loaded <- pc_load_project("artifacts/tests/project.json")
check(identical(raw, loaded$table), "project data round-trip preserves values and headers")
check(isTRUE(all.equal(s, loaded$settings)), "project settings round-trip")
broken <- pc_project(raw, s); broken$settings$width <- 100000
jsonlite::write_json(broken, "artifacts/tests/broken.json", auto_unbox = TRUE)
check(errors(pc_load_project("artifacts/tests/broken.json")), "unsafe project export dimensions rejected")
blank <- data.frame(Control = rep(NA_character_, 6), Treatment = rep(NA_character_, 6))
blank_settings <- pc_defaults(); blank_settings$method <- "descriptive"; blank_settings$group2 <- "Treatment"
jsonlite::write_json(pc_project(blank, blank_settings), "artifacts/tests/blank.rdatacraft", auto_unbox = TRUE, na = "null")
blank_loaded <- pc_load_project("artifacts/tests/blank.rdatacraft")
check(nrow(blank_loaded$table) == 6 && all(is.na(blank_loaded$table)), "blank desktop projects save and reopen without invented values")
check(nrow(pc_normalize(blank, allow_empty = TRUE)$data) == 0, "blank tables retain zero observations")
check(errors(pc_plot(pc_normalize(blank, allow_empty = TRUE), blank_settings)), "empty figures request observations")
check(identical(pc_signature(raw, s), pc_signature(loaded$table, loaded$settings)), "saved-state signatures survive JSON round trips")
check(identical(pc_project_name("/tmp/study.rdatacraft.json"), "study") && identical(pc_project_name("/tmp/study.rdatacraft"), "study"), "native and legacy project names are supported")

# Exercise every graph family and actual export devices, including annotations.
grouped <- pc_normalize(raw)
a <- pc_analyze(grouped, "anova", "Control", "Treatment A")
for (graph in c("points", "bar", "box", "violin", "paired")) {
  s$graph <- graph
  file <- paste0("artifacts/tests/", graph, ".svg")
  ggplot2::ggsave(file, pc_plot(grouped, s, a), width = 160, height = 120, units = "mm")
  check(file.info(file)$size > 1000, paste(graph, "graph exports as SVG"))
}
s <- pc_defaults(); s$layout <- "xy"; s$graph <- "scatter"; s$method <- "linear"; s$group1 <- "Y"
ggplot2::ggsave("artifacts/tests/linear.pdf", pc_plot(xy, s, linear), device = grDevices::pdf, width = 6, height = 4)
check(file.info("artifacts/tests/linear.pdf")$size > 1000, "regression and confidence band export as PDF")
s <- pc_defaults(); s$log_y <- TRUE
check(errors(pc_plot(pc_normalize(data.frame(A = c(0, 1, 2))), s)), "log axis does not silently discard zero values")
ggplot2::ggsave("artifacts/tests/figure.png", pc_plot(grouped, pc_defaults(), a), device = pc_png_device, width = 160, height = 120, units = "mm", dpi = 150)
check(file.info("artifacts/tests/figure.png")$size > 1000, "raster export succeeds")
s <- pc_defaults(); s$y_label <- "Response (μM)"; s$title <- "β response"
ggplot2::ggsave("artifacts/tests/unicode.pdf", pc_plot(grouped, s, a), device = pc_pdf_device, width = 6, height = 4)
check(file.info("artifacts/tests/unicode.pdf")$size > 1000, "PDF export supports scientific Unicode labels")
cat("\n", checks, " checks passed.\n", sep = "")
