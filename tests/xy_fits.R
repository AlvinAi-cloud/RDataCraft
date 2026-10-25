app <- source('app.R')$value
checks <- 0L
check <- function(ok,label) {if(!isTRUE(ok)) stop('FAIL: ',label,call.=FALSE);checks <<- checks+1L;cat('PASS:',label,'\n')}
dir.create('artifacts/xy-review',recursive=TRUE,showWarnings=FALSE)
x <- rep(1:8,each=3); noise <- rep(c(-.3,.1,.2),8)
tab <- pc_check_table(data.frame(X=x,Increasing=2+2*x+noise,Decreasing=24-1.3*x+noise))
n <- pc_normalize(tab,'xy'); s <- pc_defaults()
s$layout <- 'xy';s$graph <- 'xymean';s$method <- 'linear';s$group1 <- 'Increasing';s$group2 <- 'Decreasing'
s$fit_scope <- 'all';s$xy_connections <- 'none';s$xy_fit_band <- FALSE;s$show_points <- FALSE;s$error <- 'sd'
s$title <- 'Independent fits with mean ± SD';s$x_label <- 'Time';s$y_label <- 'Response'
a <- pc_analyze(n,s$method,s$group1,s$group2,s)
check(setequal(unique(a$curve$group),n$groups) && all(a$fit_status$status=='Fitted'),'independent linear fits produce curves for both source series')
for(g in n$groups) {
 curve <- a$curve[a$curve$group==g,]
 expected <- if(g=='Increasing') 2+2*curve$x else 24-1.3*curve$x
 check(max(abs(curve$fit-expected))<1e-8,paste(g,'curve agrees with its independent known regression'))
}
is_line <- function(layer) inherits(layer$geom,'GeomLine') || inherits(layer$geom,'GeomStep')
is_fit <- function(layer) is.data.frame(layer$data) && 'fit' %in% names(layer$data)
for(graph in c('scatter','line','xymean','xyband','step','area')) {
 s$graph <- graph;p <- pc_plot(n,s,a);built <- ggplot2::ggplot_build(p)
 lines <- which(vapply(p$layers,is_line,logical(1)))
 check(length(lines)==1 && is_fit(p$layers[[lines]]),paste(graph,'shows fitted curves without observation connectors'))
 check(setequal(unique(p$layers[[lines]]$data$group),n$groups),paste(graph,'retains both fitted groups'))
 if(graph=='xymean') check(any(vapply(p$layers,function(l) inherits(l$geom,'GeomErrorbar'),logical(1))),'mean/error graph keeps observation error bars alongside fitted curves')
 hidden <- pc_plot(n,modifyList(s,list(xy_show_fit=FALSE)),a)
 check(!any(vapply(hidden$layers,is_line,logical(1))),paste(graph,'can hide fitted curves and connectors independently'))
 connected <- pc_plot(n,modifyList(s,list(xy_connections='connect')),a)
 check(sum(vapply(connected$layers,is_line,logical(1)))==2,paste(graph,'can show connectors and fits together'))
}
s$graph <- 'xymean';p <- pc_plot(n,s,a)
with_band <- pc_plot(n,modifyList(s,list(xy_fit_band=TRUE)),a)
check(sum(vapply(with_band$layers,function(l) inherits(l$geom,'GeomRibbon'),logical(1)))==1 && !any(vapply(p$layers,function(l) inherits(l$geom,'GeomRibbon'),logical(1))),'fitted confidence band has its own display toggle')
single <- modifyList(s,list(fit_scope='selected',group1='Decreasing'))
one <- pc_analyze(n,'linear',single$group1,single$group2,single)
check(identical(unique(pc_plot(n,single,one)$layers[[length(p$layers)]]$data$group),'Decreasing'),'selected-series fitting still draws only the requested series')
quadratic <- pc_analyze(n,'quadratic',s$group1,s$group2,s)
check(setequal(unique(quadratic$curve$group),n$groups) && inherits(ggplot2::ggplotGrob(pc_plot(n,s,quadratic)),'gtable'),'polynomial multi-series fitting works with mean/error display')
weighted <- pc_analyze(n,'linear',s$group1,s$group2,modifyList(s,list(fit_weight='replicate_sd',fit_replicates='mean')))
check(setequal(unique(weighted$curve$group),n$groups),'multi-series mean fits preserve replicate-SD weighting')
bad <- tab;bad$Incomplete <- c('5',rep(NA_character_,nrow(bad)-1));partial <- pc_analyze(pc_normalize(bad,'xy'),'linear',s$group1,s$group2,s)
check(any(partial$fit_status$status=='Not fitted') && setequal(unique(partial$curve$group),n$groups),'multi-series output reports fit status without losing valid curves')
project <- pc_project(tab,s);loaded <- pc_decode_project(project)
check(project$schema_version==12L && identical(loaded$settings$xy_connections,'none') && !loaded$settings$xy_fit_band,'line and fitted-band controls survive save/reopen with explicit schema support')
legacy <- list(format='rdatacraft',schema_version=1L,data_tsv=pc_table_text(tab),settings=s);legacy$settings[c('xy_connections','xy_show_fit','xy_fit_band')] <- NULL
old <- pc_decode_project(legacy)
check(old$settings$xy_connections=='auto' && old$settings$xy_show_fit && old$settings$xy_fit_band,'older projects preserve automatic connections and visible fits')
for(fmt in c('svg','pdf','png')) {
 file <- paste0('artifacts/xy-review/mean-errors-and-fits.',fmt)
 ggplot2::ggsave(file,p,device=switch(fmt,svg=svglite::svglite,pdf=pc_pdf_device,png=pc_png_device),width=s$width,height=s$height,units='mm',dpi=150)
 check(file.info(file)$size>1000,paste('both fitted series and observation error bars export as',fmt))
}
edited <- pc_graph_edit(tab,s,list(xy_connections='connect',xy_show_fit=FALSE,xy_fit_band=TRUE))
check(edited$xy_connections=='connect' && !edited$xy_show_fit && edited$xy_fit_band,'direct graph formatting accepts separate connection and fitted-curve controls')
shiny::testServer(app,{
 raw(tab);document_open(TRUE);do.call(session$setInputs,s);session$flushReact()
 messages <- list();original_send <- session$sendInputMessage
 session$sendInputMessage <- function(inputId,message) {messages[[length(messages)+1L]] <<- list(id=inputId,message=message);original_send(inputId,message)}
 session$setInputs(fit_scope='selected',xy_fit_all=1);session$flushReact()
 # Apply the select-input update as a browser does after the button response.
 check(any(vapply(messages,function(m) identical(m$id,'fit_scope') && identical(m$message$value,'all'),logical(1))),'graph shortcut requests all-series fitting using the existing analysis setting')
})
pc_write_project(project,'artifacts/xy-review/XY curve fitting review.rdatacraft')
cat(checks,'XY fitted-curve checks passed.\n')
