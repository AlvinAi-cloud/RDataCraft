# Observed-replicate comparisons at matching X values, independent of curve fits.
pc_xy_comparisons <- function(n,s) {
  if(n$layout!="xy" || !isTRUE(s$xy_compare)) return(NULL)
  groups<-c(s$xy_compare_group1,s$xy_compare_group2)
  for(i in 1:2) if(!nzchar(groups[i])) groups[i]<-if(length(n$groups)>=i) n$groups[i] else ""
  if(any(!groups %in% n$groups) || groups[1]==groups[2]) stop("Choose two different existing Y series for X-value comparisons.",call.=FALSE)
  correction<-s$xy_compare_correction
  if(!correction %in% c("holm","bonferroni","none")) stop("Choose a supported X-value comparison correction.",call.=FALSE)
  d<-n$data[n$data$group %in% groups,,drop=FALSE]
  xs<-if(!is.null(n$x_values)) sort(unique(n$x_values[is.finite(n$x_values)])) else sort(unique(n$data$x))
  if(!length(xs)) stop("Enter observations for the selected Y series.",call.=FALSE)
  rows<-lapply(xs,function(x) {
    a<-d$value[d$x==x & d$group==groups[1]];b<-d$value[d$x==x & d$group==groups[2]]
    avg<-function(v) if(length(v)) mean(v) else NA_real_
    r<-data.frame(x=x,group1=groups[1],group2=groups[2],n1=length(a),n2=length(b),
      mean1=avg(a),mean2=avg(b),estimate=avg(a)-avg(b),ci_low=NA_real_,ci_high=NA_real_,
      statistic=NA_real_,df=NA_real_,p_raw=NA_real_,p=NA_real_,significance="",status="Not tested",detail="",stringsAsFactors=FALSE)
    if(min(length(a),length(b))<2L) {r$detail<-"Needs at least two observed replicates in each series at this X.";return(r)}
    test<-tryCatch(stats::t.test(a,b,paired=FALSE,var.equal=FALSE,alternative="two.sided",conf.level=.95),error=identity)
    if(inherits(test,"error")) {r$detail<-conditionMessage(test);return(r)}
    if(!is.finite(test$p.value)) {r$detail<-"A finite test result could not be estimated.";return(r)}
    r$ci_low<-test$conf.int[1];r$ci_high<-test$conf.int[2];r$statistic<-unname(test$statistic)
    r$df<-unname(test$parameter);r$p_raw<-test$p.value;r$status<-"Tested";r
  })
  tab<-do.call(rbind,rows);valid<-is.finite(tab$p_raw)
  # The family includes all selected X values, including unavailable tests.
  if(any(valid)) tab$p[valid]<-stats::p.adjust(tab$p_raw[valid],method=correction,n=nrow(tab))
  tab$significance<-pc_stars(tab$p);tab$correction<-correction;tab$family_size<-nrow(tab)
  label<-switch(correction,holm="Holm",bonferroni="Bonferroni",none="No correction")
  notes<-c(paste0(groups[1]," minus ",groups[2],": independent two-sided Welch t test at each matching X value, using observed replicates, not curve predictions or fitted means."),
    paste0(label," across a family of ",nrow(tab)," X values; ",sum(valid)," tests estimable. Unavailable tests remain in the correction family and have no P value or significance label."),
    "Difference confidence intervals are individual 95% intervals, not multiplicity-adjusted intervals. Significance labels use the displayed P values (adjusted when a correction is selected; P ≤ 0.05).",
    "Within each group, replicates must represent independent experimental units. These pointwise tests do not test differences between fitted curves or a treatment-by-time interaction. Matched/paired comparisons and longitudinal models require an appropriate Advanced R analysis.")
  list(table=tab,notes=notes,groups=groups,correction=correction,correction_label=label,family_size=nrow(tab),tested=sum(valid))
}

pc_xy_attach_comparisons <- function(analysis,result) {
  if(is.null(result)) return(analysis)
  if(is.null(analysis)) analysis<-list()
  analysis$xy_comparisons<-result$table
  analysis$xy_comparison_notes<-result$notes
  analysis
}

pc_xy_comparison_layers <- function(plot,n,s,result,analysis) {
  if(is.null(result) || !isTRUE(s$show_p) || s$graph=="residual") return(plot)
  ann<-result$table
  ann<-ann[is.finite(ann$p) & (!isTRUE(s$xy_compare_significant_only) | ann$p<=.05),,drop=FALSE]
  caption<-paste0(paste(result$groups,collapse=" vs ")," · Welch · ",result$correction_label," over ",result$family_size," X values")
  existing<-plot$labels$caption
  plot<-plot+ggplot2::labs(caption=paste(c(if(!is.null(existing)) existing,paste(strwrap(caption,width=58),collapse="\n")),collapse="\n"))
  if(!nrow(ann)) return(plot)
  span<-diff(range(n$data$value));if(!is.finite(span) || span==0) span<-max(abs(n$data$value),1)
  ann$y<-vapply(ann$x,function(x) {
    d<-n$data[n$data$x==x,,drop=FALSE];tops<-d$value
    for(g in unique(d$group)) {
      v<-d$value[d$group==g];k<-length(v)
      margin<-switch(s$error,sd=stats::sd(v),sem=stats::sd(v)/sqrt(k),ci=if(k>1) stats::qt(.975,k-1)*stats::sd(v)/sqrt(k) else 0,none=0)
      if(is.finite(margin)) tops<-c(tops,mean(v)+margin)
    }
    z<-analysis$diagnostics
    if(!is.null(z) && all(c("x","fitted") %in% names(z))) tops<-c(tops,z$fitted[z$x==x])
    top<-max(tops[is.finite(tops)])
    if(isTRUE(s$log_y)) top*10^max(.07,.06*diff(range(log10(n$data$value)))) else top+.07*span
  },numeric(1))
  ann$label<-pc_p_label(ann$p,if(result$correction=="none") "p" else "adj. p",identical(s$annotation,"stars"))
  plot+ggplot2::geom_text(data=ann,ggplot2::aes(x=x,y=y,label=label),inherit.aes=FALSE,
    color="#334550",size=s$font_size/ggplot2::.pt,vjust=0,show.legend=FALSE)
}

pc_xy_comparison_results_ui <- function(result) {
  if(is.null(result)) return(NULL)
  table<-result$table[,c("x","p","significance","p_raw","estimate","ci_low","ci_high","n1","n2","mean1","mean2","statistic","df","status","detail"),drop=FALSE]
  names(table)[names(table)=="x"]<-"X"
  names(table)[names(table)=="p"]<-if(result$correction=="none") "P value" else "Adjusted P value"
  names(table)[names(table)=="n1"]<-"First-series n"
  names(table)[names(table)=="n2"]<-"Second-series n"
  names(table)[names(table)=="mean1"]<-"First-series mean"
  names(table)[names(table)=="mean2"]<-"Second-series mean"
  names(table)[names(table)=="statistic"]<-"t statistic"
  names(table)[names(table)=="family_size"]<-"Family X values"
  shiny::div(class="xy-pointwise-results",shiny::h4("Comparisons at each X value"),shiny::tags$ul(lapply(result$notes,shiny::tags$li)),
    pc_result_table_ui(table,"Comparisons at each X value"))
}
