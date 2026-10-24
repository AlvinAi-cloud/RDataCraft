required <- c("shiny","bslib","ggplot2","DT","readxl","jsonlite","svglite","survival","xml2")
missing <- required[!vapply(required,requireNamespace,logical(1),quietly=TRUE)]
if(length(missing)) stop("Incomplete bundled library: ",paste(missing,collapse=", "),". Restore dependencies before building.")
source("R/devices.R")
file <- tempfile(fileext=".pdf")
pc_pdf_device(file,width=2,height=2);plot.new();text(.5,.5,"α ± μ");dev.off()
stopifnot(file.exists(file),file.info(file)$size>100)
unlink(file)
cat("Bundled runtime ready:",R.version$platform,"with Unicode vector PDF support.\n")
