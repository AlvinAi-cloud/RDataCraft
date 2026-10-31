app <- source("app.R")$value
checks <- 0L
check <- function(ok, label) {if (!isTRUE(ok)) stop("FAIL: ", label, call. = FALSE); checks <<- checks + 1L; cat("PASS:", label, "\n")}
shiny::testServer(app, {
  # Explicit fixture: production startup is intentionally empty.
  raw(pc_example("column")$table);sheet_name("Treatment groups");project_name("Example study");document_open(TRUE)
  do.call(session$setInputs, pc_defaults()); session$flushReact()
  original <- raw()
  session$setInputs(rename_study = list(name = "  Drug response α  ", nonce = 1)); session$flushReact()
  check(project_name() == "Drug response α" && identical(raw(), original), "inline rename changes only study metadata")
  check(document_dirty(), "renaming marks the native document unsaved")
  for (name in c("", "  ", paste(rep("x", 101), collapse = ""), "Bad\nname")) {
    session$setInputs(rename_study = list(name = name, nonce = runif(1))); session$flushReact()
    check(project_name() == "Drug response α", "invalid title preserves the last accepted name")
  }
  file <- normalizePath("artifacts/tests", mustWork = TRUE)
  file <- file.path(file, "renamed-study.rdatacraft")
  pc_write_project(snapshot(), file)
  check(pc_load_project(file)$study_name == "Drug response α", "study title survives project serialization")
  session$setInputs(desktop_saved = list(path = file, nonce = 2)); session$flushReact()
  check(!document_dirty() && project_name() == "Drug response α", "Save clears dirty state without using the filename as the title")
  session$setInputs(rename_study = list(name = "Newer title", nonce = 3)); session$flushReact()
  session$setInputs(desktop_saved = list(path = file, nonce = 4)); session$flushReact()
  check(document_dirty() && project_name() == "Newer title", "a delayed save acknowledgement preserves newer title edits")
  session$setInputs(desktop_open_project = list(path = file, nonce = 5)); session$flushReact()
  check(project_name() == "Drug response α" && !document_dirty(), "reopen restores title metadata and clean state")
  check(pc_study_filename("Study / A: B") == "Study - A- B.rdcraft", "Save As title suggestion uses the new safe study filename")
  p <- snapshot(); p$study_name <- list("invalid")
  check(inherits(try(pc_decode_project(p), silent = TRUE), "try-error"), "malformed title metadata is rejected")
})
cat(checks, " study metadata checks passed.\n")
