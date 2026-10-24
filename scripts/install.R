# Install runtime dependencies locally; keep binaries and source archives for releases.
root <- normalizePath(getwd(),winslash='/')
lib <- file.path(Sys.getenv("RDATACRAFT_RUNTIME",file.path(root,"runtime")), "library")
dir.create(lib, recursive = TRUE, showWarnings = FALSE)
lib <- normalizePath(lib,winslash='/',mustWork=TRUE)
.libPaths(c(lib, .Library),include.site=FALSE)
options(repos = c(CRAN = "https://cloud.r-project.org"), timeout = 300)
packages <- c("shiny", "bslib", "ggplot2", "DT", "readxl", "jsonlite", "svglite", "survival", "xml2", "processx")
missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
dir.create("downloads/packages", recursive = TRUE, showWarnings = FALSE)
if (length(missing)) install.packages(missing, lib = lib, dependencies = NA,
                                     destdir = "downloads/packages")
if (!all(vapply(packages, requireNamespace, logical(1), quietly = TRUE))) {
  stop("Some dependencies could not be installed. Inspect the installation output.")
}
installed <- installed.packages(lib.loc = .libPaths())
installed <- installed[!duplicated(installed[, "Package"]), , drop = FALSE]
installed <- installed[normalizePath(installed[, "LibPath"],winslash='/',mustWork=FALSE) == lib | (!is.na(installed[, "Priority"]) & installed[, "Priority"] == "recommended"), , drop = FALSE]
manifest <- data.frame(package = installed[, "Package"], version = installed[, "Version"],
                       license = installed[, "License"], row.names = NULL)
manifest <- manifest[order(manifest$package), ]
write.csv(manifest, "dependencies.csv", row.names = FALSE)
jsonlite::write_json(list(r_version = as.character(getRversion()), platform = R.version$platform,
                         packages = manifest), "dependencies.lock.json", pretty = TRUE,
                     auto_unbox = TRUE)
cat("RDataCraft dependencies installed:", nrow(manifest), "packages\n")
