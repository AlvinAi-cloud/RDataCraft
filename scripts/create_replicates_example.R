# Original illustrative observations for exploring the XY replicate workflow.
source("R/data.R")
source("R/analysis.R")
source("R/plot.R")
source("R/project.R")
tab <- pc_check_table(data.frame(Time = c(0,1,2,4,6,8), Control = rep(NA_character_,6), Treatment = rep(NA_character_,6)))
tab <- pc_xy_replicates(tab,3)
tab[,2:7] <- data.frame(
  c(1.0,1.4,2.0,2.8,3.6,4.1), c(1.2,1.6,1.8,3.1,3.4,4.4), c(0.9,1.5,2.1,2.9,3.8,4.2),
  c(1.1,2.1,3.2,5.0,6.4,7.9), c(1.0,2.3,3.5,5.4,6.8,8.3), c(1.2,2.0,3.3,5.2,6.6,8.0))
s <- pc_defaults(); s$layout <- "xy"; s$graph <- "xymean"; s$method <- "descriptive"
s$title <- "Response over time"; s$x_label <- "Time (hours)"; s$y_label <- "Response (a.u.)"
s$group1 <- "Control"; s$group2 <- "Treatment"
book <- list(D1 = pc_sheet(tab,s,"Triplicate time course"))
file <- "examples/XY replicates example.rdatacraft"
pc_write_project(pc_project(tab,s,book,study_name="XY replicate example"),file)
stopifnot(pc_normalize(pc_load_project(file)$table,"xy")$replicates == 3L)
cat("Created",file,"\n")
