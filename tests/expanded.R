source("R/data.R"); source("R/analysis.R"); source("R/plot.R"); source("R/project.R"); source("R/report.R")
checks <- 0L
check <- function(ok, label) {if (!isTRUE(ok)) stop("FAIL: ", label, call. = FALSE); checks <<- checks + 1L; cat("PASS:", label, "\n")}
near <- function(x,y,tol=1e-7) isTRUE(all.equal(as.numeric(x), as.numeric(y), tolerance=tol))
errors <- function(expr) inherits(tryCatch(force(expr),error=identity),"error")
dir.create("artifacts/expanded",recursive=TRUE,showWarnings=FALSE)
# Analytic 2x2 balanced factorial benchmark: independent cell offsets -0.1,0,+0.1.
g <- data.frame(Time=c("Early","Early","Late","Late"), Treatment=c("Control","Drug","Control","Drug"), R1=c(.9,1.9,1.9,5.9),R2=c(1,2,2,6),R3=c(1.1,2.1,2.1,6.1))
n <- pc_normalize(g,"grouped"); a <- pc_analyze(n,"twoway","Control","Drug")
check(near(a$effects$F[1:3],c(1875,1875,675)),"factorial F statistics match hand-computed sums of squares")
check(near(a$effects$sum_squares,c(18.75,18.75,6.75,.08)),"factorial sums of squares and residual variation")
g_missing <- g;g_missing[1,3] <- NA
check(errors(pc_analyze(pc_normalize(g_missing,"grouped"),"twoway")),"unbalanced factorial designs cannot silently use balanced ANOVA")
a <- pc_analyze(n,"simpleeffects","Control","Drug")
check(nrow(a$comparisons)==2 && all(a$comparisons$p>=a$comparisons$p_raw),"grouped comparisons correct the full family")
check(near(a$comparisons$estimate,c(-1,-4)),"within-level comparisons preserve factor direction")
check(errors(pc_normalize(data.frame(A=NA,B="Drug",Y=1),"grouped")),"replicates with missing factor labels rejected")
# Classic Fisher exact example from R's published help (lady tasting tea / small tables).
cnt <- data.frame(Outcome=c("Yes","No"),A=c(1,9),B=c(11,3))
nc <- pc_normalize(cnt,"contingency");f <- pc_analyze(nc,"fisher")
check(near(f$p,.00275945618522008),"Fisher exact fixed 2x2 benchmark")
chi <- pc_analyze(nc,"chisquare")
check(near(chi$p,stats::pchisq(10.9714285714286,1,lower.tail=FALSE)),"uncorrected Pearson chi-square benchmark")
sparse <- pc_analyze(pc_normalize(data.frame(C=c("A","B"),X=c(1,9),Y=c(1,3)),"contingency"),"chisquare")
check(any(grepl("below 5",sparse$notes)),"sparse expected counts warn about approximation")
check(errors(pc_normalize(data.frame(C=c("A","B"),X=c(1.2,2),Y=c(3,4)),"contingency")),"fractional contingency counts rejected")
check(errors(pc_normalize(data.frame(C=c("A","B"),X=c(NA,2),Y=c(3,4)),"contingency")),"missing counts are not converted to observed zeros")
check(errors(pc_analyze(pc_normalize(data.frame(C=c("A","B"),X=c(0,0),Y=c(3,4)),"contingency"),"fisher")),"empty contingency margins rejected for inference")
# Kaplan-Meier product limit estimates: S(1)=3/4; censor at 2; S(3)=3/8.
surv <- data.frame(Time=c(1,2,3,4),Status=c(1,0,1,0),Group="A")
ns <- pc_normalize(surv,"survival");km <- pc_analyze(ns,"kaplan")
check(near(km$survival_fit$surv,c(.75,.75,.375,.375)),"Kaplan-Meier known product-limit estimates")
check(km$summary$median==3,"Kaplan-Meier median comes from survival crossing one half")
check(errors(pc_normalize(data.frame(Time=1,Status=2,Group="A"),"survival")),"invalid event status rejected")
check(errors(pc_normalize(data.frame(Time=NA,Status=0,Group="A"),"survival")),"incomplete survival subjects rejected")
check(errors(pc_analyze(ns,"logrank")),"log-rank needs multiple groups")
# Published survival::lung dataset (NA survival group rows removed explicitly).
lung <- survival::lung; lung <- lung[!is.na(lung$sex),]
nl <- pc_normalize(data.frame(Time=lung$time,Status=as.integer(lung$status==2),Group=lung$sex),"survival")
lr <- pc_analyze(nl,"logrank")
check(near(lr$p,.001311164,1e-6),"lung survival published log-rank benchmark by sex")
# Matched sleep study: two-level RM ANOVA equals paired t squared.
sleep <- datasets::sleep;wide <- data.frame(A=sleep$extra[1:10],B=sleep$extra[11:20]);nn <- pc_normalize(wide)
rm <- pc_analyze(nn,"rm_anova","A","B")
check(near(rm$p,.00283289019738427),"two-level repeated-measures ANOVA matches sleep paired benchmark")
fr <- pc_analyze(pc_normalize(data.frame(A=1:5,B=2:6,C=3:7)),"friedman","A","B")
check(near(fr$p,exp(-5)),"Friedman analytic chi-square benchmark")
wide$A[2] <- NA;rm <- pc_analyze(pc_normalize(wide),"rm_anova","A","B")
check(rm$metrics$value[rm$metrics$measure=="Complete subjects"]=="9","RM ANOVA excludes whole incomplete subjects")
pg <- datasets::PlantGrowth;nn <- pc_normalize(as.data.frame(split(pg$weight,pg$group)))
kw <- pc_analyze(nn,"kruskal","ctrl","trt1",list(correction="holm"))
check(near(kw$p,.01842375573),"PlantGrowth Kruskal-Wallis fixed benchmark")
check(nrow(kw$comparisons)==3 && all(kw$comparisons$p>=kw$comparisons$p_raw),"rank comparisons include all pairs and adjusted P values")
wa <- pc_analyze(nn,"welchanova","ctrl","trt1")
check(near(wa$p,.01739282149017,1e-7),"PlantGrowth Welch ANOVA fixed benchmark")
mult <- pc_analyze(nn,"multiple","ctrl","trt1",list(correction="BH"))
check(nrow(mult$comparisons)==3 && all(is.finite(mult$comparisons$ci_low)),"multiple Welch comparisons include interval estimates")
check(all(pc_stars(c(.00001,.0005,.005,.03,.2))==c("****","***","**","*","ns")),"significance thresholds are explicit")
st <- pc_analyze(pc_normalize(data.frame(A=c(1,2,4,5),B=c(4,5,7,8))),"student","A","B")
check(near(st$p,stats::t.test(c(1,2,4,5),c(4,5,7,8),var.equal=TRUE)$p.value),"Student equal-variance comparison")
one <- pc_analyze(pc_normalize(data.frame(A=c(1,2,3))),"onesample","A",options=list(null_mean=2))
check(near(one$p,1),"one-sample null mean setting")
sr <- pc_analyze(pc_normalize(data.frame(A=c(1,NA,4,6,8),B=c(2,3,5,8,9))),"signedrank","A","B")
check(sr$metrics$value[sr$metrics$measure=="Complete pairs"]=="4","signed-rank pairs match source row identity")
normal <- pc_analyze(nn,"normality","ctrl")
check(all(normal$summary$status=="Tested"),"normality analysis produces group diagnostic results")
# Correlation and AUC have analytic answers; duplicate X values average before integration.
xy <- pc_normalize(data.frame(X=c(0,1,1,2),Y=c(0,1,3,4)),"xy")
auc <- pc_analyze(xy,"auc","Y")
check(near(auc$summary$auc,4),"trapezoidal integration averages duplicate X observations")
cor <- pc_analyze(pc_normalize(data.frame(X=1:6,Y=c(1,3,2,4,6,5)),"xy"),"spearman","Y")
check(near(as.numeric(cor$metrics$value[cor$metrics$measure=="Spearman rho"]),.885714285714286),"Spearman fixed rank-correlation benchmark")
# Independently generated log-logistic data with known EC50=10, baseline=5, top=105.
xx <- 10^seq(-2,4,length.out=20); yy <- 5+100/(1+(10/xx)^1.2)+rep(c(-.3,.3),10)
ndose <- pc_normalize(data.frame(Concentration=xx,Response=yy),"xy");dose <- pc_analyze(ndose,"fourpl","Response")
mid <- as.numeric(dose$metrics$value[grepl("^EC50 / IC50 \\(half",dose$metrics$measure)])
check(abs(mid-10)<.2,"4PL recovers known EC50 from noisy generated observations")
check(max(abs(dose$diagnostics$residual))<1,"4PL residuals recover the generating curve")
check(nrow(dose$parameters)==4 && all(is.finite(dose$parameters$se)),"4PL estimates uncertainty for all four parameters")
ndec <- pc_normalize(data.frame(Concentration=xx,Response=110-yy),"xy");dec <- pc_analyze(ndec,"fourpl","Response")
check(dec$parameters$estimate[dec$parameters$parameter=="hill"]<0,"4PL supports inhibitory dose response")
check(errors(pc_analyze(pc_normalize(data.frame(X=0:6,Y=1:7),"xy"),"fourpl","Y")),"dose-response fitting rejects zero and log-transformed concentrations")
# Derived tables preserve source data and blanks.
tab <- data.frame(Control=c(1,2,3),Drug=c(2,4,NA));tr <- pc_transform(tab,"column","percent_control","Control")
check(near(as.numeric(tr$Control),c(50,100,150)) && is.na(tr$Drug[3]),"percent-of-control transform preserves missing observations")
check(identical(tab$Control,c(1,2,3)),"transforms leave source observations intact")
check(errors(pc_transform(data.frame(A=c(0,1)),"column","log10")),"invalid logarithmic transforms rejected before mutation")
# Round-trip a workbook with dissimilar data types and per-sheet graph/analysis settings.
book <- list();for (layout in unname(pc_layouts())) {e<-pc_example(layout);ss<-pc_defaults();ss$layout<-layout;ss$method<-e$method;ss$graph<-unname(pc_graphs(layout))[1];z<-pc_normalize(e$table,layout);ss$group1<-z$groups[1];ss$group2<-z$groups[min(2,length(z$groups))];book[[paste0("D",length(book)+1)]]<-pc_sheet(e$table,ss,layout)}
current <- book$D5;proj<-pc_project(pc_read_text(current$data_tsv,"\t"),current$settings,book,"D5")
jsonlite::write_json(proj,"artifacts/expanded/workbook.rdatacraft",auto_unbox=TRUE,pretty=TRUE,na="null",digits=15)
opened<-pc_load_project("artifacts/expanded/workbook.rdatacraft")
check(length(opened$worksheets)==length(pc_layouts()) && opened$active=="D5","all supported table types restore named worksheets and active table")
check(identical(opened$worksheets$D3$settings$method,"twoway"),"inactive worksheet analysis choices survive save and reopen")
legacy<-pc_project(pc_example("column")$table,pc_defaults());legacy$format<-"plotcraft";legacy$app_version<-"0.2.0";legacy$settings$correction<-NULL;legacy$settings$null_mean<-NULL;legacy$settings$annotation<-NULL
check(pc_decode_project(legacy)$settings$correction=="holm","old PlotCraft project opens with compatible defaults")
check(pc_project_name("/tmp/old.plotcraft.json")=="old","legacy file extension keeps the correct study name")
# Render every new graph using actual vector/raster devices.
for (layout in unname(pc_layouts())) {
 e<-pc_example(layout);n<-pc_normalize(e$table,layout);ss<-pc_defaults();ss$layout<-layout;ss$method<-e$method;ss$group1<-n$groups[1];ss$group2<-n$groups[min(2,length(n$groups))];ss$x_label<-e$x_label;ss$y_label<-e$y_label;ss$title<-e$title
 a<-pc_analyze(n,ss$method,ss$group1,ss$group2)
 for (graph in unname(pc_graphs(layout))) {
  ss$graph<-graph;file<-paste0("artifacts/expanded/",layout,"-",graph,".svg")
  plot_n <- n
  if (graph=="xyband") {replicated <- pc_xy_replicates(e$table,2); for(j in seq(3,ncol(replicated),by=2)) replicated[[j]] <- as.numeric(replicated[[j-1]])+.1; plot_n <- pc_normalize(replicated,"xy")}
  ggplot2::ggsave(file,pc_plot(plot_n,ss,a),width=180,height=130,units="mm")
  check(file.info(file)$size>1000,paste(layout,graph,"graph exports"))
 }
 writeLines(pc_report(a,e$table,ss),paste0("artifacts/expanded/",layout,"-report.html"))
 check(is.list(pc_public_result(a)),paste(layout,"result serializes without fitted objects"))
 jsonlite::write_json(pc_public_result(a),paste0("artifacts/expanded/",layout,"-result.json"),auto_unbox=TRUE,na="null")
}
ss<-pc_defaults();ss$layout<-"xy";ss$graph<-"scatter";ss$method<-"fourpl";ss$group1<-"Response";ss$log_x<-TRUE;ss$title<-"Dose-response fit";ss$x_label<-"Concentration";ss$y_label<-"Response"
ggplot2::ggsave("artifacts/expanded/dose-response.png",device=pc_png_device,pc_plot(ndose,ss,dose),width=180,height=130,units="mm",dpi=150)
check(file.info("artifacts/expanded/dose-response.png")$size>1000,"nonlinear fit renders on a logarithmic X axis")
report<-pc_report(dose,data.frame(X=xx,Y=yy),ss)
check(grepl("Fit parameters",report,fixed=TRUE) && !grepl("<script>",pc_report(dose,data.frame(X="<script>",Y=1),ss),fixed=TRUE),"analysis report includes parameter tables and escapes imported content")
cat("\n",checks," expanded checks passed.\n",sep="")
