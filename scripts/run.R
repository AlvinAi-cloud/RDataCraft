args <- commandArgs(trailingOnly = TRUE)
root <- normalizePath(getwd())
.libPaths(c(file.path(Sys.getenv("RDATACRAFT_RUNTIME",file.path(root,"runtime")), "library"), .libPaths()))
required <- c("shiny", "bslib", "ggplot2", "DT", "readxl", "jsonlite", "svglite", "survival", "xml2")
missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) stop("Missing dependencies: ", paste(missing, collapse = ", "), ". Run scripts/install.R first.")
port_arg <- grep("^--port=", args, value = TRUE)
port <- as.integer(if (length(port_arg)) sub("^--port=", "", port_arg[1]) else Sys.getenv("RDATACRAFT_PORT", "8743"))
if (is.na(port) || port < 1024 || port > 65535) stop("Choose a port between 1024 and 65535.")
# Graph measurement may request a default device outside a Shiny render.
# Keep that scratch device in memory instead of writing Rplots.pdf into the app.
options(device = function(...) grDevices::pdf(file = NULL, ...),
        shiny.autoreload = FALSE, shiny.sanitize.errors = TRUE)
if (Sys.getenv("RDATACRAFT_DESKTOP") == "1") {
  parent <- suppressWarnings(as.integer(Sys.getenv("RDATACRAFT_PARENT_PID")))
  if (!is.na(parent) && parent > 1L) {
    watch_parent <- function() {
      # Windows pskill always calls TerminateProcess, even with signal=0.
      # Query process state through ps instead of sending any Windows signal.
      alive <- tryCatch(if (.Platform$OS.type == "windows") {
        ps::ps_is_running(ps::ps_handle(parent))
      } else tools::pskill(parent, signal = 0L), error = function(e) FALSE)
      if (!isTRUE(alive)) quit(save = "no", status = 0L)
      later::later(watch_parent, 2)
    }
    later::later(watch_parent, 2)
  }
}
cat("\n  RDataCraft 0.3\n  Open http://127.0.0.1:", port,
    "\n  Keep this window open. Press Control+C to stop.\n\n", sep = "")
shiny::runApp(root, host = "127.0.0.1", port = port,
              launch.browser = !"--no-browser" %in% args, display.mode = "normal")
