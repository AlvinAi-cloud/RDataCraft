source("R/data.R");source("R/analysis.R");source("R/plot.R");source("R/project.R")
checks<-0L
check<-function(ok,label){if(!isTRUE(ok))stop("FAIL: ",label,call.=FALSE);checks<<-checks+1L;cat("PASS:",label,"\n")}
errors<-function(expr)inherits(tryCatch(force(expr),error=identity),"error")
dir.create("artifacts/views",recursive=TRUE,showWarnings=FALSE)
tab<-pc_example("column")$table;s<-pc_defaults();other<-s;other$method<-"anova";other$graph<-"box";other$title<-"Distribution view";other$legend_position<-"bottom";other$grid_lines<-TRUE
views<-list(V1=pc_view(s,"Mean comparison"),V2=pc_view(other,"Distribution and ANOVA"))
book<-list(D1=pc_sheet(tab,other,"Treatment study",views,"V2"))
check(nrow(pc_view_catalog(book))==2,"two analyses and graphs share one source table")
ls<-pc_layout_defaults();ls$selected<-c("D1:V1","D1:V2")
p<-pc_project(tab,other,book,"D1",ls);pc_write_project(p,"artifacts/views/linked.rdatacraft");loaded<-pc_load_project("artifacts/views/linked.rdatacraft")
check(loaded$worksheets$D1$active_view=="V2" && length(loaded$worksheets$D1$views)==2,"linked views and active view round-trip through schema 3")
check(loaded$worksheets$D1$views$V1$settings$method=="welch" && loaded$worksheets$D1$views$V2$settings$method=="anova","different analyses persist without duplicating observations")
check(loaded$worksheets$D1$views$V2$settings$grid_lines && loaded$worksheets$D1$views$V2$settings$legend_position=="bottom","per-view formatting persists")
check(identical(loaded$figure_layout$selected,ls$selected),"layout panel references survive save and reopen")
plots<-pc_layout_plots(loaded$worksheets,ls$selected)
check(length(plots)==2 && all(vapply(plots,inherits,logical(1),"ggplot")),"layout resolves both linked graphs from shared source observations")
changed<-loaded$worksheets;modified<-pc_read_text(changed$D1$data_tsv,"\t");modified[1,1]<-"35";changed$D1$data_tsv<-pc_table_text(modified)
updated<-pc_layout_plots(changed,ls$selected)
check(plots[[1]]$data$value[1]!=updated[[1]]$data$value[1] && updated[[2]]$data$value[1]==35,"source edits propagate to every saved graph view")
check(errors(pc_layout_plots(book,c("D99:V1"))),"missing layout references fail explicitly")
invalid<-p;invalid$figure_layout$selected<-"D1:V99"
check(errors(pc_decode_project(invalid)),"saved layouts cannot reference nonexistent views")
invalid<-p;invalid$worksheets$D1$views$V2$settings$layout<-"xy"
check(errors(pc_decode_project(invalid)),"views with incompatible table types are rejected")
check(errors(pc_layout_settings(list(selected=paste0("D1:V",1:9)))),"layout panel count is bounded")
check(errors(pc_layout_settings(list(columns=4))),"unsupported layout column counts rejected")
assembled <- pc_layout_grob(plots,2,"Treatment study")
check(sum(grepl("^panel-",assembled$layout$name))==2 && all(assembled$layout$l[grepl("^panel-",assembled$layout$name)]==1:2),"layout allocates both panel columns independently")
for(fmt in c("svg","pdf","png")){
 file<-paste0("artifacts/views/layout.",fmt)
 ggplot2::ggsave(file,pc_layout_grob(plots,2,"Treatment study"),device=switch(fmt,svg=svglite::svglite,pdf=pc_pdf_device,png=pc_png_device),width=180,height=100,units="mm",dpi=150,bg="white")
 check(file.info(file)$size>1000,paste("two-panel layout exports as",fmt))
}
svg <- paste(readLines("artifacts/views/layout.svg"),collapse="\n")
check(all(vapply(c("Treatment response", "Distribution view", ">A</text>", ">B</text>"), function(label) grepl(label,svg,fixed=TRUE),logical(1))),"SVG contains both panel tags and both graph titles")
xy<-pc_normalize(data.frame(X=1:6,Y=c(2,4,5,8,9,13)),"xy");sx<-s;sx$layout<-"xy";sx$graph<-"scatter";sx$method<-"linear";sx$group1<-"Y"
a<-pc_analyze(xy,"linear","Y");sx$x_min<-"2";sx$x_max<-"4";sx$y_min<-"0";sx$y_max<-"15"
plot<-pc_plot(xy,sx,a);built<-ggplot2::ggplot_build(plot)
check(nrow(plot$data)==6 && a$n==6,"axis cropping preserves all data used for regression")
check(all(as.numeric(plot$coordinates$limits$x)==c(2,4)),"manual X limits reach the coordinate system")
check(all(as.numeric(plot$coordinates$limits$y)==c(0,15)),"manual Y limits reach the coordinate system")
sx$x_min<-"5";sx$x_max<-"2";check(errors(pc_plot(xy,sx,a)),"reversed axis ranges rejected")
sx$x_min<-"garbage";check(errors(pc_plot(xy,sx,a)),"nonnumeric axis limits rejected")
sx$x_min<-"0";sx$x_max<-"5";sx$log_x<-TRUE;check(errors(pc_plot(xy,sx,a)),"log axes reject nonpositive manual limits")
sx<-s;sx$x_min<-"1";check(errors(pc_plot(pc_normalize(tab),sx,pc_analyze(pc_normalize(tab),"welch",s$group1,s$group2))),"numeric X limits cannot shift category positions")
sx<-s;sx$y_min<-"0";sx$y_max<-"30"
proj<-pc_project(tab,sx);pc_write_project(proj,"artifacts/views/axes.rdatacraft")
check(pc_load_project("artifacts/views/axes.rdatacraft")$settings$y_max=="30","axis limits persist in project settings")
legacy<-jsonlite::read_json("artifacts/tests/project.json",simplifyVector=FALSE);legacy$schema_version<-1L;legacy$worksheets<-NULL
check(pc_decode_project(legacy)$figure_layout$columns==2,"legacy projects gain safe layout defaults")
cat("\n",checks," linked-view, axis, and layout checks passed.\n",sep="")
