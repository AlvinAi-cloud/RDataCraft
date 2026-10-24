# Supported Prism JSON is translated to existing RDataCraft contracts, never evaluated as code.
pc_prism_settings <- function(t) {
  s<-pc_defaults();s$layout<-t$layout;s$method<-'descriptive';s$graph<-if(t$layout=='multiple') 'variables' else unname(pc_graphs(t$layout))[1]
  if(t$layout=='xy' && (pc_xy_structure(t$table)$n>1 || isTRUE(t$replicates_in_rows))) s$graph<-'xymean'
  if(isTRUE(t$unresolved_exclusions) && t$layout=='xy') s$graph<-'scatter'
  if(t$layout=="multiple" && length(t$measurement_names)) s$pca_variables<-as.character(jsonlite::toJSON(t$measurement_names,auto_unbox=FALSE))
  s$show_p<-FALSE;s$title<-substr(t$name,1,300);s$x_label<-if(t$layout=='xy') names(t$table)[1] else 'Condition';s$y_label<-'Response'
  n<-pc_normalize(t$table,t$layout,allow_empty=TRUE);s$group1<-if(length(n$groups)) n$groups[1] else '';s$group2<-if(length(n$groups)) n$groups[min(2,length(n$groups))] else ''
  s
}
pc_prism_col <- function(ref,t) {
  if(!is.list(ref) || is.null(ref$col) || is.null(ref$col$uid)) stop('The selected variable has no stable dataset identifier.')
  i<-match(ref$col$uid,t$dataset_ids)
  if(is.na(i)) stop('An analysis depends on a derived or unavailable dataset; its upstream workflow is not converted.')
  names(t$table)[i]
}
pc_prism_analysis <- function(t,a,p) {
  schemas<-c('analyses/two_sample_tests/parameters.schema.json'='T_TESTS_AND_NONPARAMETRIC',
             'analyses/pca/parameters.schema.json'='PCA','analyses/remove_baseline/parameters.schema.json'='REMOVE_BASELINE')
  if(is.null(p$analysisClass) && is.character(p[['$id']]) && p[['$id']] %in% names(schemas)) p$analysisClass<-unname(schemas[[p[['$id']]]])
  if(!identical(a$analysisClass,p$analysisClass) || !is.list(p$content)) stop('Analysis metadata is incomplete or inconsistent.')
  if(isTRUE(t$snapshot)) stop('Saved summary/result snapshots cannot be converted into a raw-observation analysis.')
  if(!isTRUE(a$isAllDataAnalyzed)) stop('A subset or analysis exclusion selection is not yet supported.')
  c<-p$content;cls<-p$analysisClass;s<-pc_prism_settings(t);tab<-t$table;notes<-character()
  if(cls=='T_TESTS_AND_NONPARAMETRIC') {
    if(!identical(c$options$pValueTailType,'P_VALUE_TWO_TAILED') || !identical(c$options$significanceLevel,0.05)) stop('Only two-sided tests with 95% intervals are supported.')
    if(identical(c$experimentalDesign,'UNPAIRED_T_TEST') && t$layout=='column') {
      selected<-vapply(a$inputDataSets,function(x) x$uid,character(1))
      positions<-match(selected,t$dataset_ids)
      if(length(positions)!=2 || anyNA(positions) || anyDuplicated(positions)) stop('The unpaired test needs two distinct, explicitly linked raw data columns.')
      tab<-tab[positions];groups<-names(tab);s$method<-'student';s$layout<-'column';s$graph<-'points'
      s$group1<-groups[1];s$group2<-groups[2]
      if(isTRUE(c$options$swapDirection)) {s$group1<-groups[2];s$group2<-groups[1]}
      notes<-'Recomputed two-sided unpaired Student t test with pooled variance and a 95% interval, using the two linked raw columns and saved comparison direction. Original estimation-plot decoration is not reproduced.'
    } else {
    if(t$layout!='multiple') stop('This two-sample schema requires explicit reconstruction in the preview.')
    # Only this design has been verified against an installed Prism template.
    if(!identical(c$experimentalDesign,'PAIRED_T_TEST')) stop('This two-sample design needs manual reconstruction in the preview.')
    vd<-c$variableDesign
    if(length(vd$responseList)!=1 || length(vd$factorList)!=1) stop('Choose one response and one grouping variable.')
    response<-pc_prism_col(vd$responseList[[1]],t);factor<-pc_prism_col(vd$factorList[[1]],t);subject<-pc_prism_col(vd$subject,t)
    groups<-unique(tab[[factor]]);groups<-groups[!is.na(groups)]
    if(length(groups)!=2 || anyNA(tab[[factor]]) || anyNA(tab[[subject]])) stop('Paired conversion needs two groups and complete subject/group identifiers.')
    if(anyDuplicated(paste(tab[[subject]],tab[[factor]],sep='\r'))) stop('Duplicate subject/group records cannot be interpreted as independent pairs.')
    ids<-unique(tab[[subject]]);out<-data.frame(row.names=seq_along(ids))
    for(g in groups) {rows<-tab[[factor]]==g;out[[g]]<-tab[[response]][which(rows)[match(ids,tab[[subject]][rows])]]}
    tab<-pc_check_table(out);s$layout<-'column';s$method<-'paired';s$graph<-'paired';s$group1<-groups[1];s$group2<-groups[2]
    if(isTRUE(c$options$swapDirection)) {s$group1<-groups[2];s$group2<-groups[1]}
    s$x_label<-factor;s$y_label<-response;notes<-paste('Rows are matched by',subject,'before conversion; edit this working table to rerun the paired test. Source subject order:',paste(ids,collapse=', '))
    }
  } else if(cls=='PCA') {
    if(t$layout!='multiple') stop('PCA requires a multiple-variable source table.')
    if(!c$calc$transform %in% c('STANDARDIZE_DATA','CENTER_DATA')) stop('This PCA preprocessing is not supported.')
    if(isTRUE(c$calc$regression$run)) stop('PCA regression is not implemented.')
    variables<-vapply(c$data$variables,pc_prism_col,character(1),t=t)
    if(length(variables)<2 || anyDuplicated(variables)) stop('PCA requires distinct selected variables.')
    s$method<-'pca';s$graph<-'pcascores';s$pca_variables<-as.character(jsonlite::toJSON(variables));s$pca_scale<-c$calc$transform=='STANDARDIZE_DATA'
    s$pca_missing<-'error'
    if(isTRUE(c$graph$variables$symbolColor$use)) s$pca_group_column<-pc_prism_col(c$graph$variables$symbolColor$variable,t)
    if(isTRUE(c$graph$variables$labels$use) && identical(c$graph$variables$labels$type,'LABEL_TYPE_VARIABLE')) {s$pca_label_column<-pc_prism_col(c$graph$variables$labels$variable,t);s$pca_labels<-TRUE}
    notes<-'Centered SVD PCA and selected variables are converted. Parallel analysis, automatic component-retention rules, biplots, contribution tables and original graph decoration are not reproduced; inspect explained variance to choose components.'
  } else stop(paste('Unsupported analysis class:',cls))
  s$title<-substr(a$title,1,300);s$show_p<-s$layout=='column'
  n<-pc_normalize(tab,s$layout);result<-pc_analyze(n,s$method,s$group1,s$group2,s)
  # Verify a graph can actually be drawn, not just stored as an apparent success.
  ggplot2::ggplot_build(pc_plot(n,s,result))
  views<-if(s$method=='pca') pc_pca_views(s) else list(V1=pc_view(s,'Converted Prism analysis'))
  list(name=substr(paste('R ·',a$title),1,100),layout=s$layout,table=tab,settings=views[[1]]$settings,views=views,conversion=notes,source_id=t$source_id)
}
pc_prism_graph_style <- function(s,g) {
  graph<-g$graph
  if(!is.list(graph) || !identical(graph[['@class']],'MVGraph')) return(s)
  label<-function(v) if(is.list(v$text) && is.character(v$text$string)) substr(v$text$string,1,300) else NULL
  title<-label(graph$title);if(!is.null(title)) s$title<-title
  for(axis in c('X','Y')) {
    a<-graph[[paste0('axis',axis)]];if(is.null(a)) next
    if(length(a$segments)!=1) stop('Broken or multiple-segment axes are not yet converted.')
    seg<-a$segments[[1]];kind<-seg[['@class']]
    if(!identical(kind,'LinearAxisSegment') || isTRUE(seg$isReversed)) stop('Nonlinear or reversed axes require explicit reconstruction in the preview.')
    key<-tolower(axis);s[[paste0('log_',key)]]<-FALSE
    title<-label(a$title);if(!is.null(title)) s[[paste0(key,'_label')]]<-title
    for(pair in list(c('isLowerLimitFixed','lowerLimit','min'),c('isUpperLimitFixed','upperLimit','max'))) if(isTRUE(seg[[pair[1]]])) {
      v<-seg[[pair[2]]];if(!is.numeric(v) || length(v)!=1 || !is.finite(v)) stop('The fixed axis limit is not a finite number.')
      s[[paste0(key,'_',pair[3])]]<-as.character(v)
    }
  }
  pc_validate_axes(s);s
}
pc_prism_graph <- function(t,g) {
  if(isTRUE(t$snapshot)) stop('Saved summary/result values are available as a separate snapshot table; the original graph is not reconstructed.')
  graph<-g$graph
  if(!is.list(graph) || !identical(graph[['@class']],'MVGraph')) stop('Binary graph formatting is unavailable. Use the preview to choose an editable replacement graph.')
  if(!identical(graph$dataSheet,t$source_id) || t$layout!='multiple') stop('Graph references derived data or an unsupported source layout.')
  xs<-unlist(graph$xVariables);ys<-unlist(graph$yVariables)
  if(length(xs)!=1 || !length(ys)) stop('This graph needs one X variable and one or more Y variables.')
  idx<-match(c(xs,ys),t$dataset_ids);if(anyNA(idx) || anyDuplicated(idx)) stop('Graph variables do not match distinct source columns.')
  types<-unlist(graph$gdoTypes$defaults)
  if(!length(types) || any(!types %in% c('symbols','lines'))) stop('This graph-object family is not supported.')
  # Color/size mappings change the grouping contract: reject rather than drop it silently.
  symbol<-graph$gdoSettings$symbols
  if(!is.null(symbol$colorVariable) || !is.null(symbol$sizeVariable)) stop('Variable-mapped symbol color/size needs manual graph reconstruction.')
  tab<-t$table[idx];s<-pc_prism_settings(list(name=g$title,layout='xy',table=tab));s$graph<-if('lines' %in% types) 'line' else 'scatter'
  s<-pc_prism_graph_style(s,g);n<-pc_normalize(tab,'xy');ggplot2::ggplot_build(pc_plot(n,s,pc_analyze(n,'descriptive',s$group1,s$group2,s)))
  list(name=substr(paste('Graph ·',g$title),1,100),layout='xy',table=tab,settings=s,views=list(V1=pc_view(s,'Converted Prism graph')),
    conversion='Editable XY source variables, title, axis titles, linear axes and explicit limits. Colors, shapes, legends, annotations, page geometry and unsupported decorations use RDataCraft defaults.',source_id=t$source_id)
}
