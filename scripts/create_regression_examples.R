# Original, deterministic illustrative data for inspecting model families.
source("R/data.R");source("R/analysis.R");source("R/plot.R");source("R/project.R")
x<-seq(.2,8,length.out=30);noise<-.04*sin(seq_along(x));book<-list()
models<-c(Linear="linear",Quadratic="quadratic",Exponential="exponential",`One-phase decay`="decay",`One-phase association`="association",`Michaelis–Menten`="michaelis",`Gaussian peak`="gaussian",Power="power")
for(label in names(models)) {
 method<-models[[label]]
 y<-switch(method,linear=1+2*x,quadratic=1+2*x+.3*x^2,exponential=2*exp(.2*x),decay=1+5*exp(-.4*x),association=8-5*exp(-.4*x),michaelis=8*x/(2+x),gaussian=1+4*exp(-.5*((x-4)/1.2)^2),power=2*x^.8)+noise
 tab<-pc_check_table(data.frame(X=x,Response=y));s<-pc_defaults();s$layout<-"xy";s$graph<-"scatter";s$method<-method;s$group1<-"Response";s$group2<-"Response";s$title<-paste(label,"fit");s$x_label<-"X";s$y_label<-"Response"
 pc_analyze(pc_normalize(tab,"xy"),method,"Response",options=s)
 book[[paste0("D",length(book)+1L)]]<-pc_sheet(tab,s,label)
}
first<-book$D1
pc_write_project(pc_project(pc_read_text(first$data_tsv),first$settings,book,study_name="Regression model gallery"),"examples/Regression model gallery.rdatacraft")
stopifnot(length(pc_load_project("examples/Regression model gallery.rdatacraft")$worksheets)==8)
cat("Created eight original regression examples.\n")
