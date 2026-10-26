# RDataCraft data validation. Blank cells are missing; text and nonfinite values are errors.
pc_read_text <- function(text, delimiter = "auto") {
  if (!is.character(text) || length(text) != 1L || nchar(text) > 5e6) {
    stop("Paste a CSV or tab-separated table smaller than 5 MB.", call. = FALSE)
  }
  text <- gsub("\r\n?", "\n", text)
  text <- sub("\n+$", "", text)
  if (!nzchar(trimws(text))) stop("Add a table with column headers and numeric data.", call. = FALSE)
  if (delimiter == "auto") delimiter <- if (grepl("\t", strsplit(text, "\n", fixed = TRUE)[[1]][1], fixed = TRUE)) "\t" else ","
  connection <- textConnection(text)
  on.exit(close(connection), add = TRUE)
  fields <- utils::count.fields(connection, sep = delimiter, quote = '"', comment.char = "", blank.lines.skip = FALSE)
  complete <- fields[!is.na(fields)]
  if (length(complete) < 2L || any(complete != complete[1])) {
    stop("Each row must have the same number of cells as the header. Keep delimiters for blank cells.", call. = FALSE)
  }
  tab <- tryCatch(utils::read.table(text = text, header = TRUE, sep = delimiter,
                    colClasses = "character", check.names = FALSE, fill = FALSE,
                    quote = '"', comment.char = "", blank.lines.skip = FALSE,
                    na.strings = "", strip.white = TRUE, row.names = NULL),
                  error = function(e) stop("Could not read the table: ", conditionMessage(e), call. = FALSE))
  pc_check_table(tab)
}

pc_check_table <- function(tab) {
  if (!is.data.frame(tab) || nrow(tab) < 1 || ncol(tab) < 1) stop("The table needs at least one data row and column.", call. = FALSE)
  if (nrow(tab) > 10000 || ncol(tab) > 50) stop("This preview supports up to 10,000 rows and 50 columns.", call. = FALSE)
  if (anyNA(names(tab)) || any(!nzchar(trimws(names(tab)))) || anyDuplicated(names(tab))) {
    stop("Every column needs a unique, nonempty header.", call. = FALSE)
  }
  tab[] <- lapply(tab, function(x) { x <- as.character(x); x[is.na(x) | trimws(x) == ""] <- NA_character_; x })
  tab
}

pc_table_text <- function(tab) {
  tab <- pc_check_table(tab)
  lines <- capture.output(utils::write.table(tab, sep = "\t", row.names = FALSE,
                                            col.names = TRUE, na = "", quote = TRUE))
  paste(lines, collapse = "\n")
}

# Clipboard blocks have no implicit header. Parse TSV without converting numbers,
# dropping blank rows, or treating a comma in a label as a separator.
pc_clipboard_cells <- function(text) {
  if (!is.character(text) || length(text) != 1L || is.na(text) || nchar(text, type = "bytes") > 5e6)
    stop("Paste a cell block smaller than 5 MB.", call. = FALSE)
  text <- gsub("\r\n?", "\n", text)
  # A spreadsheet terminates its last record with a newline; remove only that
  # terminator, preserving deliberately copied empty rows and trailing cells.
  text <- sub("\n$", "", text)
  if (!nzchar(text)) return(matrix(NA_character_, 1L, 1L))
  con <- textConnection(text); on.exit(close(con))
  fields <- utils::count.fields(con, sep = "\t", quote = '"', comment.char = "", blank.lines.skip = FALSE)
  complete <- fields[!is.na(fields)]
  complete[complete == 0L] <- 1L
  if (!length(complete) || any(complete != complete[1]))
    stop("Paste a rectangular block: every row must contain the same number of cells.", call. = FALSE)
  if (length(complete) > 10001 || complete[1] > 50)
    stop("The table supports up to 10,000 data rows and 50 columns.", call. = FALSE)
  if (all(fields == 0L)) return(matrix(NA_character_, length(fields), 1L))
  cells <- tryCatch(utils::read.table(text = text, header = FALSE, sep = "\t",
    col.names = paste0("V", seq_len(complete[1])), colClasses = "character", fill = FALSE,
    quote = '"', comment.char = "", blank.lines.skip = FALSE, na.strings = "", strip.white = FALSE),
    error = function(e) stop("Could not read the copied cells: ", conditionMessage(e), call. = FALSE))
  as.matrix(cells)
}

pc_paste_cells <- function(tab, text, row, column, layout, headers = FALSE) {
  tab <- pc_check_table(tab)
  if (length(row) != 1L || length(column) != 1L || !is.numeric(row) || !is.numeric(column) ||
      !is.finite(row) || !is.finite(column) || row != floor(row) || column != floor(column) ||
      row < 1 || column < 1 || row > nrow(tab) || column > ncol(tab))
    stop("Select a starting cell in the current table, then paste.", call. = FALSE)
  cells <- pc_clipboard_cells(text)
  labels <- NULL
  if (isTRUE(headers)) {
    if (nrow(cells) < 2) stop("Include at least one data row after the column names.", call. = FALSE)
    labels <- trimws(cells[1, ]); cells <- cells[-1, , drop = FALSE]
    if (anyNA(labels) || any(!nzchar(labels)) || anyDuplicated(labels))
      stop("Pasted column names must be unique and nonempty.", call. = FALSE)
  }
  last_row <- row + nrow(cells) - 1L; last_column <- column + ncol(cells) - 1L
  xy <- if (layout == "xy") pc_xy_structure(tab) else NULL
  if (!is.null(xy) && xy$n > 1L && last_column > ncol(tab))
    last_column <- 1L + ceiling((last_column - 1L) / xy$n) * xy$n
  if (last_row > 10000 || last_column > 50)
    stop("The paste would exceed 10,000 rows or 50 columns.", call. = FALSE)
  if (layout == "survival" && last_column > 3)
    stop("Survival tables use exactly three columns: Time, Status, and Group.", call. = FALSE)
  # New count cells are explicit zeros; new category labels stay unique. Other
  # formats retain missing cells rather than inventing scientific observations.
  if (last_row > nrow(tab)) {
    old_rows <- nrow(tab); tab[seq.int(old_rows + 1L, last_row), ] <- NA_character_
    if (layout == "contingency") for (i in seq.int(old_rows + 1L, last_row)) {
      label <- paste("Category", i)
      while (label %in% tab[[1]]) label <- paste0(label, " new")
      tab[i, 1] <- label; tab[i, -1] <- "0"
    }
  }
  if (last_column > ncol(tab)) for (i in seq.int(ncol(tab) + 1L, last_column)) {
    label <- paste("Column", i)
    if (!is.null(xy) && xy$n > 1L) {
      group <- paste("Series", ceiling((i - 1L) / xy$n))
      while (group %in% xy$groups) group <- paste0(group, " new")
      label <- paste0(group, " [rep ", ((i - 2L) %% xy$n) + 1L, "]")
    }
    while (label %in% names(tab) || label %in% labels) label <- paste0(label, " new")
    tab[[label]] <- if (layout == "contingency") "0" else NA_character_
  }
  cols <- seq.int(column, column + ncol(cells) - 1L)
  if (!is.null(labels)) names(tab)[cols] <- labels
  tab[seq.int(row, last_row), cols] <- cells
  tab <- pc_check_table(tab)
  pc_normalize(tab, layout, allow_empty = TRUE, allow_incomplete = identical(layout, "survival"))
  tab
}

pc_numeric <- function(x, column) {
  value <- suppressWarnings(as.numeric(x))
  bad <- !is.na(x) & (is.na(value) | !is.finite(value))
  if (any(bad)) stop(sprintf("Column '%s', row %d: enter a finite number or leave the cell blank.", column, which(bad)[1]), call. = FALSE)
  value
}

# Explicit, portable replicate headers keep the series grouping in CSV/TSV and
# project files: X, Control [rep 1], Control [rep 2], Drug [rep 1], Drug [rep 2].
pc_xy_structure <- function(tab) {
  if (ncol(tab) < 2) stop("An XY table needs X followed by at least one Y series.", call. = FALSE)
  labels <- names(tab)[-1]
  marked <- grepl("(?s)^.+ \\[rep [1-9][0-9]*\\]$", labels,perl=TRUE)
  if (!any(marked)) return(list(groups = labels, series = labels, replicate = rep(1L, length(labels)), n = 1L))
  if (!all(marked)) stop("Use Series [rep 1], Series [rep 2], etc. for every Y column in a replicate table. Use Y replicates… to set up the columns.", call. = FALSE)
  groups <- sub(" \\[rep [1-9][0-9]*\\]$", "", labels)
  index <- as.integer(sub("(?s)^.* \\[rep ([1-9][0-9]*)\\]$", "\\1", labels,perl=TRUE))
  runs <- rle(groups)
  if (anyDuplicated(runs$values) || length(unique(runs$lengths)) != 1L ||
      !identical(index, rep(seq_len(runs$lengths[1]), length(runs$values))))
    stop("Each Y series needs the same number of adjacent replicate columns, numbered from 1.", call. = FALSE)
  list(groups = runs$values, series = groups, replicate = index, n = runs$lengths[1])
}

pc_xy_replicates <- function(tab, n) {
  tab <- pc_check_table(tab); spec <- pc_xy_structure(tab)
  if (!is.numeric(n) || length(n) != 1L || !is.finite(n) || n != floor(n) || n < 1 || n > 49)
    stop("Choose a whole number of Y replicates from 1 to 49.", call. = FALSE)
  if (length(spec$groups) * n + 1 > 50) stop("This many series and replicates would exceed 50 total columns. Choose fewer replicates or series.", call. = FALSE)
  out <- tab[1]
  for (g in spec$groups) {
    columns <- which(spec$series == g) + 1L
    if (n < length(columns) && any(!is.na(tab[, columns[seq.int(n + 1L, length(columns))], drop = FALSE])))
      stop("Some replicate columns being removed contain observations. Clear those cells or keep more replicates.", call. = FALSE)
    for (j in seq_len(n)) {
      label <- if (n == 1) g else paste0(g, " [rep ", j, "]")
      out[[ncol(out) + 1L]] <- if (j <= length(columns)) tab[[columns[j]]] else rep(NA_character_, nrow(tab))
      names(out)[ncol(out)] <- label
    }
  }
  out <- pc_check_table(out); pc_normalize(out, "xy", allow_empty = TRUE); out
}

pc_normalize <- function(tab, layout = "column", allow_empty = FALSE, allow_incomplete = FALSE) {
  tab <- pc_check_table(tab)
  if (layout == "multiple") return(pc_normalize_multiple(tab,allow_empty))
  if (layout %in% c("grouped", "contingency", "survival")) return(pc_normalize_special(tab, layout, allow_empty, allow_incomplete))
  if (!layout %in% c("column", "xy")) stop("Unknown table layout.", call. = FALSE)
  if (layout == "xy" && ncol(tab) < 2) stop("An XY table needs an X column followed by at least one Y column.", call. = FALSE)
  columns <- if (layout == "xy") seq.int(2L, ncol(tab)) else seq_len(ncol(tab))
  xy <- if (layout == "xy") pc_xy_structure(tab) else NULL
  values <- lapply(seq_len(ncol(tab)), function(i) pc_numeric(tab[[i]], names(tab)[i]))
  parts <- lapply(columns, function(i) data.frame(group = if (layout == "xy") xy$series[i - 1L] else names(tab)[i], value = values[[i]],
                                                row_id = seq_len(nrow(tab)),
                                                replicate = if (layout == "xy") xy$replicate[i - 1L] else 1L,
                                                x = if (layout == "xy") values[[1]] else NA_real_))
  data <- do.call(rbind, parts)
  if (layout == "xy" && any(is.na(data$x) & !is.na(data$value))) {
    stop("Each populated Y cell must have an X value on the same row.", call. = FALSE)
  }
  missing <- sum(is.na(data$value))
  data <- data[!is.na(data$value), , drop = FALSE]
  if (!nrow(data) && !allow_empty) stop("The table has no numeric observations.", call. = FALSE)
  groups <- if (layout == "xy") xy$groups else names(tab)[columns]
  data$group <- factor(data$group, levels = groups)
  list(data = data, groups = groups, missing = missing, layout = layout,
       rows = nrow(tab), x_label = if (layout == "xy") names(tab)[1] else "Group",
       replicates = if (layout == "xy") xy$n else 1L)
}

pc_import_file <- function(path, name = basename(path)) {
  if (length(path) != 1L || !file.exists(path) || is.na(file.info(path)$size) || file.info(path)$size > 6e6) stop("Choose a data file smaller than 6 MB.", call. = FALSE)
  ext <- tolower(tools::file_ext(name))
  tab <- if (ext == "xlsx") as.data.frame(readxl::read_excel(path, .name_repair = "minimal", col_types = "text"))
    else if (ext %in% c("csv", "tsv", "txt")) pc_read_text(paste(readLines(path, warn = FALSE), collapse = "\n"), if (ext == "csv") "," else "auto")
    else stop("Choose a CSV, TSV, text, or XLSX file.", call. = FALSE)
  pc_check_table(tab)
}

pc_summary <- function(normalized) {
  if (normalized$layout == "contingency") return(data.frame(category = rownames(normalized$counts), normalized$counts, total = rowSums(normalized$counts), check.names = FALSE))
  if (normalized$layout == "survival") return(do.call(rbind, lapply(normalized$groups, function(g) {d <- normalized$data[normalized$data$group == g, ]; data.frame(group = g, n = nrow(d), events = sum(d$status), censored = sum(d$status == 0), median_followup = if(nrow(d)) median(d$x) else NA_real_)})))
  rows <- lapply(normalized$groups, function(group) {
    x <- normalized$data$value[normalized$data$group == group]
    n <- length(x)
    avg <- if (n) mean(x) else NA_real_
    sd <- if (n > 1) stats::sd(x) else NA_real_
    sem <- sd / sqrt(n)
    margin <- if (n > 1) stats::qt(0.975, n - 1) * sem else NA_real_
    data.frame(group = group, n = n, mean = avg, sd = sd, sem = sem,
               median = if (n) stats::median(x) else NA_real_,
               ci_low = avg - margin, ci_high = avg + margin)
  })
  do.call(rbind, rows)
}

pc_normalize_special <- function(tab, layout, allow_empty = FALSE, allow_incomplete = FALSE) {
  rows <- nrow(tab)
  if (layout == "grouped") {
    if (ncol(tab) < 3) stop("Grouped tables need two factor columns followed by numeric replicates.", call. = FALSE)
    populated <- rowSums(!is.na(tab[, -(1:2), drop = FALSE])) > 0
    if (any(populated & (is.na(tab[[1]]) | is.na(tab[[2]])))) stop("Every populated row needs both factor labels.", call. = FALSE)
    parts <- lapply(3:ncol(tab), function(i) data.frame(condition = tab[[1]], group = tab[[2]], value = pc_numeric(tab[[i]], names(tab)[i]), row_id = seq_len(rows), replicate = names(tab)[i], x = NA_real_))
    d <- do.call(rbind, parts); missing <- sum(is.na(d$value)); d <- d[!is.na(d$value), , drop = FALSE]
    groups <- unique(stats::na.omit(tab[[2]])); conditions <- unique(stats::na.omit(tab[[1]]))
    d$group <- factor(d$group, levels = groups); d$condition <- factor(d$condition, levels = conditions)
    if (!nrow(d) && !allow_empty) stop("Enter numeric replicates.", call. = FALSE)
    return(list(data = d, groups = groups, conditions = conditions, missing = missing, layout = layout, rows = rows, factor_names = names(tab)[1:2]))
  }
  if (layout == "contingency") {
    if (ncol(tab) < 3 || nrow(tab) < 2) stop("Contingency tables need two or more rows and two or more count columns, after the category column.", call. = FALSE)
    if (anyNA(tab[[1]]) || anyDuplicated(tab[[1]])) stop("Category labels must be unique and nonempty.", call. = FALSE)
    counts <- do.call(cbind, lapply(2:ncol(tab), function(i) pc_numeric(tab[[i]], names(tab)[i])))
    if (anyNA(counts) || any(counts < 0 | counts != floor(counts))) stop("Counts must be nonnegative integers; use 0 rather than blank for an observed zero.", call. = FALSE)
    if (any(counts > 1e9)) stop("Counts are limited to one billion per cell.", call. = FALSE)
    dimnames(counts) <- list(tab[[1]], names(tab)[-1])
    d <- data.frame(category = rep(rownames(counts), times = ncol(counts)), group = factor(rep(colnames(counts), each = nrow(counts)), levels = colnames(counts)), value = as.vector(counts), row_id = rep(seq_len(rows), ncol(counts)), x = NA_real_)
    return(list(data = d, groups = colnames(counts), counts = counts, missing = 0L, layout = layout, rows = rows))
  }
  if (ncol(tab) != 3) stop("Survival tables require exactly Time, Status, and Group columns, in that order.", call. = FALSE)
  populated <- rowSums(!is.na(tab)) > 0
  if (!allow_incomplete && any(populated & !stats::complete.cases(tab))) stop("Every survival subject needs time, status, and a group; use status 0 for censoring.", call. = FALSE)
  time <- pc_numeric(tab[[1]], names(tab)[1]); status <- pc_numeric(tab[[2]], names(tab)[2])
  if (any(time < 0, na.rm = TRUE) || any(!is.na(status) & !status %in% c(0, 1))) stop("Survival time must be nonnegative and status must be 0 (censored) or 1 (event).", call. = FALSE)
  if (allow_incomplete) populated <- stats::complete.cases(tab)
  d <- data.frame(x = time[populated], status = status[populated], group = tab[[3]][populated], value = time[populated], row_id = which(populated))
  groups <- unique(d$group); d$group <- factor(d$group, levels = groups)
  if (!nrow(d) && !allow_empty) stop("Enter at least one complete survival subject.", call. = FALSE)
  list(data = d, groups = groups, missing = 0L, layout = layout, rows = rows)
}

source("R/workflows.R", local = TRUE)

source("R/table_edit.R", local = TRUE)

source("R/pca.R",local=TRUE)
