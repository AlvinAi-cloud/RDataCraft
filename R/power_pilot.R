# Read-only pilot estimates. Unsupported designs return summaries, never a
# misleading conversion to a different test. Complete pairs stay matched by row.
pc_power_pilot <- function(tab, settings, name="Active table", group1=NULL, group2=NULL, outcome=NULL) {
  layout<-settings$layout;tab<-pc_check_table(tab)
  n<-pc_normalize(tab,layout);d<-n$data
  rows<-list();add<-function(label,value) {rows[[length(rows)+1L]]<<-data.frame(Measure=label,Estimate=as.character(value),stringsAsFactors=FALSE)}
  fmt<-function(x) if(length(x)==1 && is.finite(x)) format(signif(x,6),trim=TRUE) else "Not estimable"
  add("Pilot worksheet",name);add("Table type",layout);add("Selected analysis",settings$method)
  add("Interpretation","Pilot estimates are uncertain; review and edit anticipated effects before planning a new study.")
  proposal<-NULL;note<-"This analysis needs a model-specific power calculation; manual planning remains available."
  first<-if(!is.null(group1)&&group1 %in% n$groups) group1 else if(settings$group1 %in% n$groups) settings$group1 else n$groups[1]
  second<-if(!is.null(group2)&&group2 %in% n$groups) group2 else if(settings$group2 %in% n$groups) settings$group2 else n$groups[min(2,length(n$groups))]
  if(layout=="column") {
    values<-lapply(n$groups,function(g)d$value[d$group==g]);names(values)<-n$groups
    for(g in n$groups) {v<-values[[g]];add(paste(g,"N / mean / SD"),paste(length(v),fmt(mean(v)),fmt(stats::sd(v)),sep=" / "))}
    method<-settings$method
    if((method=="anova" && length(values)>=2) || (method=="descriptive" && length(values)>2)) {
      counts<-lengths(values);means<-vapply(values,mean,numeric(1));vars<-vapply(values,stats::var,numeric(1))
      within<-sum((counts-1)*vars)/sum(counts-1)
      f<-sqrt(mean((means-mean(means))^2)/within)
      add("Pooled within-group SD",fmt(sqrt(within)));add("Cohen f (equal planned group weights)",fmt(f))
      if(all(counts>=2)&&is.finite(f)&&f>0) proposal<-list(design="anova",effect=f,groups=length(values),n=min(counts))
      note<-"Balanced ordinary one-way ANOVA planning. Pilot group sizes may differ; planned groups have equal N. Review common-variance and independent-unit assumptions."
    } else if(method=="onesample" || (method=="descriptive" && length(values)==1)) {
      a<-values[[first]];null<-settings$null_mean;if(is.null(null)||!is.finite(null)) null<-0
      effect<-abs(mean(a)-null)/stats::sd(a)
      add("Selected group",first);add("Reference mean",null);add("Standardized difference d",fmt(effect))
      if(length(a)>=2&&is.finite(effect)&&effect>0) proposal<-list(design="one.sample",effect=effect,n=length(a))
      note<-"One-mean planning relative to the stated reference mean. The observed difference is a candidate only; choose a meaningful future difference."
    } else if(length(values)>=2 && first!=second) {
      a<-values[[first]];b<-values[[second]]
      add("Selected comparison",paste(first,"versus",second))
      if(method %in% c("paired","signedrank")) {
        pair<-merge(d[d$group==first,c("row_id","value")],d[d$group==second,c("row_id","value")],by="row_id",suffixes=c(".a",".b"))
        diff<-pair$value.a-pair$value.b;effect<-abs(mean(diff))/stats::sd(diff)
        add("Complete matched pairs",length(diff));add("Incomplete rows excluded",nrow(tab)-length(diff))
        add("Mean within-pair difference",fmt(mean(diff)));add("SD of within-pair differences",fmt(stats::sd(diff)));add("Paired dz",fmt(effect))
        if(method=="paired" && length(diff)>=2&&is.finite(effect)&&effect>0) proposal<-list(design="paired",effect=effect,n=length(diff))
        note<-if(method=="signedrank") "Matched summaries are shown; signed-rank power is not approximated by a paired t test." else "N counts complete pairs, not two independent samples. Review the paired-difference effect before planning."
      } else {
        sd<-sqrt(((length(a)-1)*stats::var(a)+(length(b)-1)*stats::var(b))/(length(a)+length(b)-2));effect<-abs(mean(a)-mean(b))/sd
        add("Pooled SD",fmt(sd));add("Absolute mean difference",fmt(abs(mean(a)-mean(b))));add("Cohen d",fmt(effect))
        if(method %in% c("welch","student","descriptive") && length(a)>=2&&length(b)>=2&&is.finite(effect)&&effect>0) proposal<-list(design="two.sample",effect=effect,n=min(length(a),length(b)))
        note<-if(method %in% c("mann","kruskal")) "Distribution summaries are shown; rank-test power requires a distribution-specific design, not a t-test substitution." else "Pooled-SD planning assumes common variance and equal planned group sizes. This is not Welch-test power. Use a sensitivity range if variances or pilot effects are uncertain."
      }
    }
  } else if(layout=="contingency") {
    for(g in n$groups) add(paste(g,"total count"),sum(n$counts[,g]))
    if(nrow(n$counts)==2 && length(n$groups)>=2 && first!=second) {
      outcome<-if(!is.null(outcome)&&outcome %in% rownames(n$counts)) outcome else rownames(n$counts)[1]
      totals<-colSums(n$counts[,c(first,second),drop=FALSE]);p<-n$counts[outcome,c(first,second)]/totals
      add("Outcome counted as success",outcome);add(paste(first,"success proportion"),fmt(p[1]));add(paste(second,"success proportion"),fmt(p[2]));add("Absolute proportion difference",fmt(abs(diff(p))))
      if(all(totals>=2)&&all(is.finite(p))&&all(p>0&p<1)&&p[1]!=p[2]) proposal<-list(design="proportions",p1=unname(p[1]),p2=unname(p[2]),n=min(totals))
      note<-"Two independent proportions with equal planned group sizes. This is a normal approximation, not Fisher-exact power. Boundary proportions 0 or 1 need external assumptions; no artificial adjustment is made."
    } else note<-"Counts for every population are shown. Multicategory or paired categorical analyses need a matching model; categories are not silently collapsed."
  } else if(layout=="xy") {
    for(g in n$groups) {
      a<-d[d$group==g,,drop=FALSE]
      add(paste(g,"observations / distinct X"),paste(nrow(a),length(unique(a$x)),sep=" / "))
      if(nrow(a)>=3 && length(unique(a$x))>=2) {
        fit<-stats::lm(value~x,data=a)
        add(paste(g,"OLS slope / residual SD"),paste(fmt(stats::coef(fit)[2]),fmt(summary(fit)$sigma),sep=" / "))
        add(paste(g,"Pearson correlation"),fmt(suppressWarnings(stats::cor(a$x,a$value))))
      }
    }
    note<-"XY summaries retain X and series identity. OLS slope, residual SD and Pearson r are descriptive pilot estimates, not nonlinear-fit or correlation power. Replicate observations may be dependent; review experimental units. Use a model-specific Advanced R design for the selected regression/correlation analysis."
  } else if(layout=="grouped") {
    cells<-split(d$value,interaction(d$condition,d$group,drop=TRUE))
    for(cell in names(cells)) {v<-cells[[cell]];add(paste(cell,"N / mean / SD"),paste(length(v),fmt(mean(v)),fmt(stats::sd(v)),sep=" / "))}
    note<-"Summaries are per factor combination; both factors are retained. Two-way effects, interactions and repeated measures require a matching factorial or mixed-model power calculation. Cells are not relabelled as independent one-way groups."
  } else if(layout=="survival") {
    for(g in n$groups) {a<-d[d$group==g,,drop=FALSE];add(paste(g,"subjects / events / event fraction"),paste(nrow(a),sum(a$status),fmt(mean(a$status)),sep=" / "))}
    note<-"Censoring is preserved. Event fractions are pilot estimates, not hazard ratios or log-rank power. Survival planning also requires a target hazard ratio, allocation, accrual and follow-up assumptions; use a matching Advanced R design."
  } else if(layout=="multiple") {
    numeric<-pc_transform_columns(tab,"multiple")
    for(g in numeric) {v<-pc_numeric(tab[[g]],g);v<-v[!is.na(v)];add(paste(g,"N / mean / SD"),paste(length(v),fmt(mean(v)),fmt(stats::sd(v)),sep=" / "))}
    note<-"Numeric-column summaries include possible numeric IDs: review their meaning. PCA has no single t-test effect or universally applicable scalar power calculation. Choose a measurement and explicit comparison/design in Advanced R; metadata are not automatically treated as outcomes."
  }
  if(!is.null(proposal)) note<-paste(note,"Filled N is a pilot-derived starting value (the smallest group size for equal-group planning), not the required sample size. Review inputs and choose Calculate. Changing pilot selectors does not change planning inputs until you fill them again.")
  if(is.null(proposal)) note<-paste(note,"No automatic planning inputs were filled. Zero effects, zero/undefined SD, sparse pilots and unsupported designs are not invented or regularized.")
  list(metrics=do.call(rbind,rows),proposal=proposal,note=note,source=name,layout=layout,method=settings$method)
}
