source("R/data.R");source("R/analysis.R");source("R/plot.R");source("R/project.R")
checks <- 0L
check <- function(ok,label) {if(!isTRUE(ok))stop("FAIL: ",label,call.=FALSE);checks<<-checks+1L;cat("PASS:",label,"\n")}
dir.create("artifacts/style",recursive=TRUE,showWarnings=FALSE)
check(!requireNamespace("ggprism",quietly=TRUE),"graphs are tested with ggprism absent from R libraries")
default<-pc_defaults()
check(default$width==76.2 && default$height==76.2 && default$font_size==7,"new graphs use a three-inch square and seven-point text")
tab<-data.frame(A=c(2,4,7,8),Empty=rep(NA_real_,4),"Drug-C"=c(8,11,13,16),check.names=FALSE)
n<-pc_normalize(tab);s<-pc_defaults();s$group1<-"A";s$group2<-"Drug-C"
a<-pc_analyze(n,"welch",s$group1,s$group2)
p<-pc_plot(n,s,a);b<-ggplot2::ggplot_build(p)
check(p$theme$axis.text$size==7 && p$theme$axis.title$size==7 && p$theme$plot.title$size==7 && p$theme$legend.text$size==7,"default title, axes and legend render at seven points")
vector_file<-'artifacts/style/default-three-inch.svg'
ggplot2::ggsave(vector_file,p,device=svglite::svglite,width=s$width,height=s$height,units='mm')
svg<-paste(readLines(vector_file,warn=FALSE),collapse='\n')
check(grepl("width='216.00pt'",svg,fixed=TRUE) && grepl("height='216.00pt'",svg,fixed=TRUE) && grepl('font-size: 7.00px',svg,fixed=TRUE),"default vector export keeps three-inch dimensions and seven-point text")
check(pc_decode_project(pc_project(tab,s))$settings$font_size==7,"seven-point figures save and reopen")
legacy_size<-modifyList(s,list(width=152.4,height=114.3,font_size=13))
restored<-pc_decode_project(pc_project(tab,legacy_size))$settings
check(restored$width==152.4 && restored$height==114.3 && restored$font_size==13,"previously saved figure sizes remain intact")
segment<-which(vapply(p$layers,function(x)inherits(x$geom,"GeomSegment"),logical(1)))
text<-which(vapply(p$layers,function(x)inherits(x$geom,"GeomText"),logical(1)))
check(length(segment)==1 && nrow(b$data[[segment]])==3,"one comparison has a horizontal bracket and two tips")
z<-b$data[[segment]]
check(z$x[1]==1 && z$xend[1]==3,"bracket endpoints preserve positions across an empty middle group")
check(identical(b$layout$panel_params[[1]]$x$get_labels(),c("A","Empty","Drug-C")),"empty group labels remain aligned with source columns")
check(length(text)==1 && grepl("p =|p <",b$data[[text]]$label),"exact P-value label renders from the analysis result")
check(all(z$yend[2:3]<z$y[2:3]),"bracket tips point toward the observations")
s$annotation<-"stars";ps<-pc_plot(n,s,a);bs<-ggplot2::ggplot_build(ps)
check(identical(bs$data[[text]]$label,pc_stars(a$p)),"star labels match significance thresholds")
s$show_p<-FALSE;plain<-pc_plot(n,s,a)
check(!any(vapply(plain$layers,function(x)inherits(x$geom,"GeomSegment"),logical(1))),"disabling comparison annotations removes the bracket layers")
s$show_p<-TRUE;s$log_y<-TRUE;logged<-pc_plot(n,s,a)
check(!any(vapply(logged$layers,function(x)inherits(x$geom,"GeomSegment"),logical(1))),"log axes retain the existing policy of hiding significance brackets")
r<-pc_normalize(data.frame("Control-A"=c(1,3,5,6),"Drug-B"=c(6,8,12,15),"Drug-C"=c(7,10,14,18),check.names=FALSE))
s<-pc_defaults();s$method<-"anova";s$group1<-"Control-A";s$group2<-"Drug-B"
a<-pc_analyze(r,"anova",s$group1,s$group2);p<-pc_plot(r,s,a);b<-ggplot2::ggplot_build(p)
text<-which(vapply(p$layers,function(x)inherits(x$geom,"GeomText"),logical(1)))
check(nrow(b$data[[text]])==3 && all(grepl("adj. p",b$data[[text]]$label,fixed=TRUE)),"Tukey annotations preserve all adjusted comparisons and hyphenated names")
check(all(diff(sort(b$data[[text]]$y))>0),"multiple comparisons occupy separate bracket heights")
check(inherits(tryCatch(pc_comparison_layers(data.frame(group1="Wrong",group2="Drug-B",p=.1,label="p=.1",y.position=20),r$groups,10),error=identity),"error"),"unknown bracket groups fail explicitly")
check(length(pc_comparison_layers(data.frame(group1="Control-A",group2="Drug-B",p=NA_real_,label=NA_character_,y.position=20),r$groups,10))==0,"undefined comparisons do not draw misleading labels")
for(fmt in c("svg","pdf","png")) {
 file<-paste0("artifacts/style/comparisons.",fmt)
 ggplot2::ggsave(file,p,device=switch(fmt,svg=svglite::svglite,pdf=pc_pdf_device,png=pc_png_device),width=160,height=120,units="mm",dpi=150)
 check(file.info(file)$size>1000,paste("original styling and annotations export as",fmt))
}
check(!"ggprism" %in% read.csv("dependencies.csv")$package,"dependency inventory excludes the retired package")
check(!"ggprism" %in% names(pc_project(tab,s)$environment$packages),"new projects no longer query ggprism versions")
legacy<-jsonlite::read_json("examples/RDataCraft examples.rdatacraft",simplifyVector=FALSE)
legacy$environment$packages$ggprism<-"1.0.7.9000"
check(length(pc_decode_project(legacy)$worksheets)==6,"older projects recording ggprism still open without the package")
cat("\n",checks," styling and dependency checks passed.\n",sep="")
