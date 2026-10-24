# Preserve analysis and appearance references when headers change in place.
pc_rename_header_settings <- function(s, before, after) {
  if (ncol(before)!=ncol(after) || identical(names(before),names(after)) || setequal(names(before),names(after))) return(s)
  if (s$layout == "multiple") return(pc_pca_rename_settings(s,names(before),names(after)))
  if (!s$layout %in% c("column","xy")) return(s)
  old <- pc_table_series(before,s$layout); new <- pc_table_series(after,s$layout)
  if (length(old)!=length(new)) return(s)
  rename <- function(values) {i<-match(values,old);keep<-!is.na(i);values[keep]<-new[i[keep]];values}
  for(key in c("group1","group2")) s[[key]]<-rename(s[[key]])
  styles <- pc_series_styles(s$series_styles)
  if (length(styles)) {
    # Retired style keys must not collide with a newly named, active series.
    styles <- styles[intersect(old,names(styles))]
    names(styles)<-rename(names(styles))
    s$series_styles<-if(length(styles)) as.character(jsonlite::toJSON(styles,auto_unbox=TRUE)) else "{}"
  }
  s
}

# Structural edits are validated as a complete candidate and committed once.
pc_edit_rows <- function(tab, layout, action, first, count = 1L) {
  whole <- function(x) is.numeric(x) && length(x) == 1L && is.finite(x) && x == floor(x) && x >= 1
  if (!whole(first) || !whole(count) || !action %in% c("insert", "delete")) stop("Choose a valid row and positive whole row count.", call. = FALSE)
  if (action == "delete") {
    if (first + count - 1L > nrow(tab) || count >= nrow(tab)) stop("Keep at least one row; choose a range inside the table.", call. = FALSE)
    tab <- tab[-seq.int(first, length.out = count), , drop = FALSE]
  } else {
    if (first > nrow(tab) + 1L || nrow(tab) + count > 10000) stop("Insert within the table or after its last row, up to 10,000 rows.", call. = FALSE)
    added <- tab[rep(1L, count), , drop = FALSE]; added[,] <- NA_character_
    if (layout == "contingency") {
      added[, -1] <- "0"
      labels <- tab[[1]]
      for (i in seq_len(count)) {label <- paste("Category",length(labels)+1);while(label %in% labels) label <- paste0(label," new");added[i,1] <- label;labels <- c(labels,label)}
    }
    tail_rows <- if (first <= nrow(tab)) seq.int(first,nrow(tab)) else integer()
    tab <- rbind(tab[seq_len(first - 1L), , drop = FALSE], added, tab[tail_rows, , drop = FALSE])
  }
  rownames(tab) <- NULL
  pc_normalize(tab, layout, allow_empty = TRUE, allow_incomplete = layout == "survival")
  tab
}
pc_table_series <- function(tab, layout) {
  if (layout == "xy") return(pc_xy_structure(tab)$groups)
  if (layout == "column") return(names(tab))
  character()
}
pc_edit_series <- function(tab, layout, action, series, name = "") {
  groups <- pc_table_series(tab, layout)
  if (!length(groups) || !series %in% groups || !action %in% c("rename","delete","left","right")) stop("Choose a Column group or XY series.", call. = FALSE)
  columns <- if (layout == "xy") split(seq.int(2L,ncol(tab)),factor(pc_xy_structure(tab)$series,levels=groups)) else setNames(as.list(seq_len(ncol(tab))),groups)
  i <- match(series, groups)
  if (action == "rename") {
    name <- trimws(name)
    if (length(name) != 1L || is.na(name) || !nzchar(name) || nchar(name) > 100 || grepl("[[:cntrl:]]| \\[rep [0-9]+\\]$",name) || (name != series && name %in% groups)) stop("Enter a unique series name of 1–100 characters.", call. = FALSE)
    ids <- columns[[series]]
    names(tab)[ids] <- if (length(ids) == 1L) name else paste0(name," [rep ",seq_along(ids),"]")
  } else if (action == "delete") {
    if (length(groups) == 1L) stop("Keep at least one data series.", call. = FALSE)
    tab <- tab[, -columns[[series]], drop = FALSE]
  } else {
    target <- i + if (action == "left") -1L else 1L
    if (target < 1L || target > length(groups)) stop("The series is already at that edge.", call. = FALSE)
    order <- seq_along(groups); order[c(i,target)] <- order[c(target,i)]
    tab <- tab[, c(if(layout == "xy") 1L,unlist(columns[order],use.names=FALSE)), drop = FALSE]
  }
  pc_normalize(tab, layout, allow_empty = TRUE)
  tab
}

# Header edits change labels only; XY shared headers rename a complete replicate block.
pc_rename_header <- function(tab, layout, column, name) {
  if (!is.numeric(column) || length(column)!=1L || !is.finite(column) || column!=floor(column) || column<1 || column>ncol(tab)) stop("Choose a current column header.",call.=FALSE)
  if (!is.character(name) || length(name)!=1L || is.na(name) || !nzchar(trimws(name)) || nchar(trimws(name))>100 || grepl("[[:cntrl:]]",name)) stop("Enter a unique column name of 1–100 characters, without line breaks.",call.=FALSE)
  name <- trimws(name)
  if(layout=="xy" && column>1) return(pc_edit_series(tab,layout,"rename",pc_xy_structure(tab)$series[column-1],name))
  names(tab)[column] <- name
  tab <- pc_check_table(tab)
  pc_normalize(tab,layout,allow_empty=TRUE,allow_incomplete=TRUE)
  tab
}
