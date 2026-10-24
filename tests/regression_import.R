app<-source("app.R")$value;checks<-0L
check<-function(ok,label) {if(!isTRUE(ok)) stop("FAIL: ",label,call.=FALSE);checks<<-checks+1L;cat("PASS:",label,"\n")}
errors<-function(expr) inherits(tryCatch(force(expr),error=identity),"error")
x<-seq(.2,8,length.out=30)
for(method in unname(pc_regression_methods())) {
  truth<-switch(method,origin=2*x,quadratic=1+2*x+.3*x^2,cubic=1+x+.2*x^2+.01*x^3,logarithmic=2+3*log(x),power=2*x^.8,exponential=2*exp(.2*x),decay=1+5*exp(-.4*x),association=8-5*exp(-.4*x),michaelis=8*x/(2+x),gaussian=1+4*exp(-.5*((x-4)/1.2)^2))
  y<-truth+.01*sin(seq_along(x));n<-pc_normalize(data.frame(X=x,Y=y),"xy");s<-pc_defaults();s$layout<-"xy";s$method<-method;s$graph<-"scatter";s$group1<-"Y"
  r<-pc_analyze(n,method,"Y",options=s)
  check(max(abs(r$diagnostics$fitted-truth))<.03,paste(method,"recovers the known curve within observation noise"))
  check(all(is.finite(r$parameters$ci_low)) && all(r$parameters$ci_low<=r$parameters$estimate) && all(r$parameters$ci_high>=r$parameters$estimate),paste(method,"reports finite ordered parameter intervals"))
  check(inherits(ggplot2::ggplot_build(pc_plot(n,s,r)),"ggplot_built"),paste(method,"renders a fitted curve"))
  s$graph<-"residual";check(inherits(pc_plot(n,s,r),"ggplot"),paste(method,"provides a residual graph"))
}
n<-pc_normalize(data.frame(X=1:8,Y=c(2.1,3.8,6.2,7.9,10.2,12,14.1,16)),"xy")
r<-pc_analyze(n,"origin","Y",options=pc_defaults());slope<-sum(n$data$x*n$data$value)/sum(n$data$x^2)
check(abs(r$parameters$estimate[1]-slope)<1e-10,"through-origin slope matches the closed-form least-squares benchmark")
s<-pc_defaults();s$fit_weight<-"inv_y2";r<-pc_analyze(n,"linear","Y",options=s)
w<-1/n$data$value^2;design<-cbind(1,n$data$x);expected<-solve(crossprod(design,w*design),crossprod(design,w*n$data$value))
check(max(abs(r$parameters$estimate-as.vector(expected)))<1e-10,"weighted line matches the normal-equation benchmark")
tab<-pc_xy_replicates(data.frame(X=1:8,Y=2*(1:8)),3);tab[[3]]<-2*(1:8)+1;tab[[4]]<-2*(1:8)-1
n<-pc_normalize(tab,"xy");s$fit_weight<-"replicate_sd";s$fit_replicates<-"mean";r<-pc_analyze(n,"linear","Y",options=s)
check(nrow(r$diagnostics)==8 && r$n==8 && max(abs(r$diagnostics$fitted-2*(1:8)))<1e-8,"mean and replicate-SD fitting uses X-level means with their precision weights")
check(errors(pc_analyze(pc_normalize(data.frame(X=1:6,Y=1:6),"xy"),"linear","Y",options=s)),"SD weighting rejects unavailable replicate variance")
s$fit_weight<-"inv_y2";check(errors(pc_analyze(pc_normalize(data.frame(X=1:6,Y=0:5),"xy"),"linear","Y",options=s)),"inverse-Y-squared weighting rejects zero observations")
check(errors(pc_analyze(pc_normalize(data.frame(X=0:6,Y=1:7),"xy"),"power","Y")),"power models reject nonpositive X")
xx<-10^seq(-2,2,length.out=16);yy<-1+8*plogis(2*(log10(xx)-.2))+.01*sin(seq_along(xx))
s<-pc_defaults();s$fit_weight<-"inv_y2";r<-pc_analyze(pc_normalize(data.frame(X=xx,Y=yy),"xy"),"fourpl","Y",options=s)
check(abs(r$parameters$estimate[r$parameters$parameter=="logEC50"]-.2)<.02 && all(r$diagnostics$weight>0),"weighted four-parameter regression recovers a known midpoint and exposes its weights")
for(ext in c("pzfx","prism")) {
  p<-pc_prism_import(paste0("tests/fixtures/source-tables.",ext))
  check(length(p$tables)==2 && length(p$skipped)==1,paste(ext,"imports supported tables and reports unsupported summary data"))
  first<-p$tables[[1]]
  check(first$layout=="xy" && pc_normalize(first$table,"xy")$replicates==if(ext=="pzfx") 3 else 2,paste(ext,"preserves side-by-side replicate grouping"))
  if(ext=="pzfx") check(is.na(first$table[3,4]) && !any(first$table=="999",na.rm=TRUE),"PZFX excluded values stay missing")
  if(ext=="prism") check(p$tables[[2]]$layout=="grouped" && nrow(p$tables[[2]]$table)==4,"modern grouped import preserves both factors and replicate subcolumns")
}
check(errors(pc_prism_import("tests/fixtures/unsafe-source.prism")),"ZIP path traversal is rejected without extraction")
check(errors(pc_prism_import("tests/fixtures/unsafe-source.pzfx")),"XML external entities are rejected")
check(errors(pc_prism_import("tests/fixtures/source-tables.prism",name="old.pzf")),"binary PZF import provides an explicit conversion requirement")
check(!pc_prism_exclusions(list(title="Excluded group",attributes=list("NUMERIC"))),"a dataset title containing excluded is not treated as an exclusion flag")
check(pc_prism_exclusions(list(attributes=list("EXCLUDED"))) && !pc_prism_exclusions(list(isExcluded=FALSE)),"actual exclusion flags are distinguished from disabled flags")
cd<-pc_prism_import("tests/fixtures/cdata-source.pzfx")$tables[[1]]
check(cd$name=="CDATA & labels" && names(cd$table)[1]=="Control & alpha" && cd$table[1,1]=="1","XML CDATA preserves labels and observations")
t<-pc_prism_table("","xy",x=1:3,ys=list(list(name="Control\nA",subcolumns=list(1:3,2:4))))
check(t$name=="Imported table" && identical(pc_xy_structure(t$table)$groups,"Control A"),"blank table titles and multiline dataset labels import without losing replicate grouping")
multi<-pc_xy_replicates(data.frame(X=1:3,check.names=FALSE,"Control\nA"=1:3),2)
check(pc_normalize(multi,"xy")$replicates==2 && length(pc_normalize(multi,"xy")$groups)==1,"multiline XY series headers remain a single replicated series")
shiny::testServer(app,{
  # Explicit fixture: production startup is intentionally empty.
  raw(pc_example("column")$table);sheet_name("Treatment groups");project_name("Example study");document_open(TRUE)
 do.call(session$setInputs,pc_defaults());session$flushReact();before<-workbook()$D1$data_tsv
 session$setInputs(desktop_import_prism=list(path=normalizePath("tests/fixtures/source-tables.prism"),nonce=1));session$flushReact()
 check(length(prism_staging()$tables)==2 && length(workbook())==1,"Prism preview stages source tables before committing")
 session$setInputs(prism_all=TRUE,prism_table="1",confirm_prism_import=1);session$flushReact()
 target<-restoring_settings();if(!is.null(target)) do.call(session$setInputs,target);session$flushReact()
 check(length(workbook())==3 && workbook()$D1$data_tsv==before,"import adds source tables while preserving the existing study")
 check(workbook()$D2$settings$method=="descriptive" && workbook()$D3$settings$method=="descriptive","import never presents Prism's saved analyses as recomputed R results")
 check(pc_normalize(pc_read_text(workbook()$D2$data_tsv),"xy")$replicates==2,"replicate structure survives the importer server workflow")
})
cat(checks,"regression and import checks passed.\n")
