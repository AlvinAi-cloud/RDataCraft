app <- source('app.R')$value
checks <- 0L
check <- function(x,label) {if(!isTRUE(x)) stop('FAIL: ',label,call.=FALSE);checks<<-checks+1L;cat('PASS:',label,'\n')}
near <- function(x,y) isTRUE(all.equal(as.numeric(x),as.numeric(y),tolerance=1e-10))
x <- rep(10^seq(-2,3,length.out=14),each=3)
noise <- rep(c(-.8,.2,.6),14)
tab <- pc_check_table(data.frame(X=x,Reference=4+94*plogis(2.7*(log10(x)-log10(8.4)))+noise,
  Drug=5+95*plogis(3*(log10(x)-log10(3.1)))+noise))
s <- pc_defaults();s$layout<-'xy';s$graph<-'scatter';s$method<-'fourpl';s$group1<-'Reference';s$group2<-'Drug';s$fit_scope<-'all'
n <- pc_normalize(tab,'xy');a <- pc_analyze(n,s$method,s$group1,options=s);before <- a
d <- pc_curve_results(a,n,s)
check(identical(d$series,c('Reference','Drug')),'curve columns retain source-series order')
check(identical(vapply(d$rows,`[[`,character(1),'label'),c('Bottom','Top','EC50','SE of EC50','Hill coefficient','SE of Hill coefficient','R²','Residual SD','Observations (n)')),'four-parameter summary includes the approved compact rows')
value <- function(label) d$rows[[match(label,vapply(d$rows,`[[`,character(1),'label'))]]$cells[[1]]$value
p <- a$parameters[a$parameters$series=='Reference',];get <- function(key,field='estimate') p[p$parameter==key,field]
check(near(value('Bottom'),get('bottom')) && near(value('Top'),get('bottom')+exp(get('logSpan'))),'bottom and top are shown on the response scale')
check(near(value('EC50'),10^get('logEC50')),'EC50 is displayed on the entered X scale')
check(near(value('SE of EC50'),log(10)*10^get('logEC50')*get('logEC50','se')),'EC50 standard error uses the delta method rather than the log-scale SE')
check(near(value('Hill coefficient'),get('hill')) && near(value('SE of Hill coefficient'),get('hill','se')),'Hill estimate and SE use the same model coefficient scale')
check(near(d$rows[[3]]$cells[[1]]$ci,10^c(get('logEC50','ci_low'),get('logEC50','ci_high'))),'EC50 confidence limits retain the fitted log-scale transformation')
check(identical(a,before),'presentation does not alter full analysis metrics, parameters or exports')
html <- as.character(pc_analysis_results_ui(a,n,s))
check(grepl('curve-results-scroll',html,fixed=TRUE) && !grepl('µM',html,fixed=TRUE),'curve table has local scrolling and no invented EC50 concentration unit')
check(!grepl('AIC',html,fixed=TRUE) && any(a$metrics$measure=='AIC'),'omitted technical metrics remain available in the complete analysis')
bad <- tab;bad$Incomplete <- c('5',rep(NA_character_,nrow(bad)-1))
nn <- pc_normalize(bad,'xy');partial <- pc_analyze(nn,'fourpl',s$group1,options=s)
pd <- pc_curve_results(partial,nn,s)
check(tail(pd$status$status,1)=='Not fitted' && all(vapply(pd$rows,function(r) is.na(tail(r$cells,1)[[1]]$value),logical(1))),'failed fits retain a clearly marked column without fabricated estimates')
for(method in c('linear','quadratic','decay')) {
 ss<-s;ss$method<-method
 result<-try(pc_analyze(n,method,ss$group1,options=ss),silent=TRUE)
 if(!inherits(result,'try-error')) check(!is.null(pc_curve_results(result,n,ss)),paste(method,'fits use the same per-curve table without dose-response labels'))
}
ss<-s;ss$fit_replicates<-'mean';aa<-pc_analyze(n,'fourpl',s$group1,options=ss);dd<-pc_curve_results(aa,n,ss)
check(tail(dd$rows,1)[[1]]$label=='Fitted points (n)' && tail(dd$rows,1)[[1]]$cells[[1]]$value==14 && dd$rows[[9]]$cells[[1]]$value==42,'fits to means distinguish source observations from fitted points')
sc<-pc_defaults();nc<-pc_normalize(pc_example('column')$table,'column');ac<-pc_analyze(nc,sc$method,sc$group1,sc$group2,sc)
check(is.null(pc_curve_results(ac,nc,sc)) && grepl('table',as.character(pc_analysis_results_ui(ac,nc,sc)),fixed=TRUE),'ordinary statistical results retain the existing measure/value layout')
shiny::testServer(app,{
 raw(tab);document_open(TRUE);do.call(session$setInputs,s);session$flushReact()
 check(grepl('SE of EC50',output$analysis_metrics$html,fixed=TRUE),'reactive analysis renders the approved fitted-curve table')
})
for(ext in c('rdcraft','rdatacraft')) {
 file<-file.path('artifacts/tests',paste0('extension-roundtrip.',ext));project<-pc_project(tab,s);pc_write_project(project,file)
 check(identical(pc_load_project(file)$table,tab),paste(ext,'opens the same saved study without conversion'))
 check(pc_project_name(paste0('Study.',ext))=='Study',paste(ext,'filename does not become part of the study title'))
}
check(endsWith(pc_study_filename('New study'),'.rdcraft'),'newly suggested study files use rdcraft by default')
csv<-pc_analysis_results_csv(a,n,s)
check(identical(names(csv),c('Parameter / measure','Reference','Drug')),'results CSV retains one column per fitted curve')
check(near(as.numeric(csv[csv[[1]]=='EC50','Reference']),value('EC50')),'results CSV retains EC50 precision before display rounding')
check(near(as.numeric(csv[csv[[1]]=='EC50 95% CI lower','Reference']),d$rows[[3]]$cells[[1]]$ci[1]),'results CSV separates numerical confidence bounds from the estimate')
check(any(pc_analysis_results_csv(partial,nn,s)[[1]]=='Fit detail'),'CSV includes failure reasons for unavailable curves')
check(identical(pc_summary_results_csv(a,n,s)$Measure,c('Residual degrees of freedom','SSE (original Y scale)','Weighted SSE','AIC')),'fitting summary exports the displayed diagnostic measures')
coeff<-pc_parameters_csv(a,n,s)
check(near(as.numeric(coeff[coeff[[1]]=='logEC50 · Standard error','Reference']),get('logEC50','se')),'complete coefficient CSV preserves the actual fitted log-scale SE')
check(grepl('logEC50 = log10(EC50)',as.character(pc_model_details_ui(a,n,s)),fixed=TRUE),'model details explain transformed coefficient scales')
check(identical(a,before),'new summaries and CSVs leave the numerical result unchanged')
for(method in c('linear','quadratic','fourpl')) {
 ss<-s;ss$method<-method
 fit<-pc_analyze(n,method,ss$group1,options=ss)
 check(all(c('Reference','Drug') %in% names(pc_parameters_csv(fit,n,ss))),paste(method,'coefficients align both fitted curves'))
 check(grepl('Fit diagnostics by curve',as.character(pc_summary_results_ui(fit,n,ss)),fixed=TRUE),paste(method,'shows fit diagnostics instead of pooled response summaries'))
}
# Cover the distinct scientific result schemas, rather than assuming every table is a fit.
cases<-list(c('column','welch'),c('column','anova'),c('column','normality'),c('column','multiple'),
 c('column','rm_anova'),c('column','friedman'),c('xy','auc'),c('xy','pearson'),
 c('grouped','twoway'),c('grouped','simpleeffects'),c('contingency','chisquare'),c('survival','kaplan'),c('multiple','pca'))
for(case in cases) {
 ex<-pc_example(case[1]);sn<-pc_normalize(ex$table,case[1]);ss<-pc_defaults();ss$layout<-case[1];ss$method<-case[2];ss$group1<-sn$groups[1];ss$group2<-sn$groups[min(2,length(sn$groups))]
 rr<-pc_analyze(sn,ss$method,ss$group1,ss$group2,ss);copy<-rr
 check(nrow(pc_analysis_results_csv(rr,sn,ss))>0 && nrow(pc_summary_results_csv(rr,sn,ss))>0,paste(case[1],case[2],'has valid results and summary CSVs'))
 markup<-paste(as.character(pc_summary_results_ui(rr,sn,ss)),as.character(pc_model_details_ui(rr,sn,ss)))
 check(nchar(markup)>0 && identical(rr,copy),paste(case[1],case[2],'renders its own result schema without altering inference'))
 if(case[2]=='anova') check(grepl('simultaneous 95%',markup,fixed=TRUE) && grepl('Adjusted P value',markup,fixed=TRUE),'Tukey intervals and adjusted P values are labeled explicitly')
 if(case[2]=='multiple') check(grepl('Unadjusted P value',markup,fixed=TRUE) && grepl('individual 95%',markup,fixed=TRUE),'corrected comparisons retain raw P values and individual intervals')
 if(case[2]=='chisquare') check(identical(pc_expected_counts(rr)$Category,rownames(rr$expected)),'expected counts retain original category labels in UI and CSV')
 if(case[2]=='kaplan') check(!grepl('mean intervals',markup,ignore.case=TRUE),'Kaplan–Meier summaries do not claim mean intervals')
 if(case[2]=='pca') check(grepl('restricted to the observations retained in PCA',markup,fixed=TRUE),'PCA summaries describe only the selected retained data')
}
counts<-pc_normalize(data.frame(Outcome=c('A','B'),p=c(2,5),n=c(4,8)),'contingency');cs<-pc_defaults();cs$layout<-'contingency';cs$method<-'descriptive';cr<-pc_analyze(counts,'descriptive')
check(identical(pc_summary_results_csv(cr,counts,cs)$Measure,c('p','n','Total')),'user-supplied count headers are not renamed as P values or sample sizes')
fake<-data.frame(group1='A',group2='B',p=1e-12)
check(grepl('&lt; 10',as.character(pc_result_table_ui(fake,'Comparisons')),fixed=TRUE),'very small comparison P values use the established threshold display')
shiny::testServer(app,{
 raw(tab);document_open(TRUE);do.call(session$setInputs,s);session$flushReact()
 check(grepl('Fit diagnostics by curve',output$descriptive_table$html,fixed=TRUE) && grepl('parameters_table',output$model_details$html,fixed=TRUE),'reactive summary and details use the model-aware layout')
 path<-output$export_analysis_table
 saved<-read.csv(path,check.names=FALSE)
 check(near(saved[saved[[1]]=='EC50','Reference'],value('EC50')),'Shiny Results CSV download writes the actual fitted result')
 path<-output$export_summary
 check('AIC' %in% read.csv(path,check.names=FALSE)$Measure,'Summary CSV download matches the displayed fit diagnostics')
 path<-output$export_parameters
 check('Drug' %in% names(read.csv(path,check.names=FALSE)),'coefficient download includes every fitted curve')
})
cat(checks,'analysis-display and document-format checks passed.\n')
