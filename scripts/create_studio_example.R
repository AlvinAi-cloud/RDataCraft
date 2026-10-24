source('R/data.R');source('R/analysis.R');source('R/plot.R');source('R/project.R')
base <- pc_load_project('examples/Prism workflow improvements.rdatacraft');book <- base$worksheets
# Keep the original observations and add linked distribution summaries.
s <- book$D1$settings;s$method <- 'anova';s$graph <- 'violinbox';s$title <- 'Treatment distributions';s$font_size <- 11;s$show_p <- FALSE
book$D1$views$V2 <- pc_view(s,'Violin + box')
s$graph <- 'median';s$x_tick_angle <- 35;s$title <- 'Median and interquartile range';book$D1$views$V3 <- pc_view(s,'Median + IQR')
s <- book$D2$views$V1$settings;s$font_size <- 11;s$title <- 'Independent time-course fits';book$D2$views$V1$settings <- s
if(book$D2$active_view=='V1') book$D2$settings <- s
# An original balanced grouped example for distribution / mean heatmap views.
e <- pc_example('grouped');s <- pc_defaults();s$layout <- 'grouped';s$method <- 'twoway';s$graph <- 'groupbox';s$title <- 'Replicates by time and treatment';s$x_label <- 'Time';s$y_label <- 'Response';s$font_size <- 11;s$show_p <- FALSE
heat <- s;heat$graph <- 'groupheat';heat$title <- 'Mean response';heat$y_label <- ''
book$D4 <- pc_sheet(e$table,s,'Factorial response',list(V1=pc_view(s,'Grouped distributions'),V2=pc_view(heat,'Mean heatmap')))
e <- pc_example('contingency');s <- pc_defaults();s$layout <- 'contingency';s$method <- 'fisher';s$graph <- 'stacked';s$title <- 'Response counts';s$x_label <- 'Population';s$y_label <- 'Subjects';s$font_size <- 11;s$show_p <- TRUE
book$D5 <- pc_sheet(e$table,s,'Treatment outcomes')
ls <- pc_layout_defaults();ls$title <- 'Treatment response: observations, fits and outcomes';ls$width <- 180;ls$height <- 220;ls$selected <- c('D2:V1','D1:V3','D4:V2','D5:V1');ls$scale_text <- TRUE;ls$label_size <- 12
rects <- pc_layout_rects(ls);rects[['D2:V1']]$h <- 98;rects[['D1:V3']]$h <- 98
ls$arrangement <- 'manual';ls$positions <- jsonlite::toJSON(rects,auto_unbox=TRUE,digits=10)
active <- 'D2';sh <- book[[active]]
p <- pc_project(pc_read_text(sh$data_tsv,'\t'),sh$settings,book,active,ls,'Figure studio — RDataCraft 0.7')
pc_write_project(p,'examples/Figure studio.rdatacraft')
cat('Created schema',p$schema_version,'studio example with',length(book),'data tables.\n')
