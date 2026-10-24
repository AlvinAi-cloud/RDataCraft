root <- normalizePath(getwd())
lib <- file.path(Sys.getenv("RDATACRAFT_RUNTIME",file.path(root,"runtime")),"library")
packages <- installed.packages(lib.loc = .libPaths())
packages <- packages[!duplicated(packages[, "Package"]), , drop = FALSE]
packages <- packages[normalizePath(packages[, "LibPath"],winslash='/',mustWork=FALSE) == normalizePath(lib,winslash='/') | (!is.na(packages[, "Priority"]) & packages[, "Priority"] == "recommended"), , drop = FALSE]
dir.create("licenses/packages", recursive = TRUE, showWarnings = FALSE)
records <- lapply(packages[, "Package"], function(package) {
  path <- find.package(package)
  dest <- file.path(root, "licenses/packages", package)
  dir.create(dest, recursive = TRUE, showWarnings = FALSE)
  file.copy(file.path(path, "DESCRIPTION"), dest, overwrite = TRUE)
  all <- list.files(path, recursive = TRUE, full.names = TRUE, all.files = TRUE)
  selected <- all[grepl("^(licen[cs]e|copying|copyright|notice)([._-].*)?$", basename(all), ignore.case = TRUE)]
  for (source in selected) {
    relative <- substring(source, nchar(path) + 2)
    target <- file.path(dest, relative)
    dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
    file.copy(source, target, overwrite = TRUE)
  }
  desc <- read.dcf(file.path(path, "DESCRIPTION"))
  data.frame(package = package, version = desc[1, "Version"], license = desc[1, "License"],
             author = if ("Author" %in% colnames(desc)) desc[1, "Author"] else "See DESCRIPTION",
             row.names = NULL)
})
write.csv(do.call(rbind, records), "licenses/THIRD_PARTY.csv", row.names = FALSE)
file.copy(file.path(R.home(), "COPYING"), "licenses/R-COPYING", overwrite = TRUE)
license_dir <- file.path(R.home("share"), "licenses")
if (dir.exists(license_dir)) file.copy(license_dir, "licenses", recursive = TRUE, overwrite = TRUE)
cat("Collected license notices for", nrow(packages), "R packages.\n")
