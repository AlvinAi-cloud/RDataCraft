# PCA uses centered SVD via stats::prcomp. No imputation or inferred grouping.
pc_normalize_multiple <- function(tab,allow_empty=FALSE) {
  numbers<-lapply(tab,function(x) suppressWarnings(as.numeric(x)))
  candidates<-names(tab)[vapply(seq_along(tab),function(i) all(is.na(tab[[i]])) || any(!is.na(numbers[[i]])) || any(tolower(tab[[i]]) %in% c('nan','inf','-inf','infinity')),logical(1))]
  parts<-lapply(candidates,function(key) {v<-numbers[[key]];keep<-is.finite(v);data.frame(group=rep(key,sum(keep)),value=v[keep],row_id=which(keep),x=rep(NA_real_,sum(keep)))})
  d<-if(length(parts)) do.call(rbind,parts) else data.frame(group=character(),value=numeric(),row_id=integer(),x=numeric())
  d$group<-factor(d$group,levels=candidates)
  if(!nrow(d) && !allow_empty) stop('Enter numeric variables in columns and observations in rows. Text columns can supply sample labels or groups.',call.=FALSE)
  list(data=d,groups=candidates,missing=sum(is.na(tab[,candidates,drop=FALSE])),layout='multiple',rows=nrow(tab),table=tab)
}
pc_pca_variables <- function(n,s) {
  selected<-if(is.null(s$pca_variables) || identical(s$pca_variables,'')) n$groups else {
    value<-tryCatch(jsonlite::fromJSON(s$pca_variables),error=function(e) NULL)
    if(!is.character(value) && length(value)) stop('Choose PCA variable columns.',call.=FALSE)
    as.character(value)
  }
  if(anyNA(selected) || anyDuplicated(selected) || any(!selected %in% names(n$table))) stop('PCA variable selection refers to missing or duplicate columns.',call.=FALSE)
  setdiff(selected,c(s$pca_label_column,s$pca_group_column))
}
pc_pca <- function(n,s) {
  pc_validate_pca_settings(s)
  if(n$layout!='multiple') stop('PCA requires a Multiple variables table.',call.=FALSE)
  if(s$log_x || s$log_y) stop('Use linear axes for PCA scores, loadings and explained variance.',call.=FALSE)
  for(key in c('pca_label_column','pca_group_column')) if(nzchar(s[[key]]) && !s[[key]] %in% names(n$table)) stop('A selected PCA label/group column is no longer present.',call.=FALSE)
  variables<-pc_pca_variables(n,s)
  if(length(variables)<2L) stop('Choose at least two numeric variables for PCA. Exclude sample IDs and group codes from the variable selection.',call.=FALSE)
  x<-do.call(cbind,lapply(variables,function(key) pc_numeric(n$table[[key]],key)));colnames(x)<-variables
  complete<-stats::complete.cases(x); excluded<-which(!complete)
  if(length(excluded) && s$pca_missing=='error') stop(sprintf('PCA has %d incomplete row(s). Fill the missing cells or explicitly choose complete-row exclusion in PCA settings.',length(excluded)),call.=FALSE)
  if(sum(complete)<3L) stop('PCA needs at least three complete observations and two numeric variables.',call.=FALSE)
  x<-x[complete,,drop=FALSE]
  variation<-apply(x,2,stats::sd)
  if(any(!is.finite(variation) | variation==0)) stop(paste('PCA variables must vary across the included observations. Remove constant columns:',paste(variables[!is.finite(variation) | variation==0],collapse=', ')),call.=FALSE)
  fit<-stats::prcomp(x,center=TRUE,scale.=s$pca_scale)
  count<-min(nrow(x)-1L,ncol(x));fit$sdev<-fit$sdev[seq_len(count)];fit$rotation<-fit$rotation[,seq_len(count),drop=FALSE];fit$x<-fit$x[,seq_len(count),drop=FALSE]
  # Resolve arbitrary SVD signs consistently for saved/exported views.
  signs<-vapply(seq_len(count),function(i) if(fit$rotation[which.max(abs(fit$rotation[,i])),i]<0) -1 else 1,numeric(1))
  fit$rotation<-sweep(fit$rotation,2,signs,'*');fit$x<-sweep(fit$x,2,signs,'*')
  eigenvalues<-fit$sdev^2
  if(any(!is.finite(eigenvalues)) || !is.finite(sum(eigenvalues)) || sum(eigenvalues)<=0) stop('These variable magnitudes cannot produce finite PCA variances. Rescale the input values.',call.=FALSE)
  variance<-eigenvalues/sum(eigenvalues)
  ids<-which(complete);labels<-if(nzchar(s$pca_label_column)) n$table[[s$pca_label_column]][ids] else paste('Row',ids)
  labels[is.na(labels)]<-paste('Row',ids[is.na(labels)])
  groups<-if(nzchar(s$pca_group_column)) n$table[[s$pca_group_column]][ids] else rep('Observations',length(ids));groups[is.na(groups)]<-'(Missing group)'
  scores<-data.frame(row=ids,sample=labels,group=groups,fit$x,check.names=FALSE)
  loadings<-data.frame(variable=variables,fit$rotation,check.names=FALSE)
  scree<-data.frame(component=paste0('PC',seq_len(count)),eigenvalue=eigenvalues,variance_percent=100*variance,cumulative_percent=100*cumsum(variance))
  preprocessing<-data.frame(variable=variables,center=as.numeric(fit$center),scale=if(s$pca_scale) as.numeric(fit$scale) else rep(1,length(variables)),check.names=FALSE)
  notes<-c('Rows are observations; selected numeric columns are variables. PCA is unsupervised and does not test group differences.',
    if(s$pca_scale) 'Variables are mean-centered and divided by their sample SD (unit-variance scaling).' else 'Variables are mean-centered without SD scaling. Variables with larger variances can dominate.',
    'Scores are centered/scaled observations multiplied by eigenvector loadings. Loadings are coefficients, not correlation coefficients. Component signs are arbitrary; this app orients each largest absolute loading positively.',
    if(length(excluded)) sprintf('Complete-row exclusion: %d of %d rows omitted (source row numbers: %s). No missing values were imputed.',length(excluded),n$rows,paste0(paste(head(excluded,20),collapse=', '),if(length(excluded)>20) ', …; full row list in Analysis JSON' else '')) else 'All source rows were included; no missing values were imputed.',
    if(nzchar(s$pca_group_column)) 'Group labels affect point color only; they do not enter the PCA calculation.' else 'No grouping column selected. Numeric IDs and group codes should be excluded from the variables explicitly.')
  list(fit=fit,scores=scores,loadings=loadings,scree=scree,preprocessing=preprocessing,excluded=excluded,variables=variables,notes=notes)
}
pc_analyze_multiple <- function(n,method,s) {
  if(!method %in% c('pca','descriptive')) stop('Choose a supported multiple-variable analysis.',call.=FALSE)
  if(method=='descriptive') {
    result<-pc_result(n,method);result$metrics<-rbind(pc_metric('Source rows',n$rows),pc_metric('Numeric candidate columns',length(n$groups)))
    result$notes<-c('Each row is an observation. Numeric candidate columns are summarized separately; text columns are metadata. Choose PCA to apply its variable selection and preprocessing settings.');return(result)
  }
  z<-pc_pca(n,s);result<-pc_result(n,method);result$title<-'Principal component analysis';result$n<-nrow(z$scores)
  result$metrics<-rbind(pc_metric('Included observations',nrow(z$scores)),pc_metric('Selected variables',length(z$variables)),pc_metric('Excluded incomplete rows',length(z$excluded)),pc_metric('Preprocessing',if(s$pca_scale) 'Centered and scaled to unit variance' else 'Centered, without scaling'),pc_metric('PC1 variance (%)',pc_fmt(z$scree$variance_percent[1])),pc_metric('PC2 variance (%)',pc_fmt(z$scree$variance_percent[2])),pc_metric('PC1 + PC2 variance (%)',pc_fmt(sum(z$scree$variance_percent[1:2]))))
  summary_n<-n;summary_n$data<-n$data[n$data$group %in% z$variables & n$data$row_id %in% z$scores$row,,drop=FALSE];summary_n$groups<-z$variables
  result$summary<-pc_summary(summary_n);result$notes<-z$notes
  result$pca<-z[c('scores','loadings','scree','preprocessing','excluded','variables')]
  result
}
pc_plot_pca <- function(n,s,analysis=NULL) {
  if(s$graph=='variables') {
    if(!nrow(n$data)) stop('Enter numeric measurements to plot variable distributions.')
    return(ggplot2::ggplot(n$data,ggplot2::aes(x='',y=value))+ggplot2::geom_boxplot(width=.35,outlier.shape=NA)+ggplot2::geom_point(position=ggplot2::position_jitter(width=.08,height=0,seed=42),size=s$point_size,color=pc_palettes[[s$palette]][1])+ggplot2::facet_wrap(~group,scales='free_y')+pc_theme(s$font_size)+ggplot2::labs(title=s$title,x=NULL,y=s$y_label))
  }
  pc_validate_pca_settings(s)
  z<-if(!is.null(analysis$pca)) analysis$pca else pc_pca(n,s)
  count<-nrow(z$scree);a<-s$pca_x;b<-s$pca_y
  if(s$graph!='pcascree' && (a>count || b>count || a==b)) stop(sprintf('Choose two distinct available components (PC1–PC%d) in PCA settings.',count),call.=FALSE)
  label<-function(i) sprintf('PC%d (%.1f%%)',i,z$scree$variance_percent[i])
  if(s$graph=='pcascores') {
    d<-z$scores;d$x<-d[[paste0('PC',a)]];d$y<-d[[paste0('PC',b)]]
    groups<-unique(d$group);colors<-setNames(rep(pc_palettes[[s$palette]],length.out=length(groups)),groups)
    p<-ggplot2::ggplot(d,ggplot2::aes(x=x,y=y,color=group))+ggplot2::geom_hline(yintercept=0,color='#d2ded6',linewidth=.35)+ggplot2::geom_vline(xintercept=0,color='#d2ded6',linewidth=.35)+ggplot2::geom_point(size=s$point_size)+ggplot2::scale_color_manual(values=colors)+ggplot2::labs(x=label(a),y=label(b),color=NULL)
    p<-p+ggplot2::scale_x_continuous(expand=ggplot2::expansion(mult=c(.15,.2)))+ggplot2::scale_y_continuous(expand=ggplot2::expansion(mult=c(0,if(s$pca_labels) .3 else .1)))
    if(s$pca_labels) p<-p+ggplot2::geom_text(ggplot2::aes(label=sample),vjust=-.8,size=s$font_size/ggplot2::.pt,show.legend=FALSE,check_overlap=TRUE)
    if(length(groups)==1L) p<-p+ggplot2::guides(color='none')
  } else if(s$graph=='pcaloadings') {
    d<-z$loadings;d$x<-d[[paste0('PC',a)]];d$y<-d[[paste0('PC',b)]]
    d$label<-vapply(d$variable,function(v) paste(strwrap(v,width=18),collapse='\n'),character(1))
    p<-ggplot2::ggplot(d,ggplot2::aes(x=x,y=y))+ggplot2::geom_hline(yintercept=0,color='#d2ded6',linewidth=.35)+ggplot2::geom_vline(xintercept=0,color='#d2ded6',linewidth=.35)+ggplot2::geom_segment(ggplot2::aes(x=0,y=0,xend=x,yend=y),arrow=grid::arrow(length=grid::unit(2,'mm')),color=pc_palettes[[s$palette]][1],linewidth=.65)+ggplot2::geom_text(ggplot2::aes(label=label),vjust=-.6,size=s$font_size/ggplot2::.pt)+ggplot2::scale_x_continuous(expand=ggplot2::expansion(mult=c(.25,.25)))+ggplot2::scale_y_continuous(expand=ggplot2::expansion(mult=c(0,.3)))+ggplot2::labs(x=paste(label(a),'loading'),y=paste(label(b),'loading'))
  } else {
    d<-z$scree;d$index<-seq_len(nrow(d))
    p<-ggplot2::ggplot(d,ggplot2::aes(x=index,y=variance_percent))+ggplot2::geom_col(fill=pc_palettes[[s$palette]][1],width=.65)+ggplot2::geom_line(ggplot2::aes(y=cumulative_percent),color=pc_palettes[[s$palette]][2],linewidth=.7)+ggplot2::geom_point(ggplot2::aes(y=cumulative_percent),color=pc_palettes[[s$palette]][2],size=s$point_size*.7)+ggplot2::scale_x_continuous(breaks=d$index,labels=d$component)+ggplot2::labs(x='Principal component',y='Explained variance (%)',subtitle='Bars: individual variance · line: cumulative variance')
  }
  caption<-paste(if(s$pca_scale) 'Centered · unit-variance scaled' else 'Centered · unscaled',paste(nrow(z$scores),'observations'),paste(length(z$variables),'variables'),sep=' · ')
  if(length(z$excluded)) caption<-paste0(caption,' · ',length(z$excluded),' incomplete rows excluded')
  p+pc_theme(base_size=s$font_size)+ggplot2::theme(legend.position='top',axis.title=ggplot2::element_text(face='bold'),plot.title=ggplot2::element_text(face='bold'),plot.margin=ggplot2::margin(18,22,15,18))+ggplot2::labs(title=s$title,caption=caption)
}
pc_validate_pca_settings <- function(s) {
  for(key in c('pca_x','pca_y')) if(!is.numeric(s[[key]]) || length(s[[key]])!=1L || !is.finite(s[[key]]) || s[[key]]!=floor(s[[key]]) || s[[key]]<1 || s[[key]]>50) stop('PCA component numbers must be whole numbers from 1 to 50.',call.=FALSE)
  if(!is.logical(s$pca_scale) || length(s$pca_scale)!=1L || is.na(s$pca_scale) || !is.logical(s$pca_labels) || length(s$pca_labels)!=1L || is.na(s$pca_labels)) stop('Choose valid PCA display and scaling options.',call.=FALSE)
  if(!is.character(s$pca_missing) || length(s$pca_missing)!=1L || !s$pca_missing %in% c('error','complete')) stop('Choose a supported PCA missing-value policy.',call.=FALSE)
  v<-s$pca_variables
  if(!is.character(v) || length(v)!=1L || is.na(v) || nchar(v)>6000) stop('Choose PCA variable columns.',call.=FALSE)
  if(nzchar(v)) {
    parsed<-tryCatch(jsonlite::fromJSON(v,simplifyVector=FALSE),error=function(e) NULL)
    if(is.null(parsed) || !is.list(parsed) || !is.null(names(parsed)) || length(parsed)>50 || any(!vapply(parsed,function(x) is.character(x) && length(x)==1L && !is.na(x) && nzchar(x) && nchar(x)<=100,logical(1))) || anyDuplicated(unlist(parsed))) stop('Choose distinct PCA variable columns.',call.=FALSE)
  }
  invisible(TRUE)
}
pc_pca_controls <- function(input,session,raw,settings) {
  expected<-shiny::reactiveVal(character())
  shiny::observeEvent(list(raw(),settings()),{
    s<-settings();if(s$layout!='multiple') return()
    tab<-raw();n<-pc_normalize(tab,'multiple',allow_empty=TRUE)
    selected<-tryCatch(pc_pca_variables(n,s),error=function(e) character())
    expected(selected)
    shiny::updateSelectizeInput(session,'pca_variable_pick',choices=names(tab),selected=selected)
    for(key in c('pca_label_column','pca_group_column')) shiny::updateSelectInput(session,key,choices=c('None'='',stats::setNames(names(tab),names(tab))),selected=s[[key]])
  },ignoreInit=FALSE)
  shiny::observeEvent(input$pca_variable_pick,{
    if(settings()$layout!='multiple') return()
    selected<-as.character(input$pca_variable_pick)
    if(identical(selected,shiny::isolate(expected()))) return()
    shiny::updateTextInput(session,'pca_variables',value=jsonlite::toJSON(selected,auto_unbox=FALSE))
  },ignoreNULL=FALSE,ignoreInit=TRUE)
}

pc_pca_rename_settings <- function(s,before,after) {
  rename<-function(values) {i<-match(values,before);keep<-!is.na(i);values[keep]<-after[i[keep]];values}
  for(key in c("pca_label_column","pca_group_column")) s[[key]]<-rename(s[[key]])
  if(nzchar(s$pca_variables)) s$pca_variables<-jsonlite::toJSON(rename(as.character(jsonlite::fromJSON(s$pca_variables))),auto_unbox=FALSE)
  s
}
pc_pca_views <- function(s,start=1L) {
  graphs<-pc_graphs('multiple');graphs<-graphs[graphs %in% c('pcascores','pcaloadings','pcascree')];result<-list()
  for(i in seq_along(graphs)) {
    v<-s;v$method<-'pca';v$graph<-unname(graphs[i]);v$title<-paste0(substr(s$title,1,260),' · ',c('Scores','Loadings','Explained variance')[i]);v$show_p<-FALSE;v$override_x_title<-FALSE;v$override_y_title<-FALSE
    for(key in c('x_min','x_max','y_min','y_max','x_tick_step','y_tick_step','ref_x','ref_y')) v[[key]]<-''
    v$log_x<-FALSE;v$log_y<-FALSE
    result[[paste0('V',start+i-1L)]]<-pc_view(v,names(graphs)[i])
  }
  result
}
