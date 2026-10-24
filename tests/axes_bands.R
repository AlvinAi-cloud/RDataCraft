source('app.R')
checks <- 0L
check <- function(ok,label) {if(!isTRUE(ok)) stop('FAIL: ',label,call.=FALSE); checks <<- checks+1L; cat('PASS:',label,'\n')}
errors <- function(expr) inherits(tryCatch(force(expr),error=identity),'error')
near <- function(a,b) isTRUE(all.equal(unname(a),b,tolerance=1e-7))
tab <- pc_xy_replicates(data.frame(X=c(2,0,1,3),Control=c(6,2,4,8)),3)
tab[[3]] <- c('8','4','6','10');tab[[4]] <- c('10','6','8','12')
n <- pc_normalize(tab,'xy');s <- pc_defaults();s$layout <- 'xy';s$method <- 'descriptive';s$graph <- 'xyband';s$show_points <- FALSE
p <- pc_plot(n,s);b <- ggplot2::ggplot_build(p)
check(near(p$data$x,0:3) && near(p$data$mean,c(4,6,8,10)),'mean band sorts X and uses all source replicates')
check(near(p$data$sd,rep(2,4)) && near(p$data$sem,rep(2/sqrt(3),4)),'SD and SEM agree with hand-calculated triplicates')
check(near(b$data[[1]]$ymax-b$data[[1]]$ymin,rep(4/sqrt(3),4)),'SEM ribbon has mean ± SD/sqrt(n) endpoints')
s$error <- 'sd';b <- ggplot2::ggplot_build(pc_plot(n,s))
check(near(b$data[[1]]$ymax-b$data[[1]]$ymin,rep(4,4)),'SD ribbon has mean ± SD endpoints')
check(!any(vapply(pc_plot(n,s)$layers,function(l) inherits(l$geom,'GeomErrorbar'),logical(1))),'shaded graph uses a ribbon instead of error bars')
s$error <- 'ci';p <- pc_plot(n,s)
check(near(p$data$margin,rep(qt(.975,2)*2/sqrt(3),4)),'95% mean interval uses the per-time-point t critical value')
s$error <- 'none';check(!any(vapply(pc_plot(n,s)$layers,function(l) inherits(l$geom,'GeomRibbon'),logical(1))),'None removes shading while retaining mean trajectories')
s$error <- 'sem';s$y_min <- '0';s$y_max <- '15';s$x_min <- '0';s$x_max <- '3'
b <- ggplot2::ggplot_build(pc_plot(n,s))$layout$panel_params[[1]]
check(near(b$y.range,c(0,15)) && near(b$x.range,c(0,3)),'entered X and Y limits are exact without endpoint padding')
s$y_min <- '-2';s$y_max <- '';b <- ggplot2::ggplot_build(pc_plot(n,s))$layout$panel_params[[1]]
check(b$y.range[1]==-2,'a one-sided manual minimum is exact')
s$y_min <- '';s$x_min <- '';s$x_max <- '';b <- ggplot2::ggplot_build(pc_plot(n,s))$layout$panel_params[[1]]
check(any(abs(na.omit(b$y$breaks)-b$y.range[1])<1e-8),'automatic Y baseline aligns with its lowest tick')
s$log_y <- TRUE;s$y_min <- '1';s$y_max <- '100';b <- ggplot2::ggplot_build(pc_plot(n,s))$layout$panel_params[[1]]
check(near(b$y.range,c(0,2)),'logarithmic manual endpoints remain exact in transformed coordinates')
s$y_min <- '';s$y_max <- '';bad <- n;bad$data$value[bad$data$x==0] <- c(.01,.01,5)
check(errors(pc_plot(bad,modifyList(s,list(error='sd')))),'bands crossing zero reject a logarithmic Y axis')
s$width<-152.4;s$height<-114.3 # Explicitly sized fixture for an 80 mm plotting panel.
s$log_y <- FALSE;s$x_axis_length <- 80;s$y_axis_length <- 50
p <- pc_plot(n,s);g <- ggplot2::ggplotGrob(p);panel <- g$layout[grepl('^panel$',g$layout$name),]
check(near(grid::convertWidth(g$widths[panel$l],'mm',valueOnly=TRUE),80) && near(grid::convertHeight(g$heights[panel$t],'mm',valueOnly=TRUE),50),'plotting panel has exactly the requested physical X and Y lengths')
svg <- pc_graph_svg(p,s)
check(grepl(sprintf("width='%.2f' height='%.2f'",80/25.4*72,50/25.4*72),svg,fixed=TRUE),'exported SVG panel preserves exact physical dimensions')
check(errors(pc_graph_edit(tab,s,list(x_axis_length=350))) && errors(pc_graph_edit(tab,s,list(y_axis_length=-1))),'oversized and negative axis lengths reject without clipping the canvas')
saved <- pc_project(tab,s);roundtrip <- pc_decode_project(saved)
check(saved$schema_version==7L && roundtrip$settings$x_axis_length==80 && roundtrip$settings$graph=='xyband','shaded graph and physical axis lengths round-trip with schema 7')
legacy <- pc_defaults();legacy$x_axis_length <- NULL;legacy$y_axis_length <- NULL
loaded <- pc_decode_project(list(format='rdatacraft',schema_version=1L,data_tsv=pc_table_text(pc_example('column')$table),settings=legacy))
check(loaded$settings$x_axis_length==0 && loaded$settings$y_axis_length==0,'older projects default to automatic axis lengths')
gap <- tab;gap[[3]][3] <- NA;gap[[4]][3] <- NA
gp <- pc_plot(pc_normalize(gap,'xy'),s)
check(length(unique(gp$layers[[1]]$data$segment))==2 && grepl('fewer than two',gp$labels$caption),'missing replicate interval creates separate ribbon segments and an explanatory caption')
single <- pc_normalize(data.frame(X=0:3,Y=1:4),'xy')
check(errors(pc_plot(single,s)),'single observations do not fabricate SD or SEM shading')
ls <- pc_layout_settings(list(selected='D1:V1',width=180,height=160))
check(inherits(pc_compose_layout(list('D1:V1'=p),ls),'gTree'),'figure layouts can fit a graph with standalone physical axis lengths')
cat(checks,'checks passed\n')
