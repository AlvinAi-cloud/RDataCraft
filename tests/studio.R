app <- source('app.R')$value
checks <- 0L
check <- function(ok,label) {if(!isTRUE(ok)) stop('FAIL: ',label,call.=FALSE);checks <<- checks+1L;cat('PASS:',label,'\n')}
errors <- function(expr) inherits(tryCatch(force(expr),error=identity),'error')
dir.create('artifacts/studio',recursive=TRUE,showWarnings=FALSE)
# Render the graph catalogue against independent source examples.
for(layout in unname(pc_layouts())) {
  tab <- pc_example(layout)$table;n <- pc_normalize(tab,layout);s <- pc_defaults();s$layout <- layout;s$method <- 'descriptive';s$show_p <- FALSE
  for(graph in unname(pc_graphs(layout))) {
    if(graph=='residual') next
    if(graph=='xyband') {check(errors(pc_plot(n,modifyList(s,list(graph=graph)))),'shaded variability requires source replicates'); next}
    s$graph <- graph
    check(inherits(ggplot2::ggplotGrob(pc_plot(n,s)),'gtable'),paste(layout,graph,'renders from source observations'))
  }
}
tab <- pc_check_table(data.frame(A=c(1,2,3,20),B=c(4,6,8,10)));s <- pc_defaults();s$method <- 'descriptive';s$show_p <- FALSE;s$show_points <- FALSE;s$graph <- 'median'
p <- pc_plot(pc_normalize(tab),s)
check(identical(p$data$value,c(2.5,7)) && identical(p$data$low,c(1.75,5.5)) && identical(p$data$high,c(7.25,8.5)),'median and IQR match R type-7 quantiles, including an outlier')
check(nrow(ggplot2::ggplot_build(p)$data[[2]])==2,'summary-only median graph contains two summary symbols')
xy <- pc_xy_replicates(data.frame(X=c(1,2,3),Y=c(2,4,8)),2);xy[[3]] <- c('4','6','10');sx <- pc_defaults();sx$layout <- 'xy';sx$method <- 'descriptive';sx$graph <- 'area'
p <- pc_plot(pc_normalize(xy,'xy'),sx)
check(identical(p$data$value,c(3,5,9)) && nrow(pc_normalize(xy,'xy')$data)==6,'XY area graph averages replicates without changing source observations')
sx$log_y <- TRUE;check(errors(pc_plot(pc_normalize(xy,'xy'),sx)),'area plot rejects a logarithmic zero baseline')
s$graph <- 'points';s$y_tick_step <- '5';s$ref_y <- '7';s$x_tick_angle <- 45
p <- pc_plot(pc_normalize(tab),s);b <- ggplot2::ggplot_build(p)
check(all(na.omit(b$layout$panel_params[[1]]$y$breaks) %% 5 == 0),'manual tick interval reaches continuous axis breaks')
check(tail(p$layers,1)[[1]]$data$yintercept==7 && p$theme$axis.text.x$angle==45,'reference line and label rotation reach plot geometry')
check(errors(pc_graph_edit(tab,s,list(y_tick_step='-2'))) && errors(pc_graph_edit(tab,s,list(y_tick_step='junk'))),'invalid tick intervals reject atomically')
check(errors(pc_graph_edit(tab,s,list(log_y=TRUE))),'log axis cannot retain a linear tick interval')
check(errors(pc_graph_edit(tab,s,list(ref_x='2'))),'category axes reject numeric reference lines')
s$y_tick_step <- '0.000001';check(errors(ggplot2::ggplotGrob(pc_plot(pc_normalize(tab),s))),'excessive tick counts fail before export')
s <- pc_defaults();s$graph <- 'median';s$method <- 'descriptive'
project <- pc_project(tab,s);check(project$schema_version==6L && pc_decode_project(project)$settings$graph=='median','new graph types round-trip through schema 6 even in a single-table project')
s1 <- pc_defaults();s2 <- s1;s1$font_size <- 13L;s2$font_size <- 13
check(identical(pc_graph_token(tab,s1,"D1","V1",1L),pc_graph_token(tab,s2,"D1","V1",1)),"preview tokens treat integer and numeric settings identically after project restore")
ns <- pc_defaults();ns$method <- "welch";ns$graph <- "mean";ns$group1 <- "A";ns$group2 <- "B";nn <- pc_normalize(tab)
comparison <- pc_analyze(nn,"welch","A","B",ns);annotated <- pc_plot(nn,ns,comparison)
check(any(vapply(annotated$layers,function(layer) inherits(layer$geom,"GeomSegment"),logical(1))) && nrow(comparison$comparisons)==1,"mean/error summaries retain the selected analysis comparison brackets")
# Header contracts apply to every table type.
for(layout in unname(pc_layouts())) {
  before <- pc_example(layout)$table;after <- pc_rename_header(before,layout,1,'New label')
  check(names(after)[1]=='New label' && identical(unname(as.matrix(after)),unname(as.matrix(pc_check_table(before)))) && identical(names(after)[-1],names(before)[-1]),paste('direct',layout,'header rename preserves every cell'))
}
renamed <- pc_rename_header(xy,'xy',3,'Renamed')
check(identical(names(renamed)[2:3],c('Renamed [rep 1]','Renamed [rep 2]')) && identical(unname(as.matrix(renamed)),unname(as.matrix(xy))),'editing either replicate header renames the whole series without moving cells')
check(errors(pc_rename_header(tab,'column',1,'B')) && errors(pc_rename_header(tab,'column',1,'')) && errors(pc_rename_header(tab,'column',1,'bad\nname')),'duplicate, empty and multiline headers reject atomically')
# Physical layout geometry and exports.
s <- pc_defaults();s$method <- 'descriptive';book <- list(D1=pc_sheet(tab,s,'Experiment',list(V1=pc_view(s,'One'),V2=pc_view(s,'Two'),V3=pc_view(s,'Three'))))
ls <- pc_layout_defaults();ls$selected <- c('D1:V1','D1:V2','D1:V3')
rects <- pc_layout_rects(ls)
check(rects[[1]]$x==4 && rects[[2]]$x==92 && rects[[1]]$w==84 && rects[[3]]$y>rects[[1]]$y,'grid panel positions match requested page margins and gap')
hero <- pc_layout_apply_edit(ls,list(action='template',value='hero'));r <- pc_layout_rects(hero)
check(r[[1]]$w==172 && r[[2]]$y>r[[1]]$y && r[[3]]$x>r[[2]]$x,'large-top template uses full-width first panel and lower grid')
manual <- pc_layout_apply_edit(ls,list(action='move',key='D1:V2',rect=list(x=100,y=30,w=60,h=55)))
check(manual$arrangement=='manual' && isTRUE(all.equal(pc_layout_rects(manual)[[2]],list(x=100,y=30,w=60,h=55))),'manual placement preserves exact page coordinates')
manual <- pc_layout_apply_edit(manual,list(action='label',key='D1:V2',value='B2'))
reordered <- pc_layout_apply_edit(manual,list(action='earlier',key='D1:V2'))
check(reordered$selected[1]=='D1:V2' && pc_layout_rects(reordered)[['D1:V2']]$x==100,'reordering keeps manual coordinates attached to graph identity')
check(errors(pc_layout_apply_edit(ls,list(action='move',key='D1:V1',rect=list(x=170,y=0,w=30,h=50)))),'panels cannot be placed outside the page')
check(errors(pc_layout_apply_edit(ls,list(action='move',key='D1:V1',rect=list(x=0,y=0,w=1,h=50)))),'undersized panel edits reject atomically')
plots <- pc_layout_plots(book,manual$selected)
for(fmt in c('svg','pdf','png')) {
  file <- paste0('artifacts/studio/layout.',fmt)
  ggplot2::ggsave(file,pc_compose_layout(plots,manual),device=switch(fmt,svg=svglite::svglite,pdf=pc_pdf_device,png=pc_png_device),width=manual$width,height=manual$height,units='mm',dpi=150,bg='white')
  check(file.info(file)$size>1000,paste('custom physical layout exports as',fmt))
}
svg <- paste(readLines('artifacts/studio/layout.svg'),collapse='\n')
check(grepl('>B2</text>',svg,fixed=TRUE) && !grepl('rdatacraft-layout',svg,fixed=TRUE),'export retains custom labels without editing metadata')
svg <- pc_layout_svg(plots,manual,list(token='abc',names=list('D1:V1'='One')))
check(grepl('rdatacraft-layout',svg,fixed=TRUE) && grepl('"x":100',svg,fixed=TRUE),'editable preview carries escaped layout coordinates')
project <- pc_project(tab,s,book,'D1',manual);loaded <- pc_decode_project(project)
check(project$schema_version==6L && identical(loaded$figure_layout,manual),'panel geometry and labels round-trip in schema 6')
legacy_layout <- pc_layout_defaults();legacy_layout$gap <- 4L;legacy_layout$margin <- 4L;legacy_layout$label_size <- 14L
plain <- pc_defaults();plain$series_styles <- '{"A":{"color":"#123456"}}'
check(pc_project(tab,plain,list(D1=pc_sheet(tab,plain,"Data")),"D1",legacy_layout)$schema_version==5L,"integer Shiny values do not upgrade a default layout to schema 6")
# Deleting a data table cleans every dependent layout reference.
book$D2 <- pc_sheet(tab,s,'Other');ls$selected <- c('D1:V1','D2:V1');ls$labels <- '{"D1:V1":"A","D2:V1":"B"}'
r <- pc_delete_table(book,'D1','D1',ls)
check(identical(names(r$book),'D2') && r$active=='D2' && identical(r$layout$selected,'D2:V1'),'delete active table selects a survivor and removes dependent panels')
check(!grepl('D1:',r$layout$labels,fixed=TRUE) && identical(r$book$D2,book$D2),'delete preserves unrelated table and removes obsolete panel labels')
r <- pc_delete_table(r$book,'D2','D2',r$layout)
check(length(r$book)==1 && all(is.na(pc_read_text(r$book$D1$data_tsv,'\t'))) && !length(r$layout$selected),'deleting last table creates a blank table and clears layout panels')
check(errors(pc_delete_table(book,'D99','D1',ls)),'stale table deletion rejects explicitly')
# Real reactive flow: stale events, undo/redo and native save payload use the same state.
shiny::testServer(app,{
  # Explicit fixture: production startup is intentionally empty.
  raw(pc_example("column")$table);sheet_name("Treatment groups");project_name("Example study");document_open(TRUE)
  do.call(session$setInputs,pc_defaults());session$flushReact()
  ack <- function(){target<-restoring_settings();if(!is.null(target)) do.call(session$setInputs,target);session$flushReact()}
  before <- raw();identity <- grid_identity()
  session$setInputs(rename_column=c(identity,list(column=1,name='Vehicle',nonce=1)));session$flushReact()
  check(names(raw())[1]=='Vehicle' && identical(raw()[,1],before[,1]),'server commits direct header rename without changing cells')
  session$setInputs(rename_column=c(identity,list(column=2,name='Stale',nonce=2)));session$flushReact()
  check(!'Stale' %in% names(raw()),'stale header token cannot rename a newer table')
  session$setInputs(undo_data=1);session$flushReact();check(identical(pc_table_text(raw()),pc_table_text(before)),'one data Undo restores the original header')
  session$setInputs(redo_data=1);session$flushReact();check(names(raw())[1]=='Vehicle','one data Redo reapplies the header')
  context <- graph_context();session$setInputs(graph_edit=c(context,list(changes=list(title='Edited graph',y_tick_step='5'),nonce=1)));session$flushReact();ack()
  check(settings()$title=='Edited graph' && settings()$y_tick_step=='5','new graph controls are applied by server')
  session$setInputs(undo_graph=1);session$flushReact();ack();check(settings()$title!='Edited graph','graph formatting Undo restores the previous appearance')
  session$setInputs(redo_graph=1);session$flushReact();ack();check(settings()$title=='Edited graph','graph formatting Redo restores the change')
  session$setInputs(layout_views='D1:V1');session$flushReact();token <- layout_token()
  session$setInputs(layout_edit=list(token=token,action='move',key='D1:V1',rect=list(x=20,y=25,w=100,h=100),nonce=1));session$flushReact()
  check(layout_settings()$arrangement=='manual' && pc_layout_rects(layout_settings())[[1]]$x==20,'layout server commits millimetre geometry')
  session$setInputs(layout_edit=list(token=token,action='label',key='D1:V1',value='stale',nonce=2));session$flushReact()
  check(layout_settings()$labels=='{}','stale layout tokens cannot update newer geometry')
  session$setInputs(undo_layout=1);session$flushReact();check(layout_settings()$arrangement=='grid','layout Undo restores arrangement')
  session$setInputs(redo_layout=1);session$flushReact();check(layout_settings()$arrangement=='manual','layout Redo restores manual geometry')
  session$setInputs(delete_named_table=list(sheet='D1',nonce=1));session$flushReact()
  check(!is.null(deleting_table()) && identical(raw()[,1],before[,1]),'clicking table x only stages confirmation')
  session$setInputs(add_row=1);session$flushReact();session$setInputs(confirm_delete_table=1);session$flushReact()
  check(nrow(raw())==nrow(before)+1,'confirmation rejects a table modified after opening the dialog')
  session$setInputs(delete_named_table=list(sheet='D1',nonce=2));session$flushReact();session$setInputs(confirm_delete_table=2);session$flushReact();ack()
  check(length(workbook())==1 && all(is.na(raw())) && sheet_name()=='Untitled data','confirmed final-table deletion creates a clean blank replacement')
})
cat(checks,'studio checks passed.\n')
