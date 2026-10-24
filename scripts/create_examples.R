# Original demonstration data and presentations; no GraphPad examples are copied.
source("R/data.R");source("R/analysis.R");source("R/plot.R");source("R/project.R")
book<-list()
for(layout in unname(pc_layouts())){
 e<-pc_example(layout);n<-pc_normalize(e$table,layout);s<-pc_defaults()
 s$layout<-layout;s$method<-e$method;s$graph<-unname(pc_graphs(layout))[1]
 s$title<-e$title;s$x_label<-e$x_label;s$y_label<-e$y_label
 s$group1<-n$groups[1];s$group2<-n$groups[min(2,length(n$groups))]
 name<-switch(layout,column="Treatment groups",xy="Time course",grouped="Two-factor experiment",contingency="Categorical outcomes",survival="Survival study")
 book[[paste0("D",length(book)+1)]]<-pc_sheet(e$table,s,name)
}
tab<-pc_read_text(paste(readLines("examples/dose-response.csv"),collapse="\n"));s<-pc_defaults()
s$layout<-"xy";s$method<-"fourpl";s$graph<-"scatter";s$log_x<-TRUE;s$title<-"Dose-response curve";s$x_label<-"Concentration";s$y_label<-"Response";s$group1<-"Response";s$group2<-"Response"
book$D6<-pc_sheet(tab,s,"Dose response")
s<-book$D1$settings;s$method<-"anova";s$graph<-"box";s$title<-"Distribution and ANOVA";book$D1$views$V2<-pc_view(s,"Distribution and ANOVA")
s<-book$D3$settings;s$graph<-"interaction";s$title<-"Treatment × time";book$D3$views$V2<-pc_view(s,"Interaction plot")
layout<-pc_layout_defaults();layout$selected<-c("D1:V1","D3:V2","D5:V1","D6:V1");layout$title<-"Experimental analyses";layout$height<-190
first<-book$D1
pc_write_project(pc_project(pc_read_text(first$data_tsv,"\t"),first$settings,book,"D1",layout),"examples/RDataCraft examples.rdatacraft")
stopifnot(length(pc_load_project("examples/RDataCraft examples.rdatacraft")$worksheets)==6)
cat("Created six worksheets, eight linked views, and a four-panel example layout.\n")
