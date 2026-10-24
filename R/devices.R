# Quartz is part of macOS and preserves Unicode without an XQuartz installation.
pc_pdf_device <- function(filename, width, height, bg = "white", ...) {
  if (identical(Sys.info()[["sysname"]], "Darwin"))
    grDevices::quartz(type = "pdf", file = filename, width = width, height = height, bg = bg, ...)
  else grDevices::cairo_pdf(filename = filename, width = width, height = height, bg = bg, ...)
}
pc_png_device <- function(filename, width, height, units = "in", res = 300, bg = "white", ...) {
  grDevices::png(filename, width = width, height = height, units = units, res = res, bg = bg,
    type = if (identical(Sys.info()[["sysname"]], "Darwin")) "quartz" else "cairo", ...)
}
