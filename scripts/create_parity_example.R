source("app.R")
book <- list()
e <- pc_example("column");s <- pc_defaults();s$method <- "anova";s$graph <- "bar";s$title <- "Independent treatment groups"
s$series_styles <- '{"Treatment A":{"color":"#4477AA","point_shape":17,"point_size":3},"Treatment B":{"color":"#CC6677","point_shape":22,"point_size":3}}'
book$D1 <- pc_sheet(e$table,s,"Treatment groups")
x <- 0:10
tab <- pc_xy_replicates(data.frame(Time=x,Control=1+.7*x+.2*sin(x),Drug=2+1.3*x+.25*cos(x)),3)
tab[[3]] <- as.numeric(tab[[2]])+.3;tab[[4]] <- as.numeric(tab[[2]])-.2
tab[[6]] <- as.numeric(tab[[5]])+.4;tab[[7]] <- as.numeric(tab[[5]])-.3
s <- pc_defaults();s$layout <- "xy";s$method <- "linear";s$graph <- "scatter";s$group1 <- "Control";s$group2 <- "Drug";s$fit_scope <- "all"
s$title <- "Independent fits for each series";s$x_label <- "Time (hours)";s$y_label <- "Response (a.u.)"
s$series_styles <- '{"Control":{"color":"#247763","point_shape":16,"point_size":2.5,"line_width":0.9,"line_type":"solid"},"Drug":{"color":"#AA4477","point_shape":17,"point_size":2.8,"line_width":1.1,"line_type":"dashed"}}'
views <- list(V1=pc_view(s,"Independent linear fits"));mean_s <- s;mean_s$graph <- "xymean";mean_s$error <- "sem";mean_s$method <- "descriptive";mean_s$title <- "Replicate means ± SEM"
views$V2 <- pc_view(mean_s,"Means and SEM");res <- s;res$graph <- "residual";res$title <- "Inspect both series residuals";views$V3 <- pc_view(res,"Residuals")
book$D2 <- pc_sheet(tab,s,"Triplicate time course",views)
x <- 10^seq(-2,2,length.out=20)
tab <- data.frame(Concentration=x,CompoundA=1+8*plogis(-2*(log10(x)+.3))+.025*sin(seq_along(x)),CompoundB=1+8*plogis(-2*(log10(x)-.4))+.025*cos(seq_along(x)))
s <- pc_defaults();s$layout <- "xy";s$method <- "fourpl";s$graph <- "scatter";s$group1 <- "CompoundA";s$group2 <- "CompoundB";s$fit_scope <- "all";s$log_x <- TRUE
s$title <- "Independent dose-response fits";s$x_label <- "Concentration";s$y_label <- "Response"
s$series_styles <- '{"CompoundB":{"color":"#AA4477","point_shape":17,"point_size":2.8,"line_width":1,"line_type":"dashed"}}'
book$D3 <- pc_sheet(tab,s,"Two-compound dose response")
active <- book$D2;layout <- pc_layout_defaults();layout$selected <- c("D1:V1","D2:V1","D2:V2","D3:V1");layout$title <- "RDataCraft workflow examples";layout$height <- 200
pc_write_project(pc_project(pc_read_text(active$data_tsv,"\t"),active$settings,book,"D2",layout,"Prism workflow improvements"),"examples/Prism workflow improvements.rdatacraft")
stopifnot(length(pc_load_project("examples/Prism workflow improvements.rdatacraft")$worksheets)==3)
cat("Created original examples for per-series formatting, replicates and independent fits.\n")
